#!/usr/bin/env fish

function log -a level message
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" | tee -a $project_dir/logs/wizard.log errors.log
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

# MAIN EXECUTION
if test (count $argv) -ne 1
    echo "Usage: bb-wizard-v2.fish <program_url>"
    exit 1
end

set program_url $argv[1]
set timestamp (date +%Y%m%d-%H%M%S)
set project_dir ~/bb/$timestamp
set scope_file $project_dir/scope.txt
set leads_file $project_dir/recon/leads.txt

mkdir -p $project_dir/{recon,scans,logs}
touch $project_dir/logs/{wizard.log,errors.log}

log INFO "Aruba Wizard started: $program_url"
extract_bugcrowd_scope $program_url
scan_loop

log INFO "✅ COMPLETE - check $project_dir/scans/"
echo "🎯 Results: $project_dir" | lolcat 2>/dev/null; or echo "Results: $project_dir"
