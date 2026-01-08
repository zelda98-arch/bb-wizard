# Bug Bounty Wizard v4 - Design Document

## 🎯 **Mission**
Single CLI binary that converts Bugcrowd/HackerOne program URLs → **reportable P4+ bounties** in **≤10 minutes** on Arch Linux. **No filesystem mess, no zombie processes, no WAF bans.**

## 🏗️ **Architecture**

```
Input: https://bugcrowd.com/program
       ↓
[Wizard] → 1. Scope extraction (pup + fallbacks)
         → 2. Subdomain enum (subfinder)
         → 3. Live filter (httpx) 
         → 4. P4+ nuclei (WAF-proof) → scans/nuclei-*.txt
         ↓
Output: 10-50 reportable P4+ vulns ($500+ each)
```

## 📁 **Filesystem (Clean)**
```
~/bb-wizard/                           # Git repo ONLY
├── bb-wizard.fish                    # Single binary
├── projects/                         # Isolated per-program
│   ├── aruba/                        # Self-contained
│   │   ├── recon/live.txt            # 324 live hosts
│   │   ├── scans/nuclei-1537.txt     # P4+ bounties
│   │   └── logs/wizard.log
├── .github/workflows/ci.yml          # Auto-testing
└── README.md
```

## 🔧 **Core Modes**

| Mode | Command | Time | Output | Use Case |
|------|---------|------|--------|----------|
| `full` | `bb-wizard.fish URL` | 8-12min | Full recon + P4+ | New programs |
| `surgical` | `bb-wizard.fish URL --surgical` | 3-5min | P4+ nuclei only | Resume existing |
| `fast` | `bb-wizard.fish URL --fast` | 90sec | Critical only | WAF-heavy targets |

## ⚔️ **Nuclei Battle Config**
```
critical,high,medium + bounty tags:
- cors (P4 $500)
- token/leak (P3 $1500) 
- exposed (P4 $500)
- misconfig (P4 $500)
WAF-proof: -c 5 -rl 25 -mhe 3 -timeout 8
```

## 🛡️ **Failure Modes (Pessimistic)**

| Failure | Mitigation | Recovery |
|---------|------------|----------|
| WAF bans | `-rl 25 -mhe 3` | `--fast` mode |
| Zombie processes | `pkill -f nuclei` trap | Auto-cleanup |
| Empty scope | 5 fallback parsers | Aruba/HackerOne presets |
| No live hosts | Passive subfinder only | Manual scope input |
| Nuclei timeout | `-timeout 8 -retries 1` | Skip + log |

## 📊 **Expected Output (Aruba Reality Check)**

```
324 live hosts × 200 bounty templates = 64K requests
@ 25req/sec = 43 seconds theoretical
+ WAF delays = 3-5 minutes realistic

Expected: 15-45 P4+ hits
- 10-20 CORS misconfigs ($500ea)
- 3-8 exposed panels ($1500ea)
- 2-5 leaks ($1000ea)
```

## 🧪 **Validation Matrix**

| Test | Command | Expected | Fail → |
|------|---------|----------|---------|
| Syntax | `fish -n bb-wizard.fish` | No output | Fix |
| Aruba surgical | `--surgical aruba` | 15+ vulns | WAF tune |
| CI/CD | GitHub Actions | Green ✓ | Ubuntu fix |
| Clean exit | `Ctrl+C` | No zombies | Trap fix |

## 🚨 **Known Production Risks**

1. **Cloudflare fingerprinting** → `-rl 15 --headless`
2. **Enterprise rate limits** → `--fast` + manual pivot  
3. **IPv6 live hosts** → `httpx -ip6`
4. **JSON scope parsing** → Multiple pup selectors

## 📈 **Success Metrics**
```
✅ <10min wall time → reportables
✅ 80%+ live host detection  
✅ 10%+ P4+ hit rate
✅ Zero zombie processes
✅ GitHub CI green
```

## 🎯 **MVP Scope (Week 1)**
```
[x] Single fish binary
[x] Surgical mode (P4+ only) 
[ ] Full recon pipeline
[ ] GitHub Actions CI
[ ] Test suite
[ ] Manual mode (live.txt input)
```

## 💾 **Exit Criteria**
```
~/bb-wizard.fish "aruba" --surgical → 15+ vulns in 5min
git push → GitHub Actions green
No zombies after Ctrl+C
Clean ~/bb-wizard/projects/ structure
```

**This wizard = surgical weapon, not science project.** 324 live Aruba hosts → **$15K+ bounty potential** in 5 minutes. No tangents. No filesystem cancer. Pure reportables.

**Approve design → code → test → ship.** Ready?


## Overview

`bb-wizard.fish` turns a Bugcrowd/HackerOne program URL or slug into:

- Scoped targets (`scope.txt`)
- Subdomains (`subs-quick.txt`)
- Live hosts (`live.txt`)
- A WAF-safe nuclei scan with P4+‑relevant severities into `scans/nuclei-*.txt`

You’ve validated this flow on HPE Aruba with 5 scope entries, 1964 subs, 323 live hosts, and a real nuclei candidate. 

***

## Installation \& prerequisites

From a Garuda/Arch box:

- Fish shell (4.x)
- `nuclei`, `subfinder`, `httpx`, `pup`, `curl` on `$PATH`
- Nuclei templates synced in `~/nuclei-templates` (already present on your box). 

In `~/bb-wizard`:

- `bb-wizard.fish` (executable)
- `projects/` and `logs/` will be created automatically.

***

## Directory layout

From repo root:

```text
bb-wizard/
├── bb-wizard.fish
├── README.md
├── logs/
│   ├── wizard.log
│   └── errors.log
└── projects/
    └── aruba/
        ├── recon/
        │   ├── scope.txt
        │   ├── subs-quick.txt
        │   └── live.txt
        └── scans/
            ├── nuclei-YYYYMMDD-HHMMSS.txt
            └── nuclei-test.txt
```

- `recon/` is the **resume point**: `live.txt` is the input for surgical scans. 
- `scans/` is the **output**: each nuclei run writes `nuclei-<timestamp>.txt`. 

***

## Basic commands

From `~/bb-wizard`:

### 1) Recon (build `live.txt`)

Use either a URL or a slug:

```fish
./bb-wizard.fish "https://bugcrowd.com/aruba"
# or
./bb-wizard.fish aruba
```

What this does:

- Derives `slug` = `aruba` from URL/slug. 
- Extracts scope via Bugcrowd page + Aruba hardcoded fallback into `projects/aruba/recon/scope.txt`. 
- Runs `subfinder -dL scope.txt` → `subs-quick.txt`.
- Runs `httpx` over subs → `live.txt`.
- Prints a summary like:

```text
[INFO] Live hosts written to .../projects/aruba/recon/live.txt: 323
[+] Recon complete: 323 live hosts into .../live.txt
[+] Now run: ./bb-wizard.fish aruba --surgical
status: 0
```


Expected post‑recon sanity checks:

```fish
wc -l projects/aruba/recon/scope.txt        # ~5 for Aruba
wc -l projects/aruba/recon/subs-quick.txt   # ~2000
wc -l projects/aruba/recon/live.txt         # ~300+
```


***

### 2) Surgical mode (nuclei only)

Once `live.txt` is non‑empty:

```fish
./bb-wizard.fish aruba --surgical
# or
./bb-wizard.fish "https://bugcrowd.com/aruba" --surgical
```

Behavior:

- Validates `projects/aruba/recon/live.txt` exists and has >0 lines. If not, it prints:

```text
[-] live.txt is empty for aruba. Run full recon first.
```

- Runs a single nuclei pass:

```text
nuclei -l live.txt \
  -severity critical,high,medium \
  -c 5 -rl 25 -mhe 3 -timeout 8 -retries 1 \
  -o projects/aruba/scans/nuclei-YYYYMMDD-HHMMSS.txt
```

- Uses a `trap` to `pkill nuclei` on Ctrl+C, avoiding zombies. 
- Prints a summary, for example:

```text
⚔ RESUME: /home/joandarc/bb-wizard/projects/aruba (323 live hosts)
💥 P4+ nuclei: 3-5min scan → 1 candidates
💰 scans/nuclei-20260106-132120.txt (report these NOW)
status: 0
```


***

## Reading results

After a surgical run:

```fish
ls -l projects/aruba/scans
wc -l projects/aruba/scans/nuclei-*.txt
head -20 projects/aruba/scans/nuclei-20260106-132120.txt
```

A typical hit line (your Aruba example):

```text
[shibboleth-open-redirect] [http] [medium] [https://arubapedia.arubanetworks.com/Shibboleth.sso/Logout?return=...]
```

- Each line is a **candidate vuln** that you should manually reproduce and map to program scope/severity. 
- Use the template name (`shibboleth-open-redirect`) and URL to construct a Bugcrowd/HackerOne report.

***

## Error cases \& recovery

- **Missing tools**: `log ERROR "Missing subfinder"` or `httpx`/`nuclei` in `logs/errors.log`. Install them and rerun. 
- **Empty `live.txt` after recon**: script exits with:

```text
[-] Recon completed but live.txt is empty for <slug> at <path>.
```

In that case, check `scope.txt` and `subs-quick.txt` to see if scope is too narrow, or add additional root domains to `scope.txt` manually and rerun. 
- **Ctrl+C mid‑scan**: nuclei is killed via trap; you can re‑run surgical later with the same `live.txt`.

***

This captures the weapon **as it exists today**: recon + surgical on HPE Aruba with a clean filesystem layout, no zombies, and validated hits. From here, you can move on to triaging that Shibboleth open redirect and then iterating on template tags/rest of the modes. 

<div align="center">⁂</div>




## 🧭 Usage Guide (Current State)

### Overview

\`bb-wizard.fish\` turns a Bugcrowd/HackerOne program URL or slug into scoped targets, subdomains, live hosts, and a WAF-safe nuclei scan:

- Scope → \`projects/<slug>/recon/scope.txt\`
- Subdomains → \`projects/<slug>/recon/subs-quick.txt\`
- Live hosts → \`projects/<slug>/recon/live.txt\`
- Nuclei hits → \`projects/<slug>/scans/nuclei-*.txt\`

Validated on HPE Aruba with 5 scope entries, 1964 subdomains, 323 live hosts, and a real nuclei candidate. [file:1]

### Directory layout

\`\`\`
bb-wizard/
├── bb-wizard.fish
├── README.md
├── logs/
│   ├── wizard.log
│   └── errors.log
└── projects/
    └── aruba/
        ├── recon/
        │   ├── scope.txt
        │   ├── subs-quick.txt
        │   └── live.txt
        └── scans/
            └── nuclei-YYYYMMDD-HHMMSS.txt
\`\`\`

### Recon (build live.txt)

\`\`\fish
./bb-wizard.fish "https://bugcrowd.com/aruba"
# or
./bb-wizard.fish aruba
\`\`\`

Example Aruba run:

- \`scope.txt\`: 5 lines
- \`subs-quick.txt\`: 1964 lines
- \`live.txt\`: 323 lines [file:1]

### Surgical mode (nuclei only)

\`\`\fish
./bb-wizard.fish aruba --surgical
# or
./bb-wizard.fish "https://bugcrowd.com/aruba" --surgical
\`\`\`

Behavior:

- Validates \`live.txt\` exists and is non-empty; otherwise exits with a clear message.
- Runs nuclei with WAF-safe settings:

  \`-severity critical,high,medium -c 5 -rl 25 -mhe 3 -timeout 8 -retries 1\`. [file:1]

Example Aruba hit:

\`\`\text
[shibboleth-open-redirect] [http] [medium] [https://arubapedia.arubanetworks.com/Shibboleth.sso/Logout?return=...](https://arubapedia.arubanetworks.com/Shibboleth.sso/Logout?return=...)
⚔ RESUME: .../projects/aruba (323 live hosts)
💥 P4+ nuclei: 3-5min scan → 1 candidates
💰 scans/nuclei-20260106-132120.txt (report these NOW)
\`\`\`

