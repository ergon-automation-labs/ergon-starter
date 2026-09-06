# Phase 04 — Pack Combination Validation

**Goal:** Verify that realistic combinations of Bot Army starter packs work together. Users select multiple packs in the wizard → system generates one `docker-compose.yml` with all selected bots → everything runs on shared NATS + PostgreSQL.

> **P10/2026-09-06 rewrite:** the first draft referenced pack names that don't
> exist in `catalog/packs.json` ("Primary", "Learning", "Social" — silent
> no-ops that generated identical 12-bot fleets) and hand-maintained subject
> lists that had already drifted. The harness now:
>
> - uses **real pack keys**: `core`, `learning_deepdive`, `social_media`,
>   `areas`, `research`;
> - selects bots through the `PACKS` env in `quickstart-default.sh` (union of
>   pack bots ∩ catalog, unknown names skipped, catalog order kept);
> - verifies **empirically** via the live NATS registry
>   (`bot_army.registry.bots.list`), container health, and the P10
>   log-regression grep — no static subject lists to rot;
> - tears the main stack down before the run and `down -v` between combos
>   (host ports are sequential-safe); ollama model blobs live in one shared
>   external volume so each combo doesn't re-pull 7 GB;
> - discovers each selected bot's postgres database name from the bot's own
>   repo config and appends it to the generated init SQL (P8 generalized —
>   the catalog's needs_db flag is unreliable).

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
| **Core** | core | Baseline: the core pack alone (12 bots) |
| **Core-LearningDeepdive** | core + learning_deepdive | Knowledge deep-dive (terrain, internal_docs) |
| **Core-SocialMedia** | core + social_media | Media pipeline (youtube_manager, media_ingestion) |
| **Core-Research** | core + research | Research feeds (feeds, rss_polling) |

**Extended Tier (nice to have):**

| Combo | Packs | Notes |
|-------|-------|-------|
| **Core-Areas** | core + areas | Personal areas (fitness, chore, rpg) |
| **Core-Full** | core + all add-on packs | Maximum fleet capacity test |

The combos live in `config/04-pack-combinations.json`; expected bot sets are
computed from `catalog/packs.json` at run time, never stored.

## How It Works

For each combination:
1. **Load Config** — Read pack list from `config/04-pack-combinations.json`
2. **Fetch** — CDN clone of the starter repo into the combo dir (what a user would get); `repos/` kept as build cache
3. **Generate** — Call `quickstart-default.sh` with `PACKS=<packs>` → generates `.env`, `docker-compose.yml` (+ dynamic DB init SQL)
4. **Boot** — `docker compose up -d --build` (build ceiling 30 min; ollama models from the shared volume)
5. **Verify** — registry bot set (live NATS request) + container state (running, restarts ≤ 2) + P10 log-regression grep
6. **Teardown** — `docker compose down -v` (fresh DBs next run; shared ollama volume survives)
7. **Report** — JSONL results + per-combo logs

Each combo gets its own log file: `~/logs/04-combo-<name>.log` (synced to
`/vagrant/logs/` for combo + combination logs).

## Running

### Test Core Tier (default)
```bash
cd vagrant-test
vagrant ssh -c "bash /vagrant/scripts/04-pack-matrix.sh"
```

### Test Extended Tier
```bash
vagrant ssh -c "RUN_TIER=extended bash /vagrant/scripts/04-pack-matrix.sh"
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
- **Per-combo logs**: `~/logs/04-combo-<name>.log` (VM), combo+combination logs synced to `/vagrant/logs/`
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
