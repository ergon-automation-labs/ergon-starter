#!/usr/bin/env bash
# 05-stage-env.sh — persistent staging fleet + behavior scenarios (P11, 2026-09-09)
#
# The pack matrix (04) proves a fleet can BOOT. This script keeps a fleet
# ALIVE so behaviors can be exercised repeatedly against a fixed endpoint:
#
#   bash /vagrant/scripts/05-stage-env.sh up        # build+boot, stays up
#   bash /vagrant/scripts/05-stage-env.sh status    # containers + registry
#   bash /vagrant/scripts/05-stage-env.sh tap [sec] # record wire timeline
#   bash /vagrant/scripts/05-stage-env.sh scenario lights-up
#   bash /vagrant/scripts/05-stage-env.sh down      # containers (data kept)
#   bash /vagrant/scripts/05-stage-env.sh down -v   # containers + data
#
# Fixed ports — distinct from phase-03 stack (54222/55432) and combos:
#   NATS 55622 · POSTGRES 55632 · OLLAMA 55634 · MCP 55600
set -euo pipefail

STAGE_DIR="${STAGE_DIR:-$HOME/bot-army-stage}"
STAGE_NAME="$(basename "$STAGE_DIR")"
COMBO_CONFIG="${STAGE_COMBO_CONFIG:-$HOME/bot-army-combo-sre/config/04-pack-combinations.json}"
[ -f "$COMBO_CONFIG" ] || COMBO_CONFIG="/vagrant/config/04-pack-combinations.json"

export NATS_HOST_PORT="${NATS_HOST_PORT:-55622}"
export POSTGRES_HOST_PORT="${POSTGRES_HOST_PORT:-55632}"
export OLLAMA_HOST_PORT="${OLLAMA_HOST_PORT:-55634}"
export MCP_HOST_PORT="${MCP_HOST_PORT:-55600}"
STAGE_NATS="nats://localhost:${NATS_HOST_PORT}"

nats_req() {
  nats -s "$STAGE_NATS" request -r --reply-timeout=5s "$1" "${2:-{}}" 2>/dev/null || true
}

expected_bots() {
  # Same logic as the 04 runner: PACKS → packs.json → bots.json (strip _bot)
  local packs="$1" dir="$2"
  python3 - "$packs" "$dir/catalog/bots.json" "$dir/catalog/packs.json" <<'PY'
import json, sys
packs = set(p.strip() for p in sys.argv[1].replace(',', ' ').split() if p.strip())
bots = json.load(open(sys.argv[2]))
pk = json.load(open(sys.argv[3]))
items = pk if isinstance(pk, list) else pk.get('packs', [])
chosen = set()
for p in items:
    if p.get('name') in packs:
        chosen.update(p.get('bots', []))
for b in bots:
    if b['name'] in chosen:
        rel = b.get('release_name', b['name'])
        if rel.endswith('_bot'):
            rel = rel[:-4]
        print(rel)
PY
}

fetch_starter() {
  if [ ! -d "$STAGE_DIR/.git" ]; then
    git clone --depth 1 https://github.com/ergon-automation-labs/ergon-starter.git "$STAGE_DIR"
  else
    git -C "$STAGE_DIR" pull --ff-only 2>/dev/null || echo "⚠ starter ff-pull failed, keeping existing copy"
  fi
}

seed_ollama() {
  # Stage keeps its own ollama volume; seed it from an existing combo volume
  # so we don't re-pull the multi-GB model (combo data outlives teardowns).
  local stage_vol="bot-army-stage_ollama_data"
  if ! docker volume inspect "$stage_vol" >/dev/null 2>&1; then
    docker volume create "$stage_vol" >/dev/null
  fi
  local src_vol
  src_vol=$(docker volume ls -q | grep "ollama_data" | grep -v "bot-army-stage" | head -1 || true)
  local count
  count=$(docker run --rm -v "$stage_vol":/data alpine sh -c 'ls /data/.ollama/models 2>/dev/null | wc -l')
  if [ "${count:-0}" -eq 0 ] && [ -n "$src_vol" ]; then
    echo "  ⏳ seeding ollama models from $src_vol (one-time)..."
    docker run --rm -v "$src_vol":/from -v "$stage_vol":/to alpine sh -c 'cp -a /from/. /to/ 2>/dev/null || true'
  fi
}

wait_for_fleet() {
  local dir="$1" want
  want=$(expected_bots "${PACKS:-core sre}" "$dir" | wc -l)
  echo "  ⏳ waiting for $want bots to register (max 600s)..."
  local i bots
  for i in $(seq 1 60); do
    bots=$(nats_req bot_army.registry.bots.list '{}' | python3 -c "
import json, sys
raw = sys.stdin.read().strip()
try: d = json.loads(raw)
except Exception: print(0); raise SystemExit
names = []
def walk(o):
    if isinstance(o, dict):
        n = o.get('name') or o.get('bot') or o.get('bot_name')
        if isinstance(n, str): names.append(n)
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(d)
print(len(set(names)))" 2>/dev/null || echo 0)
    if [ "${bots:-0}" -ge "$want" ]; then
      echo "  ✓ fleet up: $bots/$want bots registered"
      return 0
    fi
    sleep 10
  done
  echo "  ✗ fleet not fully up after 600s (last: ${bots:-0}/$want)" >&2
  return 1
}

stage_up() {
  echo "═══ staging env: up (PACKS=${PACKS:-core sre}) ═══"
  fetch_starter
  cd "$STAGE_DIR"
  PACKS="${PACKS:-core sre}" bash scripts/quickstart-default.sh > stage-generate.log 2>&1 \
    || { echo "✗ quickstart generation failed:"; tail -25 stage-generate.log; exit 1; }
  seed_ollama
  docker compose up -d --build > stage-build.log 2>&1 \
    || { echo "✗ build/up failed:"; tail -25 stage-build.log; exit 1; }
  wait_for_fleet "$STAGE_DIR"
  echo "  NATS: $STAGE_NATS · dir: $STAGE_DIR"
  echo "  TIP: bash scripts/05-stage-env.sh scenario lights-up"
}

stage_down() {
  cd "$STAGE_DIR" 2>/dev/null || { echo "✗ no stage at $STAGE_DIR"; exit 1; }
  if [ "${1:-}" = "-v" ]; then docker compose down -v; else docker compose down; fi
}

stage_status() {
  cd "$STAGE_DIR" 2>/dev/null || { echo "✗ no stage at $STAGE_DIR"; exit 1; }
  docker compose ps --format '{{.Name}}  {{.Status}}' | sed 's/^/  /'
  echo "  ── registry ──"
  nats_req bot_army.registry.bots.list '{}' | head -c 600; echo
}

stage_tap() {
  local secs="${1:-60}"
  mkdir -p "$STAGE_DIR/timeline"
  local out="$STAGE_DIR/timeline/$(date +%s).jsonl"
  echo "  ⏳ tapping ${secs}s → $out (subjects: system.health, bot.army.pulse.>, bot_army.registry.presence)"
  timeout "$secs" nats -s "$STAGE_NATS" sub "system.health" "bot.army.pulse.>" "bot_army.registry.presence" --json >> "$out" 2>/dev/null || true
  echo "  captured $(grep -c '"subject"' "$out" 2>/dev/null || echo 0) messages"
}

stage_scenario() {
  local name="$1"
  local sc="$STAGE_DIR/vagrant-test/stage/scenarios/${name}.sh"
  [ -f "$sc" ] || { echo "✗ unknown scenario: $name (looked for $sc)"; exit 1; }
  export STAGE_NATS STAGE_DIR
  bash "$sc"
}

case "${1:-}" in
  up)       stage_up ;;
  down)     shift; stage_down "$@" ;;
  status)   stage_status ;;
  tap)      shift; stage_tap "${1:-60}" ;;
  scenario) shift; [ -n "${1:-}" ] && stage_scenario "$1" || { echo "usage: scenario <name>"; exit 1; } ;;
  *) echo "usage: $0 up|down|status|tap [secs]|scenario <name>"; exit 1 ;;
esac