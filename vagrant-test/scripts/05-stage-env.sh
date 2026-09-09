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
SHARED_OLLAMA_VOL="${SHARED_OLLAMA_VOL:-bot-army-combo-ollama}"   # same shared volume as the 04 runner

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

write_ollama_override() {
  # Same pattern as the 04 runner: ONE external shared ollama volume across
  # stage and combos — model blobs pulled once, never re-seeded.
  docker volume create "$SHARED_OLLAMA_VOL" >/dev/null
  cat > override.yml <<EOF
# ollama blobs live in one external shared volume across stage + combos;
# mounts reference the top-level KEY (ollama_data), the external name
# redirects the storage location.
services:
  ollama:
    volumes:
      - ollama_data:/root/.ollama
volumes:
  ollama_data:
    external: true
    name: $SHARED_OLLAMA_VOL
EOF
  export COMPOSE_FILE="docker-compose.yml:override.yml"
}

wait_for_fleet() {
  local dir="$1" want
  want=$(expected_bots "${PACKS:-core sre conformance}" "$dir" | wc -l)
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
  echo "═══ staging env: up (PACKS=${PACKS:-core sre conformance}) ═══"
  fetch_starter
  cd "$STAGE_DIR"
  PACKS="${PACKS:-core sre conformance}" bash scripts/quickstart-default.sh > stage-generate.log 2>&1 \
    || { echo "✗ quickstart generation failed:"; tail -25 stage-generate.log; exit 1; }
  write_ollama_override
  docker compose up -d --build > stage-build.log 2>&1 \
    || { echo "✗ build/up failed:"; tail -25 stage-build.log; exit 1; }
  # model pull into the SHARED volume (instant once cached by any combo)
  local n=0
  until docker compose exec -T ollama ollama list >/dev/null 2>&1 || [ $n -ge 30 ]; do
    sleep 2; n=$((n+1))
  done
  for m in "${MODEL_NAME:-gemma4:31b-cloud}" gemma3:1b; do
    echo "  ollama pull $m (shared volume)..."
    docker compose exec -T ollama ollama pull "$m" >/dev/null 2>&1 || echo "  ⚠ pull $m failed"
  done
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
  # NOTE: VM nats CLI has no --json; human format (Received on + payload).
  timeout "$secs" nats -s "$STAGE_NATS" sub "system.health" "bot.army.pulse.>" "bot_army.registry.presence" >> "$out" 2>/dev/null || true
  echo "  captured $(grep -c 'Received on' "$out" 2>/dev/null || echo 0) messages"
}

stage_scenario() {
  local name="$1"
  local sc="$STAGE_DIR/vagrant-test/stage/scenarios/${name}.sh"
  if [ ! -f "$sc" ]; then
    echo "✗ unknown scenario: $name (looked for $sc)"
    exit 1
  fi
  export STAGE_NATS STAGE_DIR PACKS="${PACKS:-core sre conformance}"
  bash "$sc"
}

case "${1:-}" in
  up)       stage_up ;;
  down)     shift; stage_down "$@" ;;
  status)   stage_status ;;
  tap)      shift; stage_tap "${1:-60}" ;;
  scenario) shift; if [ -n "${1:-}" ]; then stage_scenario "$1"; else echo "usage: scenario <name>"; exit 1; fi ;;
  *) echo "usage: $0 up|down|status|tap [secs]|scenario <name>"; exit 1 ;;
esac