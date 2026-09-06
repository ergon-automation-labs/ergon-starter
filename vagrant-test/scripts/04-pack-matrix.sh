#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Phase 04 — pack matrix: validate each bot pack works in isolation
# Tests that users selecting "Primary", "Learning", "Background", etc. end up
# with a working, responsive fleet for that pack's use case.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

LOG="$HOME/logs/04-pack-matrix.log"
STATUS="$HOME/logs/04-pack-matrix-status.txt"
MARKERS="$HOME/.phase04/markers"
RESULTS="$HOME/logs/04-pack-matrix-results.json"
mkdir -p "$HOME/logs" "$MARKERS"

exec > >(tee -a "$LOG") 2>&1

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
  echo "$(date -Is)" >> "$MARKERS/step_$num"
}

# ─────────────────────────────────────────────────────────────────────────────
# Test one pack: generate compose, boot, verify subjects, log results
# ─────────────────────────────────────────────────────────────────────────────

test_pack() {
  local pack="$1"
  local pack_dir="$HOME/bot-army-pack-$pack"
  local pack_log="$HOME/logs/04-pack-$pack.log"
  local pack_marker="$MARKERS/pack_$pack"

  if [ -f "$pack_marker" ]; then
    echo "  [SKIP] $pack (already tested)"
    return 0
  fi

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "PACK: $pack"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Step 1: Clone bot-army for this pack
  if [ ! -d "$pack_dir" ]; then
    echo "  Cloning bot-army for $pack..."
    git clone --quiet /vagrant "$pack_dir" 2>&1 | grep -v "^Cloning\|^Receiving\|^Resolving"
  else
    echo "  Reusing existing $pack_dir"
    cd "$pack_dir" && git pull --ff-only origin main >/dev/null 2>&1
  fi

  cd "$pack_dir" || exit 1

  # Step 2: Generate docker-compose.yml for this pack
  echo "  Generating compose for $pack..."
  cat > .bot-army-pack.json <<EOF
{
  "packs": ["$pack"],
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

  # Invoke the wizard's generate logic or use quickstart script
  # (For now: simplified — use quickstart-default.sh with PACK override)
  PACK="$pack" bash scripts/04-pack-generate.sh .bot-army-pack.json >/dev/null 2>&1 || {
    echo "  ✗ Failed to generate compose for $pack"
    echo "pack_$pack FAILED generation" >> "$RESULTS"
    mark_step "$((step_num))"
    return 1
  }

  # Step 3: Docker compose up
  echo "  Bringing up $pack fleet..."
  cd "$pack_dir"
  timeout 300 docker compose up -d --build >>$pack_log 2>&1 || {
    echo "  ✗ Failed to boot $pack"
    docker compose logs --tail 50 >>$pack_log 2>&1
    echo "pack_$pack FAILED boot" >> "$RESULTS"
    return 1
  }

  # Step 4: Wait for services to settle
  echo "  Waiting 60s for services to stabilize..."
  sleep 60

  # Step 5: Verify pack-specific NATS subjects respond
  echo "  Testing pack-specific subjects..."
  local subjects_file="/vagrant/vagrant-test/config/04-pack-subjects.json"
  local pack_subjects=$(jq -r ".packs[\"$pack\"] // [] | .[]" "$subjects_file" 2>/dev/null || echo "")

  local subject_pass=0 subject_fail=0
  for subject in $pack_subjects; do
    # Request/reply with 3s timeout
    if timeout 3 nats request --server nats://localhost:54222 "$subject" '{}' >/dev/null 2>&1; then
      echo "    ✓ $subject"
      ((subject_pass++)) || true
    else
      echo "    ✗ $subject (no responder or timeout)"
      ((subject_fail++)) || true
    fi
  done

  # Step 6: Check container health
  echo "  Checking container state..."
  local container_pass=0 container_fail=0
  local services=$(docker compose config --services | grep -E '_bot$|_server$' | grep -v '^ollama$' || true)

  for svc in $services; do
    local state=$(docker compose ps --format '{{.Name}} {{.State}}' 2>/dev/null | awk -v s="$svc" '$1 ~ s {print $2}' || echo "unknown")
    local restarts=$(docker inspect --format '{{.RestartCount}}' "$(docker compose ps -q "$svc" 2>/dev/null)" 2>/dev/null || echo "?")

    if echo "$state" | grep -q "running" && [ "${restarts:-99}" -le 2 ]; then
      echo "    ✓ $svc (state=$state restarts=$restarts)"
      ((container_pass++)) || true
    else
      echo "    ✗ $svc (state=$state restarts=$restarts)"
      ((container_fail++)) || true
      # Show last 10 lines of logs for this service
      docker compose logs --tail 10 "$svc" 2>&1 | sed 's/^/        /' | head -12
    fi
  done

  # Step 7: Log results
  local pack_result="PASS"
  if [ $subject_fail -gt 0 ] || [ $container_fail -gt 0 ]; then
    pack_result="FAIL"
  fi

  cat >> "$RESULTS" <<EOF
{
  "pack": "$pack",
  "result": "$pack_result",
  "timestamp": "$(date -Is)",
  "subjects": {
    "pass": $subject_pass,
    "fail": $subject_fail
  },
  "containers": {
    "pass": $container_pass,
    "fail": $container_fail
  }
}
EOF

  echo "  Result: $pack_result (subjects: $subject_pass/$((subject_pass+subject_fail)) ok, containers: $container_pass/$((container_pass+container_fail)) ok)"

  # Step 8: Cleanup (optional — keep for inspection, or docker compose down)
  # For now: leave running; operator can inspect logs or run tests
  # docker compose down --remove-orphans >/dev/null 2>&1

  mark_step "$pack"
  touch "$pack_marker"
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Main: load pack list and test each
# ─────────────────────────────────────────────────────────────────────────────

hr
echo "PHASE 04 — bot pack matrix validation ($(date -Is))"
hr
echo ""

# Load pack list from catalog
PACKS=$(jq -r '.packs | keys | .[]' /vagrant/vagrant-test/config/04-pack-subjects.json 2>/dev/null || echo "Primary Background")

echo "Packs to test: $PACKS"
echo ""

PACK_PASS=0 PACK_FAIL=0
for pack in $PACKS; do
  if test_pack "$pack"; then
    ((PACK_PASS++)) || true
  else
    ((PACK_FAIL++)) || true
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

echo ""
hr
if [ $PACK_FAIL -eq 0 ]; then
  echo "RESULT: PASS — all $PACK_PASS pack(s) verified"
else
  echo "RESULT: FAIL — $PACK_FAIL pack(s) failed, $PACK_PASS passed"
fi
hr
echo ""
echo "Detailed results: $RESULTS"
echo "Pack logs: $HOME/logs/04-pack-*.log"
echo "PHASE 04 DONE"

exit $PACK_FAIL
