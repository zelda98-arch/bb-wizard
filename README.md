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
