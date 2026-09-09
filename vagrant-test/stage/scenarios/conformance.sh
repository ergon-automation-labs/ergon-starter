#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Stage scenario: conformance — the fleet integration suite, end to end
#
# The conformance bot KNOWS the integration map; the bots don't know it
# exists. This scenario drives it and asserts the receipts, consumer-side:
#   1. `conformance.suite.run` replies with a results map
#   2. the result envelope lands on `conformance.suite.result` (wire tap
#      started BEFORE the run — a subscriber guaranteed to see the publish)
#   3. sre persists the audit receipt (event_type='sre.conformance.suite.completed')
#      in the ergon_sre DB — SRE AS VALIDATOR: the integration path lit up
#   4. with include_failures=true: sre receives the failure incident
#      (events.sre.log.incident) and runs the Coordinator (graceful
#      bridge-absence handling is the documented isolated-fleet boundary)
#
# Env: STAGE_NATS, STAGE_DIR (set by 05-stage-env.sh)
set -euo pipefail

: "${STAGE_NATS:?run via 05-stage-env.sh}"
: "${STAGE_DIR:?run via 05-stage-env.sh}"
cd "$STAGE_DIR"

PASS=0; FAIL=0
ok()  { echo "  ✓ $*"; PASS=$((PASS+1)); }
bad() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }

NATS_URL="$STAGE_NATS"
SRE_CONTAINER="bot-army-stage-sre_bot-1"

# Baseline captured BEFORE the run — the audit receipt is asserted as DELTA
audit_baseline=$(docker exec bot-army-stage-postgres-1 psql -U postgres -d ergon_sre -tA \
  -c "select count(*) from audit_events where event_type='sre.conformance.suite.completed'" 2>/dev/null || echo 0)

# ── 1. suite run (bare payload — conformance accepts both shapes) ──────────
echo "── running conformance suite..."

# Wire tap FIRST, then the run.
(timeout 35 nats -s "$NATS_URL" sub conformance.suite.result --count=1 > /tmp/conf-result-tap.txt 2>/dev/null) &
tap_pid=$!
sleep 1
reply=$(nats -s "$NATS_URL" request conformance.suite.run '{}' --reply-timeout 45s 2>/dev/null || echo "")

if [ -n "$reply" ]; then
  passed=$(echo "$reply" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('passed'))" 2>/dev/null || echo "?")
  failed=$(echo "$reply" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('failed'))" 2>/dev/null || echo "?")
  absent=$(echo "$reply" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('absent'))" 2>/dev/null || echo "?")
  if [ "$passed" != "?" ] && [ "${passed:-0}" -ge 1 ] && [ "${failed:-1}" -eq 0 ]; then
    ok "suite run: passed=$passed failed=$failed absent=$absent (reply receipt)"
  else
    bad "suite run reply has failures or unparsable: passed=$passed failed=$failed absent=$absent"
    echo "$reply" | head -3 | sed 's/^/      /'
  fi
else
  bad "suite run: no reply from conformance.suite.run within 25s"
fi

# ── 2. result envelope lands on conformance.suite.result ───────────────────
wait $tap_pid 2>/dev/null || true
if grep -q "conformance.suite.result" /tmp/conf-result-tap.txt 2>/dev/null; then
  ok "result envelope visible on conformance.suite.result (wire)"
else
  bad "no result envelope on conformance.suite.result"
fi

# ── 3. SRE VALIDATOR: audit receipt persisted in ergon_sre.audit_events ────
echo "── asserting sre audit receipt (the validator path)..."
receipt_ok=""
for i in $(seq 1 12); do
  count=$(docker exec bot-army-stage-postgres-1 psql -U postgres -d ergon_sre -tA \
    -c "select count(*) from audit_events where event_type='sre.conformance.suite.completed'" 2>/dev/null || echo 0)
  if [ "${count:-0}" -gt "${audit_baseline:-0}" ]; then
    receipt_ok=1; break
  fi
  sleep 5
done
if [ -n "$receipt_ok" ]; then
  ok "sre validator: audit receipt persisted (event_type='sre.conformance.suite.completed')"
else
  bad "sre validator: no audit receipt within 60s (baseline=$audit_baseline)"
fi

# ── 4. include_failures → sre incident receipt ─────────────────────────────
echo "── seeded failure run (include_failures=true)..."

# Same receipt pattern: tap the sre incident topic BEFORE the run.
(timeout 35 nats -s "$NATS_URL" sub "events.sre.log.incident" --count=1 > /tmp/conf-incident-tap.txt 2>/dev/null) &
incident_tap_pid=$!
sleep 1
f_reply=$(nats -s "$NATS_URL" request conformance.suite.run '{"include_failures": true}' --reply-timeout 45s > /tmp/conf-fail-reply.json 2>/tmp/conf-fail-err.txt || echo "")
f_failed=$(python3 -c "import json,sys; d=json.loads(open('/tmp/conf-fail-reply.json').read()); print(d.get('failed'))" 2>/dev/null || echo "?")
if [ "$f_failed" = "1" ] || [ "$f_failed" = "2" ]; then
  ok "seeded failure run: failed=$f_failed (inject_fail probe worked)"
else
  bad "seeded failure run: inject_fail probe missing (failed=$f_failed)"
fi

wait $incident_tap_pid 2>/dev/null || true
if grep -q "events.sre.log.incident" /tmp/conf-incident-tap.txt 2>/dev/null; then
  ok "incident envelope on events.sre.log.incident (LogWatcher shape)"
else
  bad "no incident envelope on events.sre.log.incident"
fi

incident_ok=""
for i in $(seq 1 12); do
  line=$(docker logs "$SRE_CONTAINER" --since 150s 2>&1 | grep -E "Incident processed|Incident processing failed: \{:task_creation_failed" | tail -1 || true)
  if [ -n "$line" ]; then incident_ok=1; break; fi
  sleep 5
done
if [ -n "$incident_ok" ]; then
  if echo "$line" | grep -q "Incident processed"; then
    ok "sre incident pipeline: full happy path (GTD task + investigation)"
  else
    ok "sre incident pipeline: Coordinator ran + handled bridge absence gracefully (isolated-fleet boundary)"
    echo "$line" | sed 's/^/      /'
  fi
else
  bad "sre incident: no Coordinator receipt within 60s"
fi

echo "── conformance: $PASS ok, $FAIL failed ──"
[ "$FAIL" -eq 0 ]