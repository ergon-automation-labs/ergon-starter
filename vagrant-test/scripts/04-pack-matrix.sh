#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Phase 04 — pack combination validation
# Tests realistic combinations of starter packs (Primary, Learning, Social, etc.)
# to ensure they work together: shared NATS, shared PostgreSQL, all bots run.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

LOG="$HOME/logs/04-pack-combinations.log"
HOST_LOG="/vagrant/logs/04-pack-combinations.log"
STATUS="/vagrant/logs/04-pack-status.txt"
MARKERS="$HOME/.phase04/markers"
RESULTS="/vagrant/logs/04-pack-results.json"
mkdir -p "$HOME/logs" /vagrant/logs "$MARKERS"

exec > >(tee -a "$LOG" "$HOST_LOG") 2>&1

# ─────────────────────────────────────────────────────────────────────────────
# Utilities
# ─────────────────────────────────────────────────────────────────────────────

hr() { echo "═══════════════════════════════════════════════════════════"; }
step() {
  local num="$1" name="$2"
  local marker="$MARKERS/step_$num"
  if [ -f "$marker" ]; then
    echo "[SKIP] Step $num (already completed) — $name"
    return 0
  fi
  echo "[$num] $name..."
  return 1
}

mark_step() {
  local num="$1"
  touch "$MARKERS/step_$num"
}

# ─────────────────────────────────────────────────────────────────────────────
# Test one combination: generate compose, boot, verify subjects, check health
# ─────────────────────────────────────────────────────────────────────────────

test_combo() {
  local combo="$1"
  local combo_dir="$HOME/bot-army-combo-$combo"
  local combo_log="$HOME/logs/04-combo-$combo.log"
  local combo_marker="$MARKERS/combo_$combo"

  if [ -f "$combo_marker" ]; then
    echo "  [SKIP] $combo (already tested)"
    return 0
  fi

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "COMBO: $combo"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Step 1: Clone bot-army for this combo (fresh copy)
  if [ ! -d "$combo_dir" ]; then
    echo "  Cloning bot-army for $combo..."
    git clone --quiet /vagrant "$combo_dir" 2>&1 | grep -v "^Cloning\|^Receiving\|^Resolving" || true
  else
    echo "  Refreshing $combo_dir..."
    cd "$combo_dir" && git pull --ff-only origin main >/dev/null 2>&1 || true
  fi

  cd "$combo_dir" || exit 1

  # Step 2: Load combo config and generate docker-compose.yml
  echo "  Loading combo definition..."
  local packs=$(jq -r ".combos[\"$combo\"].packs[]?" /vagrant/vagrant-test/config/04-pack-combinations.json | tr '\n' ' ')
  local bots=$(jq -r ".combos[\"$combo\"].bots[]?" /vagrant/vagrant-test/config/04-pack-combinations.json | tr '\n' ' ')
  local timeout=$(jq -r ".combos[\"$combo\"].timeout_seconds // 60" /vagrant/vagrant-test/config/04-pack-combinations.json)

  if [ -z "$packs" ]; then
    echo "  ✗ Combo '$combo' not found in config"
    echo "combo_$combo FAILED config_missing" >> "$RESULTS"
    mark_step "$combo"
    return 1
  fi

  echo "  Packs: $packs"
  echo "  Bots: $bots"
  echo "  Timeout: ${timeout}s"

  # Step 3: Generate config for wizard
  echo "  Generating compose for combo..."
  cat > .bot-army-combo.json <<EOF
{
  "packs": [$(echo $packs | sed 's/ /", "/g' | sed 's/^/"/; s/$/"/')],
  "providers": ["ollama"],
  "ports": {
    "nats": 54222,
    "nats_monitor": 58222,
    "postgres": 55432,
    "ollama": 51434,
    "mcp": 39900
  }
}
EOF

  # Call quickstart to generate compose (with all selected packs)
  PACKS="$packs" bash scripts/quickstart-default.sh .bot-army-combo.json >/dev/null 2>&1 || {
    echo "  ✗ Failed to generate compose for $combo"
    docker compose logs --tail 50 >>$combo_log 2>&1
    echo "combo_$combo FAILED generation" >> "$RESULTS"
    mark_step "$combo"
    return 1
  }

  # Step 4: Docker compose up (with all bots)
  echo "  Bringing up $combo fleet..."
  timeout $((timeout + 30)) docker compose up -d --build >>$combo_log 2>&1 || {
    echo "  ✗ Failed to boot $combo"
    docker compose logs --tail 50 >>$combo_log 2>&1
    echo "combo_$combo FAILED boot" >> "$RESULTS"
    return 1
  }

  # Step 5: Wait for services to settle
  echo "  Waiting ${timeout}s for services to stabilize..."
  sleep $timeout

  # Step 6: Verify all bots respond on their NATS subjects
  echo "  Testing pack subjects..."
  local subjects=$(jq -r ".combos[\"$combo\"].subjects[]?" /vagrant/vagrant-test/config/04-pack-combinations.json)
  local subject_pass=0 subject_fail=0

  for subject in $subjects; do
    if timeout 3 nats request --server nats://localhost:54222 "$subject" '{}' >/dev/null 2>&1; then
      echo "    ✓ $subject"
      ((subject_pass++)) || true
    else
      echo "    ✗ $subject (no responder or timeout)"
      ((subject_fail++)) || true
    fi
  done

  # Step 7: Check container health (all bots running, no crashes)
  echo "  Checking container state for all $combo bots..."
  local container_pass=0 container_fail=0
  local services=$(docker compose config --services | grep -E '_bot$|_server$' | grep -v '^ollama$' || true)

  for svc in $services; do
    local state=$(docker compose ps --format '{{.Name}} {{.State}}' 2>/dev/null | awk -v s="$svc" '$1 ~ s {print $2}' || echo "unknown")
    local restarts=$(docker inspect --format '{{.RestartCount}}' "$(docker compose ps -q "$svc" 2>/dev/null)" 2>/dev/null || echo "?")

    if echo "$state" | grep -q "running" && [ "${restarts:-99}" -le 2 ]; then
      echo "    ✓ $svc (restarts=$restarts)"
      ((container_pass++)) || true
    else
      echo "    ✗ $svc (state=$state restarts=$restarts)"
      ((container_fail++)) || true
      docker compose logs --tail 5 "$svc" 2>&1 | sed 's/^/        /' | head -8
    fi
  done

  # Step 8: Log results
  local combo_result="PASS"
  if [ $subject_fail -gt 0 ] || [ $container_fail -gt 0 ]; then
    combo_result="FAIL"
  fi

  echo "combo_$combo $combo_result subjects_ok=$subject_pass subjects_fail=$subject_fail containers_ok=$container_pass containers_fail=$container_fail" >> "$RESULTS"
  echo "  Result: $combo_result (subjects: $subject_pass/$((subject_pass+subject_fail)) ok, containers: $container_pass/$((container_pass+container_fail)) ok)"

  mark_step "$combo"
  touch "$combo_marker"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Main: Load combo list and test each
# ─────────────────────────────────────────────────────────────────────────────

hr
echo "PHASE 04 — pack combination validation ($(date -Is))"
hr
echo ""

COMBO_CONFIG="/vagrant/vagrant-test/config/04-pack-combinations.json"
if [ ! -f "$COMBO_CONFIG" ]; then
  echo "✗ Config not found: $COMBO_CONFIG"
  exit 1
fi

# Determine which combos to run (default: core tier)
RUN_TIER="${RUN_TIER:-core}"
COMBOS=$(jq -r ".combos[] | select(.tier == \"$RUN_TIER\") | .tier as \$t | keys[] | select(.tier == \$t)" "$COMBO_CONFIG" 2>/dev/null || \
         jq -r "to_entries[] | select(.value.tier == \"$RUN_TIER\") | .key" "$COMBO_CONFIG")

echo "Running $RUN_TIER tier combinations:"
echo "$COMBOS" | sed 's/^/  - /'
echo ""

COMBO_PASS=0 COMBO_FAIL=0
for combo in $COMBOS; do
  if test_combo "$combo"; then
    ((COMBO_PASS++)) || true
  else
    ((COMBO_FAIL++)) || true
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

echo ""
hr
if [ $COMBO_FAIL -eq 0 ]; then
  echo "RESULT: PASS — all $COMBO_PASS combo(s) verified"
else
  echo "RESULT: FAIL — $COMBO_FAIL combo(s) failed, $COMBO_PASS passed"
fi
hr
echo ""
echo "Detailed results: $RESULTS"
echo "Combo logs: $HOME/logs/04-combo-*.log"
echo ""
echo "To test extended tier (Background, Research combos):"
echo "  RUN_TIER=extended bash ./scripts/04-pack-matrix.sh"
echo ""
echo "PHASE 04 DONE"

exit $COMBO_FAIL
