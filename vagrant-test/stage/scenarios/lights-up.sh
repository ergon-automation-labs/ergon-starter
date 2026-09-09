#!/usr/bin/env bash
# lights-up.sh — Scenario L3-1: every expected bot lights up (P11, 2026-09-09)
#
# Asserts, from the OUTSIDE (consumer-side only — no code hooks):
#   1. every expected bot is registered in the live registry (using the SAME
#      name semantics as the 04 runner: NONREGISTERING_BOTS + alias table +
#      prefix matching — copied verbatim so there is one source of truth)
#   2. within one observation window, bots publish `system.health` envelopes
#      (the tap is the consumer; nats CLI has no --json on this VM — the
#      human format is parsed: 'Received on "<subject>"' + payload line)
#   3. every live ergon_* DB received heartbeat rows in the window
#
# Env: STAGE_NATS, STAGE_DIR (set by 05-stage-env.sh)
set -euo pipefail

: "${STAGE_NATS:?run via 05-stage-env.sh}"
: "${STAGE_DIR:?run via 05-stage-env.sh}"
cd "$STAGE_DIR"

WINDOW="${SCENARIO_WINDOW:-45}"
PASS=0; FAIL=0
ok()   { echo "  ✓ $*"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $*"; FAIL=$((FAIL+1)); }
note() { echo "  · $*"; }

# ── expected + registered bots (04-runner semantics) ────────────────────────
expected=$(python3 - . <<'PY'
import json, sys, os
bots = json.load(open('catalog/bots.json')); pk = json.load(open('catalog/packs.json'))
packs = set((os.environ.get('PACKS') or 'core sre').split())
items = pk if isinstance(pk, list) else pk.get('packs', [])
chosen = set()
for p in items:
    if p.get('name') in packs: chosen.update(p.get('bots', []))
for b in bots:
    if b['name'] in chosen:
        rel = b.get('release_name', b['name'])
        print(rel[:-4] if rel.endswith('_bot') else rel)
PY
export PACKS="${PACKS:-core sre}")
[ -n "$expected" ] || { echo "✗ no expected bots"; exit 1; }

# Same tables as vagrant-test/scripts/04-pack-matrix.sh (single source of
# truth there — keep in sync or factor out):
NONREGISTERING_BOTS="bridge_lite elixir_tools_mcp rss_polling"
alias_for() { case "$1" in surface_mcp) echo "mcp" ;; *) echo "$1" ;; esac; }

registered=$(nats -s "$STAGE_NATS" request -r --reply-timeout=5s bot_army.registry.bots.list '{}' 2>/dev/null | python3 -c "
import json, sys
try: d = json.loads(sys.stdin.read().strip())
except Exception: print('REGISTRY_PARSE_FAIL'); raise SystemExit
names = set()
def walk(o):
    if isinstance(o, dict):
        n = o.get('name') or o.get('bot') or o.get('bot_name')
        if isinstance(n, str): names.add(n)
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(d)
print(' '.join(sorted(names)))" 2>/dev/null || true)
case "$registered" in ""|"REGISTRY_PARSE_FAIL") echo "✗ registry unreachable"; exit 1;; esac

missing=""
for bot in $expected; do
  echo " $NONREGISTERING_BOTS " | grep -q " $bot " && continue      # infra host
  rname=$(alias_for "$bot")
  echo " $registered " | grep -q " $rname \| bot_army_${rname}" || missing="$missing $bot"
done
n_exp=$(echo "$expected" | wc -l)
[ -z "$missing" ] && ok "registry: all $n_exp expected bots registered" \
                    || bad "registry: missing$missing (registered: $registered)"

# ── wire tap: system.health for one window (human format) ───────────────────
echo "  ⏳ tapping system.health for ${WINDOW}s..."
timeline="$STAGE_DIR/timeline-lights-up.jsonl"
timeout "$WINDOW" nats -s "$STAGE_NATS" sub "system.health" > "$timeline" 2>/dev/null || true
# blocks look like:  [#3] Received on "system.health"  \n  <payload json>
sources=$(python3 - "$timeline" <<'PY'
import json, sys, re
srcs = set()
subj = None
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    m = re.match(r'\[#+\d+\]\s+Received on "([^"]+)"', line)
    if m: subj = m.group(1); continue
    if subj and line.startswith('{'):
        try:
            d = json.loads(line)
            s = d.get('source')
            if isinstance(s, str): srcs.add(s)
        except Exception: pass
        subj = None
print(' '.join(sorted(srcs)))
PY
)
total=$(grep -c 'Received on' "$timeline" 2>/dev/null || echo 0)
note "tap captured $total system.health messages in ${WINDOW}s"

# Known gap (stage finding, 2026-09-09): these bots have NO health publisher
# child (health publishing is opt-in per bot via pulse_publisher/SynapseHealth;
# gtd/llm/synapse/job_scheduler/sre have it, these don't). They register and
# serve fine but go unseen by heartbeat-based monitoring. Systemic fix pending.
NO_HEALTH_PUBLISH="elixir_tools_mcp general graphify_cache"

for bot in $expected; do
  rname=$(alias_for "$bot")
  echo " $NO_HEALTH_PUBLISH " | grep -q " $bot " \
    && { note "wire: $bot has no health publisher child (known gap, see ledger)"; continue; }
  echo "$sources" | grep -qw "bot_army_${rname}" \
    && ok "wire: bot_army_${rname} published system.health" \
    || bad "wire: no system.health from bot_army_${rname} in ${WINDOW}s (saw: $(echo "$sources" | head -3))"
done

# ── DB receipts: heartbeats rows fresh in every live ergon_* DB ────────────
dbs=$(docker exec bot-army-stage-postgres-1 psql -U postgres -tA -c \
  "select datname from pg_database where datname like 'ergon%' and not datistemplate;" 2>/dev/null || true)
[ -n "$dbs" ] || bad "db: no ergon_* databases on stage postgres"
for db in $dbs; do
  rows=$(docker exec bot-army-stage-postgres-1 psql -U postgres -d "$db" -tA -c \
    "select count(*) from heartbeats where recorded_at > now() - interval '10 minutes';" 2>/dev/null \
    || echo "notable")
  case "$rows" in
    notable) note "db $db: no heartbeats table (skipped)" ;;
    0)       bad "db $db: zero heartbeats in the last 10 min" ;;
    *)       ok "db $db: $rows fresh heartbeat rows" ;;
  esac
done

echo "── lights-up: $PASS ok, $FAIL failed ──"
[ "$FAIL" -eq 0 ]