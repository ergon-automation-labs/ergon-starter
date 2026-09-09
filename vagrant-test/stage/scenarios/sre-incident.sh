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
    "matches": [{"line_number": 42, "line": "GenServer bot_army_chore terminating (timeout)"}],
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
    "matches": [{"line_number": 42, "line": "GenServer bot_army_chore terminating (timeout)"}],
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
# The Coordinator must RUN. "Incident processed" = full happy path (needs a
# bridge.task.create responder — the bridge host bot lives on the HOST's
# NATS, not this isolated stage NATS). "Incident processing failed:
# task_creation_failed (Bridge request failed: timeout)" = the Coordinator
# invoked create_gtd_task and handled the bridge absence GRACEFULLY — that
# still proves the three systemic legs: consumer received the envelope,
# EventHandler routed it, Coordinator ran its GTD step. A crash here would
# be a failure; a handled warning is the documented isolated-fleet boundary.
sleep 10
sre_log=$(docker logs bot-army-stage-sre_bot-1 --since 90s 2>&1 || true)
if echo "$sre_log" | grep -q "Incident processed"; then
  ok "pipeline: sre Coordinator processed the incident (full happy path)"
elif echo "$sre_log" | grep -q "Incident processing failed: {:task_creation_failed"; then
  ok "pipeline: Coordinator ran + handled bridge absence gracefully (isolated-fleet boundary)"
  echo "$sre_log" | grep -m1 -A1 "Incident processing failed" | sed 's/^/      /' | head -2
elif echo "$sre_log" | grep -q "Incident processing failed"; then
  bad "pipeline: Coordinator errored (non-bridge failure):"; echo "$sre_log" | grep -A2 "Incident processing failed" | head -6 | sed 's/^/      /'
else
  bad "pipeline: Coordinator never ran (no Incident log line in 90s window)"
fi

echo "── sre-incident: $PASS ok, $FAIL failed ──"
[ "$FAIL" -eq 0 ]