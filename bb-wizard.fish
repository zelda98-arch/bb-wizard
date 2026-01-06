#!/usr/bin/env fish

function log -a level message
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" | tee -a $log_file $err_file
end

function check_tool -a tool
    if not command -q $tool
        log ERROR "Missing $tool"
        return 1
    end
    return 0
end

function extract_bugcrowd_scope -a url
    log INFO "Extracting Bugcrowd scope from $url"
    
    # Method 1: Bugcrowd selectors
    curl -s "$url" | pup '.in-scope-targets text{}, .target text{}, [data-testid="target"] text{}' 2>/dev/null | \
    grep -Ei '(\*\.)|([0-9]{1,3}\.[0-9]{1,3}\.)' | head -50 | sort -u > $scope_file
    
    # Method 2: Domain grep fallback
    if test (wc -l < $scope_file 2>/dev/null | tr -d ' ') -eq 0
        curl -s "$url" | grep -Ei '(\*\.[a-z0-9-]+\.(com|net|org|io))' | \
        grep -v -E '(bugcrowd|google|hackerone)' | sort -u > $scope_file
    end
    
    # Method 3: Aruba hardcoded (this WILL work)
    if test (wc -l < $scope_file 2>/dev/null | tr -d ' ') -eq 0
        log WARN "Using Aruba hardcoded scope"
        echo "*.arubanetworks.com" > $scope_file
        echo "*.arubainstanton.com" >> $scope_file
        echo "*.arubacentral.com" >> $scope_file
        echo "*.arubaclearpass.com" >> $scope_file
        echo "*.arubaairwave.com" >> $scope_file
    end
    
    set count (wc -l < $scope_file 2>/dev/null | tr -d ' ')
    log INFO "Scope ready: $count targets"
    head -3 $scope_file
    return 0
end

function scan_loop
    set cycle 1
    set no_new 0
    
    while true
        log INFO "=== CYCLE $cycle ==="
        
        # Targets: scope or prior leads
        if test -f $leads_file; and test (wc -l < $leads_file 2>/dev/null | tr -d ' ') -gt 0
            set targets $leads_file
        else
            set targets $scope_file
        end
        
        # Subfinder
        if check_tool subfinder
            subfinder -dL $targets -silent -o $project_dir/recon/subs-$cycle.txt 2>> errors.log
            set subs (wc -l < $project_dir/recon/subs-$cycle.txt 2>/dev/null | tr -d ' ' || echo 0)
            log INFO "Subs found: $subs"
        end
        
        # Live hosts
        if test -f $project_dir/recon/subs-$cycle.txt; and check_tool httpx
            cat $project_dir/recon/subs-$cycle.txt | httpx -silent -o $project_dir/recon/live-$cycle.txt 2>> errors.log
            set live (wc -l < $project_dir/recon/live-$cycle.txt 2>/dev/null | tr -d ' ' || echo 0)
            log INFO "Live hosts: $live"
        end
        
        # Nuclei scan
        if test -f $project_dir/recon/live-$cycle.txt; and check_tool nuclei
            nuclei -l $project_dir/recon/live-$cycle.txt -o $project_dir/scans/nuclei-$cycle.txt -severity critical,high,medium -silent 2>> errors.log
            set vulns (wc -l < $project_dir/scans/nuclei-$cycle.txt 2>/dev/null | tr -d ' ' || echo 0)
            log INFO "Vulns found: $vulns"
        end
        
        # Update leads file
        find $project_dir/recon -name "*.txt" 2>/dev/null | xargs cat 2>/dev/null | sort -u | grep . > $leads_file 2>/dev/null
        
        # Check progress
        set live_count (wc -l < $project_dir/recon/live-$cycle.txt 2>/dev/null | tr -d ' ' || echo 0)
        if test $live_count -eq 0
            set no_new (math $no_new + 1)
            if test $no_new -ge 3
                log INFO "No live hosts x3 - stopping"
                break
            end
        else
            set no_new 0
        end
        
        if test $cycle -ge 6
            log INFO "Max cycles reached"
            break
        end
        
        sleep 3
        set cycle (math $cycle + 1)
    end
end

function quick_recon -a slug target live_file recon_dir
    # For now, Aruba-only: derive scope using existing helper + hardcoded fallback.
    set scope_file $recon_dir/scope.txt
    log INFO "Quick recon for $slug -> scope + subfinder + httpx"

    # Use Bugcrowd scope extraction if target is a URL, else Aruba hardcoded.
    if string match -rq '^https?://' -- $target
        extract_bugcrowd_scope $target
        # extract_bugcrowd_scope writes to $scope_file in old code,
        # so ensure that variable is set for compatibility.
    else
        # bare slug: just seed Aruba scope directly
        printf '%s\n' \
            "*.arubanetworks.com" \
            "*.arubainstanton.com" \
            "*.arubacentral.com" \
            "*.arubaclearpass.com" \
            "*.arubaairwave.com" > $scope_file
    end

    if not test -f $scope_file
        log ERROR "Scope file not created at $scope_file"
        return 1
    end

    set scope_count (wc -l < $scope_file 2>/dev/null | tr -d ' ')
    log INFO "Scope entries: $scope_count"

    # Subfinder
    if not check_tool subfinder
        log ERROR "subfinder missing; cannot build live.txt"
        return 1
    end

    set subs_file $recon_dir/subs-quick.txt
    subfinder -dL $scope_file -silent -o $subs_file 2>>$err_file
    set subs_count (wc -l < $subs_file 2>/dev/null | tr -d ' ')
    log INFO "Subdomains found: $subs_count"

    # httpx to discover live hosts
    if not check_tool httpx
        log ERROR "httpx missing; cannot build live.txt"
        return 1
    end

    cat $subs_file | httpx -silent -o $live_file 2>>$err_file
    set live_count (wc -l < $live_file 2>/dev/null | tr -d ' ')
    log INFO "Live hosts written to $live_file: $live_count"
end

# MAIN EXECUTION

# Args: <url-or-slug> [--surgical]
if test (count $argv) -lt 1
    echo "Usage: bb-wizard.fish <program_url|slug> [--surgical]" >&2
    exit 1
end

set mode "full"
if contains -- "--surgical" $argv
    set mode "surgical"
end

set target $argv[1]

# derive slug from URL or accept as-is
if string match -rq '^https?://' -- $target
    set clean (string replace -r '^https?://(www\.)?' '' -- $target)
    set clean (string replace -r '/+$' '' -- $clean)
    set slug (string replace -r '^.*/' '' -- $clean)
else
    set slug $target
end

# project layout under repo root
set repo_dir (pwd)
set project_dir $repo_dir/projects/$slug
set recon_dir $project_dir/recon
set scans_dir $project_dir/scans
set logs_dir $repo_dir/logs

mkdir -p $recon_dir $scans_dir $logs_dir
set live_file $recon_dir/live.txt
set log_file $logs_dir/wizard.log
set err_file $logs_dir/errors.log
set scope_file $recon_dir/scope.txt

if test "$mode" = "surgical"
    if not test -f $live_file
        echo "[-] live.txt not found for $slug at $live_file. Run full recon first." >&2
        exit 1
    end

    set live_count (wc -l < $live_file 2>/dev/null | tr -d ' ')
    if test "$live_count" = "0"
        echo "[-] live.txt is empty for $slug. Run full recon first." >&2
        exit 1
    end

    set ts (date +%Y%m%d-%H%M%S)
    set out_file $scans_dir/nuclei-$ts.txt

    trap 'pkill -f "nuclei -l $live_file"; exit 1' INT TERM

    log INFO "Starting surgical nuclei scan for $slug ($live_count live hosts)"

    nuclei -l $live_file \
        -severity critical,high,medium \
        -c 5 -rl 25 -mhe 3 -timeout 8 -retries 1 \
        -o $out_file 2>>$err_file

    set vuln_count (wc -l < $out_file 2>/dev/null | tr -d ' ')

    echo "⚔️ RESUME: $project_dir ($live_count live hosts)"
    echo "💥 P4+ nuclei: 3-5min scan → $vuln_count candidates"
    echo "💰 scans/"(basename $out_file)" (report these NOW)"
    exit 0
end

# minimal recon for now: build live.txt then instruct user to rerun --surgical
if test "$mode" != "surgical"
    log INFO "Minimal recon mode: building live.txt for $slug"

    # ensure recon directories and logging are set up (already done above)
    quick_recon $slug $target $live_file $recon_dir

    set live_count (wc -l < $live_file 2>/dev/null | tr -d ' ')
    if test "$live_count" = "0"
        echo "[-] Recon completed but live.txt is empty for $slug at $live_file." >&2
        echo "    Try adjusting scope or running tools manually." >&2
        exit 1
    end

    echo "[+] Recon complete: $live_count live hosts into $live_file"
    echo "[+] Now run: ./bb-wizard.fish $slug --surgical"
    exit 0
end
