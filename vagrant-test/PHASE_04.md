# Phase 04 — Bot Pack Matrix Validation

**Goal:** Verify that each Bot Army "starter pack" (Primary, Learning, Background, etc.) works end-to-end in isolation.

## Why This Matters

Users select a pack when they run the installer. The pack determines which bots they get. Phase 04 proves:
1. Each pack's bot set boots without crash-loops
2. Pack-specific NATS subjects (e.g., `bridge.task.list` for Primary) respond
3. Users picking a pack end up with a working, usable fleet — not a broken subset

## What It Tests

| Pack | Description | Key Subjects Tested |
|------|-------------|-------------------|
| **Primary** | GTD + Bridge + essentials | `bridge.task.list`, `bridge.internal_docs.query` |
| **Learning** | Terrain + Internal Docs + Graphify | `terrain.lesson.generate`, `internal_docs.query` |
| **Background** | LLM service + feeds + jobs (headless) | `llm.request.converse`, `job_applications.query` |
| **Social** | Synapse + chat bridges | `bridge.chat`, `synapse.command.dispatch` |
| **Research** | RSS + Job aggregation + media | `rss_polling.refresh`, `media_ingestion.ingest` |
| **Infrastructure** | SRE + observability | `system.health.sre`, `factory_breaker.query` |

## How It Works

For each pack:
1. **Clone** — Fresh copy of bot-army repo for isolation
2. **Generate** — Create a `docker-compose.yml` with just that pack's bots
3. **Boot** — `docker compose up -d --build` (60s boot window)
4. **Verify** — Test pack-specific NATS subjects (request/reply 3s timeout)
5. **Check** — Inspect container state (running, restart count ≤ 2)
6. **Report** — Pass/Fail per pack + overall summary

Each pack gets its own log file: `logs/04-pack-Primary.log`, etc.

## Running

### Test All Packs
```bash
cd vagrant-test
make phase04
# or
vagrant ssh -c "bash ./scripts/04-pack-matrix.sh"
```

### Test One Pack
```bash
make phase04-pack PACK=Primary
# or
vagrant ssh -c "PACK=Primary bash ./scripts/04-pack-matrix.sh"
```

### View Results
```bash
# Real-time status
vagrant ssh -c "tail -f ~/logs/04-pack-matrix-status.txt"

# Per-pack logs
vagrant ssh -c "ls -lh ~/logs/04-pack-*.log"

# Detailed JSON results
vagrant ssh -c "cat ~/logs/04-pack-matrix-results.json | jq ."
```

## Resumability

Phase 04 is resumable: if it fails mid-run (network glitch, resource exhaustion), re-running the same command picks up where it left off using completion markers in `~/.phase04/markers/`.

To force a fresh run:
```bash
vagrant ssh -c "rm -rf ~/.phase04/markers && bash ./scripts/04-pack-matrix.sh"
```

## Configuration

Pack definitions and expected NATS subjects live in:
```
config/04-pack-subjects.json
```

To add a new pack or change the tested subjects, edit that file. Example:

```json
{
  "packs": {
    "MyPack": {
      "description": "My custom bot set",
      "bots": ["gtd_bot", "custom_bot"],
      "subjects": [
        "bridge.task.list",
        "custom.endpoint"
      ],
      "timeout_seconds": 60
    }
  }
}
```

## Common Failures

### Subject doesn't respond
- Bot crashed or didn't start — check `docker logs <bot>`
- Wrong NATS subject in config — verify against bot's handler code
- Bot not included in pack — check `catalog/bots.json` and `04-pack-subjects.json`

### Container restart looping
- Check build logs: `docker compose logs <bot> | tail -50`
- Dockerfile issue? (missing entrypoint, compilation failure)
- Runtime issue? (database not ready, dependency missing)

### Compose generation fails
- Missing or stale bot repo clone — check `~/bot-army-pack-<name>/repos/`
- Dockerfile or docker-compose template broken — run `04-pack-generate.sh` manually for details

### Timeout (stuck at "waiting for services")
- Cold Ollama pull? (first run can take 5–10 min)
- Database slow? (Postgres initialization, migrations)
- Resource exhaustion? (check `docker stats`, VM RAM)

## Phase 04 Checklist

- [ ] All 6 packs pass individually (Primary, Learning, Background, Social, Research, Infrastructure)
- [ ] NATS subjects for each pack respond within timeout
- [ ] No container restart loops (restart count ≤ 2)
- [ ] Logs are clean (no ERROR/CRASH lines in last 5 min per bot)
- [ ] Fresh user can select a pack and get a working fleet

## Next Steps (Phase 05+)

- **Pack Compatibility**: Test picking bots from multiple packs at once
- **State Persistence**: Can a user switch packs while keeping data?
- **Custom Packs**: User-defined pack JSON + wizard integration
- **Performance**: Measure boot time + NATS latency per pack
- **Scale**: Test large custom packs (10+ bots)

---

## See Also

- `PITFALLS.md` — Known issues & fixes (P1–P7)
- `03-verify.sh` — Infra health checks
- `04-pack-matrix.sh` — The actual test runner
- `04-pack-subjects.json` — Pack definitions + subjects
