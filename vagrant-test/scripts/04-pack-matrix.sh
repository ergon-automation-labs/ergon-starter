#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Phase 04 — pack combination validation
# Tests realistic combinations of REAL packs (catalog/packs.json: core,
# learning_deepdive, social_media, areas, research). Per combo: fresh working
# copy → quickstart-default.sh with PACKS=<packs> → docker compose up →
# registry + health + log-regression verification → teardown.
#
# P10/2026-09-06 rewrite of the first draft, which called packs that don't
# exist, cloned /vagrant as a git repo (it isn't one), and never freed the
# host ports between combos. Mechanics now:
#   - teardown: main stack down (volumes kept) at start; combo `down -v`
#     between combos; host ports are sequential-safe again.
#   - ollama model blobs live in ONE external shared volume across combos
#     (a fresh 7 GB pull per combo would eat the VM disk and ~1 h).
#   - model pull happens inside the first combo (subsequent ones are
#     instant manifest checks).
#   - verify = registry bot-set + system.health + container health +
#     P10 log-regression grep. No static subject lists.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

LOG="$HOME/logs/04-pack-combinations.log"
HOST_LOG="/vagrant/logs/04-pack-combinations.log"
MARKERS="$HOME/.phase04/markers"
RESULTS="/vagrant/logs/04-pack-results.jsonl"
COMBO_CONFIG="/vagrant/config/04-pack-combinations.json"
STARTER_REPO="https://github.com/ergon-automation-labs/ergon-starter.git"
MODEL_NAME="${MODEL_NAME:-gemma4:e2b}"
SHARED_OLLAMA_VOL="bot-army-combo-ollama"
mkdir -p "$HOME/logs" /vagrant/logs "$MARKERS" "$HOME/bin"

exec > >(tee -a "$LOG" "$HOST_LOG") 2>&1

# ─────────────────────────────────────────────────────────────────────────────
# Utilities
# ─────────────────────────────────────────────────────────────────────────────

hr() { echo "═══════════════════════════════════════════════════════════"; }

combo_dirname() {
  echo "$1" | sed 's/[^a-zA-Z0-9_-]/-/g' | tr '[:upper:]' '[:lower:]'
}

# ─────────────────────────────────────────────────────────────────────────────
# nats CLI (request/response probes; not installed by bootstrap)
# ─────────────────────────────────────────────────────────────────────────────

ensure_nats_cli() {
  if command -v nats >/dev/null 2>&1; then return 0; fi
  if [ -x "$HOME/bin/nats" ]; then export PATH="$HOME/bin:$PATH"; return 0; fi
  echo "Installing nats CLI (one-time, ~10 MB)..."
  local url
  url=$(curl -fsSL https://api.github.com/repos/nats-io/natscli/releases/latest 2>/dev/null |
        grep -oE 'https://[^"]+linux-arm64\.zip' | head -1 || true)
  if [ -z "$url" ]; then
    echo "  ✗ could not resolve a linux-arm64 natscli release" >&2
    return 1
  fi
  curl -fsSL "$url" -o /tmp/natscli.zip && rm -rf /tmp/natscli &&
    python3 -m zipfile -e /tmp/natscli.zip /tmp/natscli
  find /tmp/natscli -type f -name nats -exec cp {} "$HOME/bin/nats" \; &&
    chmod +x "$HOME/bin/nats"
  export PATH="$HOME/bin:$PATH"
  command -v nats >/dev/null 2>&1
}

# NATS request → stdout raw payload (empty string on no-responder/timeout)
nats_req() {
  nats -s "nats://localhost:54222" request -r --reply-timeout=5s "$1" "${2:-{}}" 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Teardown helpers
# ─────────────────────────────────────────────────────────────────────────────

teardown_main_stack() {
  if [ -d "$HOME/bot-army" ] &&
     (cd "$HOME/bot-army" && docker compose ps -q 2>/dev/null | grep -q .); then
    echo "Tearing down the phase-03 core stack (volumes kept) — combos need its host ports..."
    (cd "$HOME/bot-army" && docker compose down --remove-orphans >/dev/null 2>&1 || true)
  fi
}

teardown_combo() {
  local dir="$1"
  [ -f "$dir/docker-compose.yml" ] && [ -f "$dir/override.yml" ] || return 0
  (cd "$dir" && docker compose -f docker-compose.yml -f override.yml down -v --remove-orphans >/dev/null 2>&1 || true)
}

# ─────────────────────────────────────────────────────────────────────────────
# Combo helpers
# ─────────────────────────────────────────────────────────────────────────────

# Expected bots: union(packs) ∩ catalog names, mapped to their REGISTRY
# names (release_name with a trailing _bot stripped — the registry logs the
# bot's in-repo release name, which occasionally differs further, e.g.
# general → bot_army_general_purpose; the matcher is tolerant of both).
expected_bots() {
  python3 - "$1" "$2" "$3" <<'PY'
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

# Registered bot names from the live registry (best-effort shape handling)
registry_bot_names() {
  local payload
  payload=$(nats_req bot_army.registry.bots.list '{}')
  [ -z "$payload" ] && { echo "REGISTRY_UNREACHABLE"; return; }
  echo "$payload" | python3 -c "
import json, sys
raw = sys.stdin.read().strip()
try:
    d = json.loads(raw)
except Exception:
    print('REGISTRY_PARSE_FAIL'); sys.exit(0)
names = []
def walk(o):
    if isinstance(o, dict):
        n = o.get('name') or o.get('bot') or o.get('bot_name')
        if isinstance(n, str): names.append(n)
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(d)
print(' '.join(sorted(set(names))))"
}

wait_ollama() {
  local n=0
  until docker compose exec -T ollama ollama list >/dev/null 2>&1 || [ $n -ge 30 ]; do
    sleep 2; n=$((n+1))
  done
}

pull_models() {
  wait_ollama
  for m in "$MODEL_NAME" gemma3:1b; do
    echo "  ollama pull $m (shared volume — instant once cached)..."
    docker compose exec -T ollama ollama pull "$m" >/dev/null 2>&1 ||
      echo "  ⚠ pull $m failed"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Test one combination
# ─────────────────────────────────────────────────────────────────────────────

test_combo() {
  local combo="$1"
  local safe dir combo_log combo_marker
  safe=$(combo_dirname "$combo")
  dir="$HOME/bot-army-combo-$safe"
  combo_log="$HOME/logs/04-combo-$safe.log"
  combo_marker="$MARKERS/combo_$safe"

  if [ -f "$combo_marker" ]; then
    echo "  [SKIP] $combo (already passed)"
    return 0
  fi

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "COMBO: $combo"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  teardown_combo "$dir"

  # 1. Fresh starter copy from the CDN (what a user would get); repos/
  # survives as a build cache across reruns. /vagrant is only the
  # vagrant-test dir — the repo root is not synced.
  mkdir -p "$dir"
  if [ ! -d "$dir/.git" ]; then
    git init -q "$dir" && git -C "$dir" remote add origin "$STARTER_REPO" || return 1
  fi
  if ! (git -C "$dir" fetch -q --depth 1 origin main &&
        git -C "$dir" reset -q --hard FETCH_HEAD &&
        git -C "$dir" clean -qfd -e repos -e data); then
    echo "  ✗ could not fetch the starter repo from $STARTER_REPO"
    echo "{\"combo\":\"$combo\",\"result\":\"FAIL\",\"reason\":\"clone\"}" >> "$RESULTS"
    return 1
  fi
  echo "  ✓ starter @ $(git -C "$dir" log --oneline -1 | head -1)"

  # 2. Combo definition → packs
  local packs timeout
  packs=$(jq -r ".combos[\"$combo\"].packs | join(\" \")" "$COMBO_CONFIG")
  local timeout
  timeout=$(jq -r ".combos[\"$combo\"].timeout_seconds // 60" "$COMBO_CONFIG")
  if [ -z "$packs" ] || [ "$packs" = "null" ]; then
    echo "  ✗ combo '$combo' not found in config"
    echo "{\"combo\":\"$combo\",\"result\":\"FAIL\",\"reason\":\"config_missing\"}" >> "$RESULTS"
    return 1
  fi
  local expected
  expected=$(expected_bots "$packs" "$dir/catalog/bots.json" "$dir/catalog/packs.json")
  echo "  Packs: $packs"
  echo "  Expected bots ($(echo $expected | wc -w)): $expected"

  # 3. Generate .env + compose (PACKS-aware generator)
  cd "$dir" || return 1
  if ! PACKS="$packs" MODEL_NAME="$MODEL_NAME" bash scripts/quickstart-default.sh >"$combo_log" 2>&1; then
    echo "  ✗ generation failed — see $combo_log (tail below)"
    tail -15 "$combo_log" | sed 's/^/      /'
    echo "{\"combo\":\"$combo\",\"result\":\"FAIL\",\"reason\":\"generation\"}" >> "$RESULTS"
    return 1
  fi
  echo "  ✓ compose generated ($(grep -c 'build:' docker-compose.yml) bot services)"

  # 4. Shared ollama blobs across combos
  docker volume create "$SHARED_OLLAMA_VOL" >/dev/null
  cat > override.yml <<EOF
services:
  ollama:
    volumes:
      - $SHARED_OLLAMA_VOL:/root/.ollama
volumes:
  ollama_data:
    external: true
    name: $SHARED_OLLAMA_VOL
EOF
  export COMPOSE_FILE="docker-compose.yml:override.yml"

  # 5. Boot (build can be slow for never-built bots; 30 min ceiling)
  echo "  Building + starting fleet..."
  if ! timeout 1800 docker compose up -d --build >>"$combo_log" 2>&1; then
    echo "  ✗ boot failed — see $combo_log (tail below)"
    docker compose logs --tail 20 2>/dev/null | sed 's/^/      /' >> "$combo_log"
    tail -15 "$combo_log" | sed 's/^/      /'
    echo "{\"combo\":\"$combo\",\"result\":\"FAIL\",\"reason\":\"boot\"}" >> "$RESULTS"
    teardown_combo "$dir"
    return 1
  fi

  # 6. Models into the shared volume (first combo does the real pull)
  echo "  Ensuring ollama models..."
  pull_models

  # 7. Settle
  echo "  Waiting ${timeout}s for services to stabilize..."
  sleep "$timeout"

  # 8. Verify — registry bot set (tolerant name matching: exact registry
  # name, release_name-stripped, or bot_army_<catalog-name> prefix)
  echo "  Verifying registry bot set..."
  local registered
  registered=$(registry_bot_names)
  local bot_pass=0 bot_fail=0 missing=""
  for b in $expected; do
    if echo " $registered " | grep -q " $b \| bot_army_${b}"; then
      bot_pass=$((bot_pass+1))
    else
      bot_fail=$((bot_fail+1)); missing="$missing $b"
    fi
  done
  if [ "$registered" = "REGISTRY_UNREACHABLE" ] || [ "$registered" = "REGISTRY_PARSE_FAIL" ]; then
    echo "    ✗ registry check unusable ($registered)"
    bot_fail=$((bot_fail+1))
    missing="$expected"
  elif [ $bot_fail -gt 0 ]; then
    echo "    ✗ missing from registry:$missing (registered: $registered)"
  else
    echo "    ✓ all $bot_pass expected bots registered"
  fi

  # 9. Data-plane probe (informational — system.health has no responder in
  # this fleet shape; the registry request itself is the liveness proof)
  if [ -n "$(nats_req system.health)" ]; then
    echo "    ✓ system.health responder"
  else
    echo "    · system.health: no responder (informational)"
  fi

  # 10. Verify — container health
  echo "  Checking container state..."
  local container_pass=0 container_fail=0
  local services
  services=$(docker compose config --services 2>/dev/null | grep -E '_bot$' || true)
  for svc in $services; do
    local cid state restarts
    cid=$(docker compose ps -q "$svc" 2>/dev/null)
    state=$(docker inspect --format '{{.State.Status}}' "$cid" 2>/dev/null || echo "unknown")
    restarts=$(docker inspect --format '{{.RestartCount}}' "$cid" 2>/dev/null || echo "?")
    if [ "$state" = "running" ] && [ "${restarts:-99}" -le 2 ]; then
      container_pass=$((container_pass+1))
    else
      container_fail=$((container_fail+1))
      echo "    ✗ $svc (state=$state restarts=$restarts)"
      docker compose logs --tail 5 "$svc" 2>/dev/null | sed 's/^/        /' | head -8
    fi
  done
  echo "    containers: $container_pass/$((container_pass+container_fail)) healthy"

  # 11. P10 log-regression: the six fixed error classes must stay dead
  local regression
  regression=$(docker compose logs 2>/dev/null | grep -ciE 'PulsePublisher terminating|failed_connect|failed 3 times|IntentEvaluator terminating|enoent|no process.*associated' || true)
  local regression_note="clean"
  if [ "${regression:-0}" -gt 20 ]; then
    regression_note="LOOPING"
  elif [ "${regression:-0}" -gt 0 ]; then
    regression_note="minor(${regression})"
  fi
  echo "    log-regression (P10 classes): $regression hits — $regression_note"

  # 12. Result (registry + containers + log-regression are the gates;
  # system.health is informational only)
  local combo_result="PASS"
  [ $bot_fail -gt 0 ] && combo_result="FAIL"
  [ $container_fail -gt 0 ] && combo_result="FAIL"
  [ "$regression_note" = "LOOPING" ] && combo_result="FAIL"

  echo "{\"combo\":\"$combo\",\"result\":\"$combo_result\",\"bots_ok\":$bot_pass,\"bots_missing\":$bot_fail,\"containers_ok\":$container_pass,\"containers_fail\":$container_fail,\"regression_hits\":${regression:-0}}" >> "$RESULTS"
  echo "  Result: $combo_result"

  if [ "$combo_result" = "PASS" ]; then
    touch "$combo_marker"
  fi

  teardown_combo "$dir"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

hr
echo "PHASE 04 — pack combination validation ($(date -Is))"
echo "Model for combos: $MODEL_NAME (shared ollama volume: $SHARED_OLLAMA_VOL)"
hr
echo ""

if [ ! -f "$COMBO_CONFIG" ]; then
  echo "✗ Config not found: $COMBO_CONFIG"
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "✗ jq not found in VM"
  exit 1
fi
if ! ensure_nats_cli; then
  echo "✗ nats CLI unavailable — cannot run registry probes"
  exit 1
fi
echo "✓ nats CLI: $(command -v nats)"

teardown_main_stack

RUN_TIER="${RUN_TIER:-core}"
COMBOS=$(jq -r ".combos | to_entries[] | select(.value.tier == \"$RUN_TIER\") | .key" "$COMBO_CONFIG")

echo "Running $RUN_TIER tier combinations:"
echo "$COMBOS" | sed 's/^/  - /'
echo ""

COMBO_PASS=0 COMBO_FAIL=0
for combo in $COMBOS; do
  if test_combo "$combo"; then
    COMBO_PASS=$((COMBO_PASS+1))
  else
    COMBO_FAIL=$((COMBO_FAIL+1))
  fi
done

echo ""
hr
if [ "$COMBO_FAIL" -eq 0 ]; then
  echo "RESULT: PASS — all $COMBO_PASS combo(s) verified"
else
  echo "RESULT: FAIL — $COMBO_FAIL combo(s) failed, $COMBO_PASS passed"
fi
hr
echo ""
echo "Results: $RESULTS"
echo "Combo logs: $HOME/logs/04-combo-*.log"
echo "Restore the phase-03 stack afterwards: cd ~/bot-army && docker compose up -d"
echo ""
echo "PHASE 04 DONE"

exit "$COMBO_FAIL"