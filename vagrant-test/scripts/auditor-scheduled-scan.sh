#!/usr/bin/env bash
# auditor-scheduled-scan.sh — provisioner-installed scheduled trigger
#
# Installed as a cron entry by scripts/bootstrap.sh (so a box reset
# re-provisions the schedule). Runs from the /vagrant synced folder, which
# always carries the latest starter.
#
# Design (fleet-not-always-up, 2026-09-09):
#   - First pings auditor.repo.ping. If the fleet (scanner) isn't up, this
#     is an error path — logged and non-noisy. No scheduler daemon, no
#     state: the box may be down for days; nothing retries or queues.
#   - When up, scans every catalog bot whose repo exists in the stage's
#     repos/ clone dir. Libraries (bot_army_library_*) are excluded.
#   - Every completed scan publishes an sre audit receipt via the bot, so
#     sre.audit.query is the durable history (this log is the second copy).
#
# Installed via: scripts/bootstrap.sh (crontab, idempotent)
# Log: ~/bot-army-stage/scan-schedule.log

set -uo pipefail

STAGE_DIR="${STAGE_DIR:-$HOME/bot-army-stage}"
NATS_ADDR="${STAGE_NATS:-nats://localhost:55622}"
REPLY_TIMEOUT="15s"
ts() { date '+%Y-%m-%dT%H:%M:%S'; }

log() { echo "[$(ts)] $*"; }

# ── Gate: is the fleet (scanner) up? ─────────────────────────────────────
# No `| tail -1` — the VM nats CLI's reply JSON has no trailing newline, so
# tail -1 yields the empty final line (caught live 2026-09-09).
ping_out=$(nats -s "$NATS_ADDR" request -r --reply-timeout=3s auditor.repo.ping '{}' 2>/dev/null || true)

if [ -z "$ping_out" ]; then
  log "ERROR: no auditor.repo.ping responder — fleet down or auditor_scan not in PACKS; skipping scan run"
  exit 1
fi

log "fleet up ($ping_out)"

# ── Targets: catalog bots present in repos/ ──────────────────────────────
CATALOG="$STAGE_DIR/catalog/bots.json"
[ -f "$CATALOG" ] || { log "no catalog at $CATALOG — nothing to scan"; exit 1; }

targets=$(python3 - "$CATALOG" <<'PY'
import json, os, sys
bots = json.load(open(sys.argv[1]))
items = bots if isinstance(bots, list) else bots.get('bots', [])
repos_dir = os.path.expanduser(os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), '..', 'repos'))
for b in items:
    if not isinstance(b, dict):
        continue
    repo = b.get('repo', '')
    if not repo or repo.startswith('bot_army_library_'):
        continue
    if os.path.isdir(os.path.join(repos_dir, repo)):
        print(repo)
PY
)

if [ -z "$targets" ]; then
  log "no scan targets (repos/ empty or catalog has no bot repos)"
  exit 0
fi

# ── Scan each ────────────────────────────────────────────────────────────
failing=0
scanned=0
for repo in $targets; do
  scanned=$((scanned+1))
  # No `| tail -1` — reply JSON has no trailing newline (see ping above).
  out=$(nats -s "$NATS_ADDR" request -r --reply-timeout="$REPLY_TIMEOUT" auditor.repo.scan "{\"repo\":\"$repo\"}" 2>/dev/null || true)
  if [ -z "$out" ]; then
    log "$repo: NO REPLY (scanner died mid-run?)"
    failing=$((failing+1))
    continue
  fi
  parsed=$(echo "$out" | python3 -c "
import json, sys
body = sys.stdin.read()
try:
    d = json.loads(body[body.find('{'):])
    v = d.get('verdict', '?')
    s = d.get('summary', {})
    print(f\"{v} fail={s.get('fail',0)} warn={s.get('warn',0)} pass={s.get('pass',0)}\")
except Exception:
    print('unparseable')
")
  log "$repo: $parsed"
  case "$parsed" in failing*) failing=$((failing+1));; esac
done

log "scan run complete: $scanned+ repos, $failing failing"
exit 0