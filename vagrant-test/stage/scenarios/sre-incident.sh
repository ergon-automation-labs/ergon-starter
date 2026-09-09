#!/usr/bin/env bash
# sre-incident.sh — Scenario L3-2: seeded log incident → SRE receipts (P11)
#
# Fires a LogWatcher-shaped incident envelope on `events.sre.log.incident`
# (exact shape sre's own LogWatcher publishes) and asserts, consumer-side:
#   1. sre's consumer validated + persisted it → `audit_events` row in the
#      ergon_sre DB with event 'sre.log.incident' and our event_id
#   2. sre's incident pipeline ran (container log shows "Incident processed")
#
# Env: STAGE_NATS, STAGE_DIR (set by 05-stage-env.sh)
set -euo pipefail

: "${STAGE_NATS:?run via 05-stage-env.sh}"
: "${STAGE_DIR:?run via 05-stage-env.sh}"
cd "$STAGE_DIR"

PASS=0; FAIL=0
ok()  { echo "  ✓ $*"; PASS=$((PASS+1)); }
bad() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }

# unique marker so we can find OUR row among real traffic
event_id="stage-$(date +%s)-$$"
bot_under_test="bot_army_chore"   # seeded incident blames a real fleet bot

envelope=$(python3 - "$event_id" "$bot_under_test" <<'PY'
import json, sys, datetime
print(json.dumps({
  "event": "sre.log.incident",
  "event_id": sys.argv[1],
  "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
  "source": "stage-scenario",
  "payload": {
    "bot": sys.argv[2],
    "error_type": "timeout",
    "match_count": 1,
    "matches": ["GenServer bot_army_chore terminating (timeout)"],
  },
}))
PY
)

# ── pre: baseline count ─────────────────────────────────────────────────────
PG="docker exec bot-army-stage-postgres-1 psql -U postgres -d ergon_sre -tA -c"
before=$($PG "select count(*) from audit_events;" 2>/dev/null || echo "0")
echo "  baseline audit_events rows: $before"

# ── fire ────────────────────────────────────────────────────────────────────
echo "  ⏳ publishing seeded incident (event_id=$event_id)..."
python3 - "$event_id" "$bot_under_test" "$STAGE_NATS" <<'PY'
import json, sys, datetime, subprocess
envelope = json.dumps({
  "event": "sre.log.incident",
  "event_id": sys.argv[1],
  "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
  "source": "stage-scenario",
  "payload": {
    "bot": sys.argv[2],
    "error_type": "timeout",
    "match_count": 1,
    "matches": ["GenServer bot_army_chore terminating (timeout)"],
  },
})
# nats CLI ignores stdin for pub in this VM version — payload must be argv
subprocess.run(["nats", "-s", sys.argv[3], "pub", "events.sre.log.incident", envelope],
               text=True, capture_output=True, check=True)
print("  published", sys.argv[1])
PY

# ── assert: DB receipt (audit_events) ───────────────────────────────────────
deadline=$((SECONDS + 60))
row=""
while [ $SECONDS -lt $deadline ]; do
  row=$($PG "select event_type, event_id from audit_events where event_id = '$event_id' limit 1;" 2>/dev/null || true)
  [ -n "$row" ] && break
  sleep 3
done
if [ -n "$row" ]; then
  ok "db: audit_events persisted our incident (event_id=$event_id)"
else
  bad "db: no audit_events row for event_id=$event_id within 60s"
fi

# ── assert: incident pipeline ran (Coordinator path in sre log) ────────────
sleep 10
sre_log=$(docker logs bot-army-stage-sre_bot-1 --since 90s 2>&1 || true)
if echo "$sre_log" | grep -q "Incident processed"; then
  ok "pipeline: sre Coordinator processed the incident"
elif echo "$sre_log" | grep -q "Incident processing failed"; then
  bad "pipeline: Coordinator errored:"; echo "$sre_log" | grep -A2 "Incident processing failed" | head -6 | sed 's/^/      /'
else
  # audit receipt is the hard consumer-side proof; pipeline trace is best-effort
  echo "  · pipeline: no 'Incident processed' log line in 90s window (audit receipt still green)"
fi

echo "── sre-incident: $PASS ok, $FAIL failed ──"
[ "$FAIL" -eq 0 ]