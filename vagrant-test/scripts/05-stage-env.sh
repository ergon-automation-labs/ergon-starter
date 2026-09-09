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

write_overrides() {
  # Same pattern as the 04 runner: ONE external shared ollama volume across
  # stage and combos — model blobs pulled once, never re-seeded.
  docker volume create "$SHARED_OLLAMA_VOL" >/dev/null
  # Compose override is assembled in ONE file with a single services: key.
  # auditor_repo_scanner needs the fleet's own bot repos mounted read-only
  # (it scans whatever PACKS cloned into ./repos) plus the catalog for the
  # catalog-entry check — added only when the auditor_scan pack is selected
  # so the override stays valid for core-only stages.
  local auditor_block=""
  if grep -q "auditor_repo_scanner_bot" docker-compose.yml 2>/dev/null; then
    auditor_block='  auditor_repo_scanner_bot:
    volumes:
      - ./repos:/repos:ro
      - ./catalog:/catalog:ro
    environment:
      AUDITOR_REPO_ROOT: /repos
      AUDITOR_CATALOG_PATH: /catalog/bots.json'
  fi
  cat > override.yml <<EOF
# ollama blobs live in one external shared volume across stage + combos;
# mounts reference the top-level KEY (ollama_data), the external name
# redirects the storage location.
services:
  ollama:
    volumes:
      - ollama_data:/root/.ollama
${auditor_block}
volumes:
  ollama_data:
    external: true
    name: $SHARED_OLLAMA_VOL
EOF
  [ -n "$auditor_block" ] && echo "  ✓ auditor override: /repos + /catalog mounts (read-only)"
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
  write_overrides
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

# Catalog-driven scan targets: every catalog bot whose repo exists in the
# stage's repos/ clone dir. Libraries (bot_army_library_*) are excluded —
# they are path-dep packages, not bots.
scan_targets() {
  python3 - "$STAGE_DIR/catalog/bots.json" <<'PY'
import json, os, sys
bots = json.load(open(sys.argv[1]))
items = bots if isinstance(bots, list) else bots.get('bots', [])
repos_dir = os.path.expanduser(os.environ.get('AUDITOR_REPOS_DIR', os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), '..', 'repos')))
for b in items:
    if not isinstance(b, dict):
        continue
    repo = b.get('repo', '')
    if not repo or repo.startswith('bot_army_library_'):
        continue
    if os.path.isdir(os.path.join(repos_dir, repo)):
        print(repo)
PY
}

stage_scan() {
  local repo="${1:-}"
  if [ -z "$repo" ]; then
    echo "usage: $0 scan <repo-name>  (name under repos/, e.g. bot_army_sre)" >&2
    exit 1
  fi
  echo "═══ repo scan: $repo ═══"
  nats -s "$STAGE_NATS" request -r --reply-timeout=15s auditor.repo.scan "{\"repo\":\"$repo\"}" 2>&1 || \
    { echo "  ✗ no reply — is auditor_repo_scanner in this fleet? (PACKS must include auditor_scan)"; return 1; }
}

stage_scan_all() {
  echo "═══ repo scan: catalog bots present in repos/ ═══"
  local repos
  repos=$(AUDITOR_REPOS_DIR="$STAGE_DIR/repos" scan_targets) || repos=""
  if [ -z "$repos" ]; then
    echo "  (no scan targets — repos/ empty or catalog missing)"
    return 0
  fi
  local fails=0 total=0 r out verdict fails_n
  for r in $repos; do
    total=$((total+1))
    out=$(nats -s "$STAGE_NATS" request -r --reply-timeout=15s auditor.repo.scan "{\"repo\":\"$r\"}" 2>&1 | tail -1 || true)
    if [ -z "$out" ]; then
      echo "  $r: NO REPLY (scanner down or slow)"
      fails=$((fails+1))
      continue
    fi
    verdict=$(echo "$out" | python3 -c "import json,sys
body=sys.stdin.read()
try:
  d=json.loads(body[body.find('{'):])
  print(d.get('verdict','?'))
except Exception:
  print('unparseable')")
    fails_n=$(echo "$out" | python3 -c "import json,sys
body=sys.stdin.read()
try:
  d=json.loads(body[body.find('{'):])
  print(d.get('summary',{}).get('fail',0))
except Exception:
  print('?')")
    echo "  $r: $verdict ($fails_n required-fail)"
    [ "$verdict" = "failing" ] && fails=$((fails+1))
  done
  echo "  ── $((total - fails))/$total not-failing ═══"
  [ "$fails" -eq 0 ]
}

case "${1:-}" in
  up)       stage_up ;;
  down)     shift; stage_down "$@" ;;
  status)   stage_status ;;
  tap)      shift; stage_tap "${1:-60}" ;;
  scan)     shift; stage_scan "$1" ;;
  scan-all) stage_scan_all ;;
  scenario) shift; if [ -n "${1:-}" ]; then stage_scenario "$1"; else echo "usage: scenario <name>"; exit 1; fi ;;
  *) echo "usage: $0 up|down|status|tap [secs]|scan <repo>|scan-all|scenario <name>"; exit 1 ;;
esac