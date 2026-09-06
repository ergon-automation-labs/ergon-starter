#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# status-dashboard.sh: Show current phase test status at a glance
# Reads phase logs and displays a quick pass/fail matrix with timing
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

LOG_DIR="${HOME}/logs"
MARKER_DIR="${HOME}/.phase0*/markers"

# ─────────────────────────────────────────────────────────────────────────────
# Utilities
# ─────────────────────────────────────────────────────────────────────────────

color_pass() { echo -e "\033[32m✓\033[0m $1"; }  # green checkmark
color_fail() { echo -e "\033[31m✗\033[0m $1"; }  # red X
color_skip() { echo -e "\033[33m⊘\033[0m $1"; }  # yellow dash
color_header() { echo -e "\033[1;36m$1\033[0m"; }  # cyan bold
color_stat() { echo -e "\033[36m$1\033[0m"; }  # cyan

parse_phase_result() {
  local log_file="$1"
  if [ ! -f "$log_file" ]; then
    echo "NOTRUN"
    return 0
  fi

  # Look for the RESULT line at the end of the log
  if grep -q "^RESULT: PASS" "$log_file"; then
    echo "PASS"
  elif grep -q "^RESULT: FAIL" "$log_file"; then
    echo "FAIL"
  elif grep -q "PHASE.*DONE" "$log_file"; then
    echo "DONE"
  else
    echo "RUNNING"
  fi
}

phase_duration() {
  local log_file="$1"
  if [ ! -f "$log_file" ]; then
    echo "-"
    return 0
  fi

  # Extract first and last timestamp
  local first=$(grep "^\[" "$log_file" 2>/dev/null | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}')
  local last=$(grep "^\[" "$log_file" 2>/dev/null | tail -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}')

  if [ -n "$first" ] && [ -n "$last" ]; then
    # Calculate difference in seconds (works on macOS + Linux)
    local first_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$first" +%s 2>/dev/null || date -d "$first" +%s 2>/dev/null || echo "0")
    local last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$last" +%s 2>/dev/null || date -d "$last" +%s 2>/dev/null || echo "0")
    local duration=$((last_epoch - first_epoch))
    if [ $duration -gt 0 ]; then
      printf "%dm%02ds" $((duration / 60)) $((duration % 60))
      return 0
    fi
  fi

  echo "-"
}

phase_timestamp() {
  local log_file="$1"
  if [ ! -f "$log_file" ]; then
    echo "-"
    return 0
  fi

  # Last timestamp in the log
  grep "^\[" "$log_file" 2>/dev/null | tail -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1 || echo "-"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Dashboard
# ─────────────────────────────────────────────────────────────────────────────

clear

color_header "Bot Army Starter — Phase Status Dashboard"
echo ""
echo "$(date '+%Y-%m-%d %H:%M:%S %Z') ($(hostname))"
echo ""

# Phase 01 — Install (pristine)
phase01_result=$(parse_phase_result "$LOG_DIR/01-stream.txt")
phase01_duration=$(phase_duration "$LOG_DIR/01-stream.txt")
phase01_time=$(phase_timestamp "$LOG_DIR/01-stream.txt")

# Phase 02 — Install (fixed)
phase02_result=$(parse_phase_result "$LOG_DIR/02-install-fixed.log")
phase02_duration=$(phase_duration "$LOG_DIR/02-install-fixed.log")
phase02_time=$(phase_timestamp "$LOG_DIR/02-install-fixed.log")

# Phase 03 — Verify
phase03_result=$(parse_phase_result "$LOG_DIR/03-verify.log")
phase03_duration=$(phase_duration "$LOG_DIR/03-verify.log")
phase03_time=$(phase_timestamp "$LOG_DIR/03-verify.log")

# Phase 04 — Pack Matrix
phase04_result=$(parse_phase_result "$LOG_DIR/04-pack-matrix.log")
phase04_duration=$(phase_duration "$LOG_DIR/04-pack-matrix.log")
phase04_time=$(phase_timestamp "$LOG_DIR/04-pack-matrix.log")

# Print table
echo "┌─────────┬──────────┬──────────┬────────────┐"
echo "│ Phase   │ Result   │ Duration │ Last Run   │"
echo "├─────────┼──────────┼──────────┼────────────┤"

case "$phase01_result" in
  PASS) color_pass "Phase 01  PASS     $phase01_duration      $phase01_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
  FAIL) color_fail "Phase 01  FAIL     $phase01_duration      $phase01_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
  RUNNING) color_stat "Phase 01  RUN      $phase01_duration      $phase01_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
  *) color_skip "Phase 01  —        $phase01_duration      $phase01_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
esac

case "$phase02_result" in
  PASS) color_pass "Phase 02  PASS     $phase02_duration      $phase02_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
  FAIL) color_fail "Phase 02  FAIL     $phase02_duration      $phase02_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
  RUNNING) color_stat "Phase 02  RUN      $phase02_duration      $phase02_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
  *) color_skip "Phase 02  —        $phase02_duration      $phase02_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
esac

case "$phase03_result" in
  PASS) color_pass "Phase 03  PASS     $phase03_duration      $phase03_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
  FAIL) color_fail "Phase 03  FAIL     $phase03_duration      $phase03_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
  RUNNING) color_stat "Phase 03  RUN      $phase03_duration      $phase03_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
  *) color_skip "Phase 03  —        $phase03_duration      $phase03_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
esac

case "$phase04_result" in
  PASS) color_pass "Phase 04  PASS     $phase04_duration      $phase04_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
  FAIL) color_fail "Phase 04  FAIL     $phase04_duration      $phase04_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
  RUNNING) color_stat "Phase 04  RUN      $phase04_duration      $phase04_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
  *) color_skip "Phase 04  —        $phase04_duration      $phase04_time" | awk '{printf "│ %-7s │ %s\n", $1, substr($0, index($0,$2))}' ;;
esac

echo "└─────────┴──────────┴──────────┴────────────┘"

# Summary
echo ""
color_header "Summary:"
pass_count=0
fail_count=0
run_count=0
for result in "$phase01_result" "$phase02_result" "$phase03_result" "$phase04_result"; do
  case "$result" in
    PASS) ((pass_count++)) || true ;;
    FAIL) ((fail_count++)) || true ;;
    RUNNING) ((run_count++)) || true ;;
  esac
done

echo "  Passed: $pass_count | Failed: $fail_count | Running: $run_count | Not Run: $((4 - pass_count - fail_count - run_count))"
echo ""

# Recommendations
if [ "$phase04_result" = "PASS" ]; then
  echo "✅ Distribution ready: all phases passing"
  echo "   → Vagrant flow is solid for outreach/documentation"
elif [ "$phase03_result" = "PASS" ]; then
  echo "⚠️  Phase 04 (pack matrix) not yet run"
  echo "   → Next: make phase04 (validates individual starter packs)"
elif [ "$phase02_result" = "PASS" ]; then
  echo "⚠️  Phase 03 (verify) not yet run"
  echo "   → Next: make verify (health checks for running fleet)"
else
  echo "⚠️  Install phases not yet run"
  echo "   → Start with: make all (or make phase2 if phase1 already done)"
fi

echo ""
echo "Commands:"
echo "  make phase04                 # Run pack matrix tests"
echo "  make phase04-pack PACK=Primary # Test one pack"
echo "  vagrant ssh -c 'tail -f ~/logs/04-pack-matrix.log' # Watch live"
echo ""
