#!/usr/bin/env bash
# lights-up.sh — Scenario L3-1: every registered bot lights up on the wire
# (P11, 2026-09-09)
#
# Asserts, from the OUTSIDE (consumer-side only — no code hooks):
#   1. every expected bot is registered in the live registry
#   2. within one observation window, every registered bot publishes a
#      `system.health` envelope (the tap is the consumer)
#   3. the bot's own DB received its heartbeat rows (Heartbeat persister)
#
# Env: STAGE_NATS, STAGE_DIR (set by 05-stage-env.sh)
set -euo pipefail

: "${STAGE_NATS:?run via 05-stage-env.sh}"
: "${STAGE_DIR:?run via 05-stage-env.sh}"
cd "$STAGE_DIR"

WINDOW="${SCENARIO_WINDOW:-45}"
PASS=0; FAIL=0
note() { echo "  $*"; }
ok()   { echo "  ✓ $*"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $*"; FAIL=$((FAIL+1)); }

# ── expected + registered bots ───────────────────────────────────────────────
expected=$(python3 - . <<'PY'
import json, sys, os
bots = json.load(open('catalog/bots.json')); pk = json.load(open('catalog/packs.json'))
packs = set((os.environ.get('STAGE_PACKS') or 'core sre').split())
items = pk if isinstance(pk, list) else pk.get('packs', [])
chosen = set()
for p in items:
    if p.get('name') in packs: chosen.update(p.get('bots', []))
for b in bots:
    if b['name'] in chosen:
        rel = b.get('release_name', b['name'])
        print(rel[:-4] if rel.endswith('_bot') else rel)
PY
STAGE_PACKS="${PACKS:-core sre}")
[ -n "$expected" ] || { echo "✗ no expected bots"; exit 1; }

registered=$(nats -s "$STAGE_NATS" request -r --reply-timeout=5s bot_army.registry.bots.list '{}' 2>/dev/null | python3 -c "
import json, sys
try: d = json.loads(sys.stdin.read().strip())
except Exception: print(''); raise SystemExit
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
[ -n "$registered" ] || { echo "✗ registry unreachable"; exit 1; }

missing=""
for bot in $expected; do
  echo "$registered" | grep -qw "$bot" || missing="$missing $bot"
done
[ -z "$missing" ] && ok "registry: all $(echo "$expected" | wc -l) expected bots registered" \
                     || bad "registry: missing$missing (have: $registered)"

# ── wire tap: system.health for one window ──────────────────────────────────
echo "  ⏳ tapping system.health for ${WINDOW}s..."
timeline="$STAGE_DIR/timeline-lights-up.jsonl"
timeout "$WINDOW" nats -s "$STAGE_NATS" sub "system.health" --json > "$timeline" 2>/dev/null || true
sources=$(python3 - "$timeline" <<'PY'
import json, sys
srcs = set()
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    try: m = json.loads(line)
    except Exception: continue
    body = m.get('data') or m.get('payload') or ''
    try: d = json.loads(body) if isinstance(body, str) else (body or {})
    except Exception: d = {}
    s = (d or {}).get('source')
    if isinstance(s, str): srcs.add(s)
print(' '.join(sorted(srcs)))
PY
)
for bot in $expected; do
  echo "$sources" | grep -qw "bot_army_${bot}" \
    && ok "wire: bot_army_${bot} published system.health" \
    || bad "wire: no system.health from bot_army_${bot} (saw: $(echo "$sources" | head -3))"
done

# ── DB receipts: heartbeats table per bot that has a DB ────────────────────
PG="docker exec bot-army-stage-postgres-1 psql -U postgres -tA -c"
for bot in $expected; do
  rows=$($PG "select count(*) from heartbeats where source = 'bot_army_${bot}';" 2>/dev/null \
      || $PG "select count(*) from ergon_${bot}.heartbeats;" 2>/dev/null || echo "nodb")
  case "$rows" in
    nodb) note "· $bot: no dedicated DB (skipped)" ;;
    0)    bad "db: zero heartbeat rows for bot_army_${bot}" ;;
    *)    ok "db: bot_army_${bot} persisted $rows heartbeat rows" ;;
  esac
done

echo "── lights-up: $PASS ok, $FAIL failed ──"
[ "$FAIL" -eq 0 ]