# Phase 04 — Pack Combination Validation

**Goal:** Verify that realistic combinations of Bot Army starter packs work together. Users select multiple packs in the wizard → system generates one `docker-compose.yml` with all selected bots → everything runs on shared NATS + PostgreSQL.

## Why This Matters

Users don't pick one pack in isolation—they compose their fleet by selecting multiple packs. Phase 04 proves:
1. ✅ Multiple packs can run together in a single `docker compose up`
2. ✅ All bots respond on their subjects (shared NATS cluster)
3. ✅ Database schema handles all bots' migrations  
4. ✅ Users get a working, integrated multi-pack fleet

## What It Tests

**Core Tier (must pass):**

| Combo | Packs | What It Validates |
|-------|-------|-------------------|
| **Primary** | Primary | GTD + Bridge works alone |
| **Primary+Learning** | Primary + Learning | Task management + knowledge together (GTD + Terrain + Docs) |
| **Primary+Social** | Primary + Social | Task management + chat together (GTD + Synapse + Discord) |
| **Primary+Learning+Social** | All three | Full featured fleet (all 3 packs integrated) |

**Extended Tier (nice to have):**

| Combo | Packs | Notes |
|-------|-------|-------|
| **Primary+Background** | Primary + Background | Foreground + async LLM/feeds |
| **Learning+Research** | Learning + Research | Knowledge + content aggregation  |
| **Primary+Learning+Social+Background** | All four | Maximum fleet capacity test |

## How It Works

For each combination:
1. **Load Config** — Read pack list + expected NATS subjects from `04-pack-combinations.json`
2. **Clone** — Fresh copy of bot-army repo (isolated test environment)
3. **Generate** — Call `quickstart-default.sh` with selected packs → generates `docker-compose.yml` with all bots
4. **Boot** — `docker compose up -d --build` (per-combo timeout, e.g. 60-150s)
5. **Verify** — Test all NATS subjects for the combo work (3s timeout per subject)
6. **Check** — Inspect container state (running, restart count ≤ 2)
7. **Report** — Pass/Fail per combo + overall summary

Each combo gets its own log file: `logs/04-combo-Primary+Learning.log`, etc.

## Running

### Test Core Tier (default)
```bash
cd vagrant-test
make phase04
# or
vagrant ssh -c "bash ./scripts/04-pack-matrix.sh"
```

### Test Extended Tier
```bash
vagrant ssh -c "RUN_TIER=extended bash ./scripts/04-pack-matrix.sh"
```

### Test One Combo
Currently, all combos in a tier run together. To test just one combo, modify the script or extract it.

## Watching Progress

From the host (no SSH needed):
```bash
cd vagrant-test
make watch-04           # Live tail of phase 04 output
make dashboard          # Quick status check
```

## Logs & Results

- **Phase log**: `logs/04-pack-combinations.log` (wrapper output, clones, boots, etc.)
- **Per-combo logs**: `logs/04-combo-Primary+Learning.log`, etc.
- **Results JSON**: `logs/04-pack-results.json` (machine-parseable pass/fail + metrics)

## Understanding Failures

### Subject doesn't respond
- Bot crashed or didn't start → check `logs/04-combo-*.log`
- Wrong NATS subject name → verify in `04-pack-combinations.json`
- Subject never populated → might be a startup race condition, check logs for errors

### Container restart looping
- Docker build failed → check `docker compose logs <bot>`
- Runtime error (missing dep, config) → check bot logs
- Resource starvation → check `docker stats` or VM memory

### Combo generation fails
- Missing bot repo → check `repos/` were cloned
- Dockerfile issue → run `docker compose build <bot>` manually to see error

## Configuration

Pack combinations live in: `vagrant-test/config/04-pack-combinations.json`

To add a new combo or change subjects:
```json
{
  "combos": {
    "MyCustomCombo": {
      "description": "My custom bot set",
      "packs": ["Primary", "Learning"],
      "bots": ["gtd_bot", "terrain_bot", ...],
      "subjects": [
        "bridge.task.list",
        "terrain.lesson.generate",
        ...
      ],
      "tier": "extended",
      "timeout_seconds": 90
    }
  }
}
```

## Next Steps

**Phase 04 is combo-focused. Future enhancements:**
- Phase 04.5: Pack switching + data persistence (can you add Learning bots to Primary-only after deploy?)
- Phase 05: Performance under load (many packs, large datasets)
- Monitoring dashboard: real-time health per combo (CPU, memory, NATS latency)

---

## See Also

- `PITFALLS.md` — Known issues & fixes (P1–P7)
- `03-verify.sh` — Infra health checks (NATS, PostgreSQL, etc.)
- `04-pack-matrix.sh` — The test runner
- `04-pack-combinations.json` — Combo definitions + subjects
- `DASHBOARD.md` — Live progress watching from host
