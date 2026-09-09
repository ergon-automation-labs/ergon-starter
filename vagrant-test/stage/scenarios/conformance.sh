#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Stage scenario: conformance — the fleet integration suite, end to end
#
# The conformance bot KNOWS the integration map; the bots don't know it
# exists. This scenario drives it and asserts the receipts, consumer-side:
#   1. `conformance.suite.run` replies with a results map
#   2. the result envelope lands on `conformance.suite.result`
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

suite_id="conf-$(date +%s)-$RANDOM"

# ── 1. suite run (bare payload — conformance accepts both shapes) ──────────
echo "── running conformance suite..."
reply=$(nats -s "$NATS_URL" request conformance.suite.run '{}' --reply-timeout 25s 2>/dev/null || echo "")
if [ -n "$reply" ]; then
  passed=$(echo "$reply" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('passed'))" 2>/dev/null || echo "?")
  failed=$(echo "$reply" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('failed'))" 2>/dev/null || echo "?")
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
res_hit=$(timeout 12 nats -s "$NATS_URL" sub conformance.suite.result -c 1 2>/dev/null | grep -m1 "conformance.suite.result" || true)
if [ -n "$res_hit" ]; then
  ok "result envelope visible on conformance.suite.result (wire)"
else
  # result may have been published just before we subscribed; force another
  # short run so the subscription definitely sees a live publish
  nats -s "$NATS_URL" request conformance.suite.run '{}' --reply-timeout 25s >/dev/null 2>&1 || true
  res_hit=$(timeout 12 nats -s "$NATS_URL" sub conformance.suite.result -c 1 2>/dev/null | grep -m1 "conformance.suite.result" || true)
  if [ -n "$res_hit" ]; then
    ok "result envelope visible on conformance.suite.result (2nd run)"
  else
    bad "no result envelope on conformance.suite.result"
  fi
fi

# ── 3. SRE VALIDATOR: audit receipt persisted in ergon_sre.audit_events ────
echo "── asserting sre audit receipt (the validator path)..."
baseline=$(docker exec bot-army-stage-postgres-1 psql -U postgres -d ergon_sre -tA \
  -c "select count(*) from audit_events where event_type='sre.conformance.suite.completed'" 2>/dev/null || echo 0)
receipt_ok=""
for i in $(seq 1 12); do
  count=$(docker exec bot-army-stage-postgres-1 psql -U postgres -d ergon_sre -tA \
    -c "select count(*) from audit_events where event_type='sre.conformance.suite.completed'" 2>/dev/null || echo 0)
  if [ "${count:-0}" -gt "${baseline:-0}" ]; then
    receipt_ok=1; break
  fi
  sleep 5
done
if [ -n "$receipt_ok" ]; then
  ok "sre validator: audit receipt persisted (event_type='sre.conformance.suite.completed')"
else
  bad "sre validator: no audit receipt within 60s"
fi

# ── 4. include_failures → sre incident receipt ─────────────────────────────
echo "── seeded failure run (include_failures=true)..."
f_reply=$(nats -s "$NATS_URL" request conformance.suite.run '{"include_failures": true}' --reply-timeout 25s 2>/dev/null || echo "")
f_failed=$(echo "$f_reply" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('failed'))" 2>/dev/null || echo "?")
if [ "$f_failed" = "1" ] || [ "$f_failed" = "2" ]; then
  ok "seeded failure run: failed=$f_failed (inject_fail probe worked)"
else
  bad "seeded failure run: inject_fail probe missing (failed=$f_failed)"
fi

incident_ok=""
for i in $(seq 1 12); do
  line=$(docker logs "$SRE_CONTAINER" --since 120s 2>&1 | grep -E "Incident processed|Incident processing failed: \{:task_creation_failed" | tail -1 || true)
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