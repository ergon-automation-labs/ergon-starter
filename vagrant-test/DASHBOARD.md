# Phase Status Dashboard

Quick at-a-glance view of all test phases: pass/fail + duration + last run time.

## Usage

```bash
cd vagrant-test
make dashboard
```

Or directly on the VM:
```bash
vagrant ssh -c "bash ./scripts/status-dashboard.sh"
```

## What It Shows

A table with:
- **Phase** — Which phase (01 install pristine, 02 install fixed, 03 verify, 04 pack matrix)
- **Result** — PASS ✓ | FAIL ✗ | RUN (in progress) | — (not run)
- **Duration** — How long that phase took (e.g., 5m23s)
- **Last Run** — ISO timestamp of the last test completion

## Example Output

```
Bot Army Starter — Phase Status Dashboard

2026-09-06 16:30:45 EEST (vagrant-ubuntu)

┌─────────┬──────────┬──────────┬────────────┐
│ Phase   │ Result   │ Duration │ Last Run   │
├─────────┼──────────┼──────────┼────────────┤
│ Phase 01 │ ✓ PASS   │ 12m34s   │ 2026-09-06 │
│ Phase 02 │ ✓ PASS   │ 18m22s   │ 2026-09-06 │
│ Phase 03 │ ✓ PASS   │ 3m45s    │ 2026-09-06 │
│ Phase 04 │ ⊘ —      │ —        │ —          │
└─────────┴──────────┴──────────┴────────────┘

Summary:
  Passed: 3 | Failed: 0 | Running: 0 | Not Run: 1

⚠️  Phase 04 (pack matrix) not yet run
   → Next: make phase04 (validates individual starter packs)

Commands:
  make phase04                 # Run pack matrix tests
  make phase04-pack PACK=Primary # Test one pack
  vagrant ssh -c 'tail -f ~/logs/04-pack-matrix.log' # Watch live
```

## How to Use It

### Before starting a test run
```bash
make dashboard  # Check baseline
```

### To watch progress live
```bash
# Terminal 1: Dashboard polling
watch -n 10 "make dashboard"  # Refresh every 10s

# Terminal 2: Tailed logs
vagrant ssh -c "tail -f ~/logs/04-pack-matrix.log"
```

### After a phase completes
```bash
make dashboard  # See updated pass/fail + timing
```

## Dashboard Status Codes

| Status | Meaning |
|--------|---------|
| **✓ PASS** | Phase completed successfully |
| **✗ FAIL** | Phase ran but had failures (check logs) |
| **RUN** | Phase is currently running (check again in a few mins) |
| **—** | Phase not yet run (logs don't exist) |

## Understanding the Recommendations

The dashboard gives context-aware suggestions:

- ✅ **All phases PASS** → Distribution ready; safe to document/publish
- ⚠️ **Phase 03 PASS, 04 not run** → Next: run `make phase04`
- ⚠️ **Phase 02 PASS, 03 not run** → Next: run `make verify`
- 🔴 **Any phase FAIL** → Check logs; fix blocking issue; re-run

## Logs

Each phase writes its own log:
- Phase 01: `logs/01-stream.txt`
- Phase 02: `logs/02-install-fixed.log`
- Phase 03: `logs/03-verify.log`
- Phase 04: `logs/04-pack-matrix.log`

```bash
# View full log for a phase
vagrant ssh -c "cat ~/logs/04-pack-matrix.log | tail -100"

# Search for errors
vagrant ssh -c "grep -i error ~/logs/04-pack-matrix.log"
```

## Automation (Optional)

Watch the dashboard continuously:
```bash
while true; do
  clear
  vagrant ssh -c "bash ./scripts/status-dashboard.sh"
  sleep 30
done
```

Or use a scheduled check:
```bash
# Add to your crontab to check every hour
0 * * * * cd /path/to/bot-army-starter/vagrant-test && make dashboard >> ~/.bot-army-dashboard-poll.log 2>&1
```

## Implementation Details

The dashboard reads:
1. **Log files** (`~/logs/*.log`) on the vagrant VM
2. **Timestamps** in phase logs (ISO 8601 format)
3. **Result markers** (grep for "RESULT: PASS" / "RESULT: FAIL")
4. **Duration** (calculated from first/last log timestamp)

No persistent state — always reads fresh from logs. Re-run anytime to see current status.
