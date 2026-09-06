#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# dashboard.sh: Show phase status by reading synced logs from the host
# No vagrant ssh needed — logs are synced to ./logs/ via /vagrant mount
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/logs" 2>/dev/null && pwd || echo "./logs")"

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

  # Check if file was modified in last 60 seconds (actively running)
  local mod_time=$(stat -f %m "$log_file" 2>/dev/null || stat -c %Y "$log_file" 2>/dev/null || echo 0)
  local now=$(date +%s)
  local age=$((now - mod_time))
  if [ $age -lt 60 ]; then
    echo "RUNNING"
    return 0
  fi

  # Look for the RESULT line at the end of the log
  if grep -q "^RESULT: PASS" "$log_file"; then
    echo "PASS"
  elif grep -q "^RESULT: FAIL" "$log_file"; then
    echo "FAIL"
  elif grep -q "PHASE.*DONE" "$log_file"; then
    echo "PASS"  # Phase completed (recognize "PHASE XX DONE" as success)
  else
    echo "DONE"
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

  grep "^\[" "$log_file" 2>/dev/null | tail -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1 || echo "-"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

clear

color_header "Bot Army Starter — Phase Status Dashboard (HOST)"
echo ""
echo "$(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Reading from: $LOG_DIR"
echo ""

# Read phase results from synced logs
phase01_log="$LOG_DIR/01-run.log"
[ -f "$phase01_log" ] || phase01_log="$LOG_DIR/01-stream.log"
[ -f "$phase01_log" ] || phase01_log="$LOG_DIR/01-stream.txt"
phase01_result=$(parse_phase_result "$phase01_log")
phase01_duration=$(phase_duration "$phase01_log")
phase01_time=$(phase_timestamp "$phase01_log")

phase02_result=$(parse_phase_result "$LOG_DIR/02-install-fixed.log")
phase02_duration=$(phase_duration "$LOG_DIR/02-install-fixed.log")
phase02_time=$(phase_timestamp "$LOG_DIR/02-install-fixed.log")

phase03_result=$(parse_phase_result "$LOG_DIR/03-verify.log")
phase03_duration=$(phase_duration "$LOG_DIR/03-verify.log")
phase03_time=$(phase_timestamp "$LOG_DIR/03-verify.log")

phase04_result=$(parse_phase_result "$LOG_DIR/04-pack-matrix.log")
phase04_duration=$(phase_duration "$LOG_DIR/04-pack-matrix.log")
phase04_time=$(phase_timestamp "$LOG_DIR/04-pack-matrix.log")

# Determine current phase
current_phase=""
if [ "$phase04_result" = "RUNNING" ]; then
  current_phase="04"
elif [ "$phase03_result" = "RUNNING" ]; then
  current_phase="03"
elif [ "$phase02_result" = "RUNNING" ]; then
  current_phase="02"
elif [ "$phase01_result" = "RUNNING" ]; then
  current_phase="01"
elif [ "$phase01_result" = "NOTRUN" ]; then
  current_phase="01"
elif [ "$phase02_result" = "NOTRUN" ]; then
  current_phase="02"
elif [ "$phase03_result" = "NOTRUN" ]; then
  current_phase="03"
elif [ "$phase04_result" = "NOTRUN" ]; then
  current_phase="04"
fi

# Print table with "You are here" marker
printf "%-10s %-10s %-10s %-20s  \n" "Phase" "Result" "Duration" "Last Run"
echo "─────────────────────────────────────────────────────────────────────────"

print_phase() {
  local phase="$1" result="$2" duration="$3" timestamp="$4"
  local marker=""
  if [ "$phase" = "Phase 0$current_phase" ]; then
    marker=" ← You are here"
  fi

  case "$result" in
    PASS)   printf "%-10s ✓ PASS    %-10s %-20s%s\n" "$phase" "$duration" "$timestamp" "$marker" ;;
    FAIL)   printf "%-10s ✗ FAIL    %-10s %-20s%s\n" "$phase" "$duration" "$timestamp" "$marker" ;;
    RUNNING) printf "%-10s ⊗ RUN     %-10s %-20s%s\n" "$phase" "$duration" "$timestamp" "$marker" ;;
    *)      printf "%-10s ⊘ —       %-10s %-20s%s\n" "$phase" "$duration" "$timestamp" "$marker" ;;
  esac
}

print_phase "Phase 01" "$phase01_result" "$phase01_duration" "$phase01_time"
print_phase "Phase 02" "$phase02_result" "$phase02_duration" "$phase02_time"
print_phase "Phase 03" "$phase03_result" "$phase03_duration" "$phase03_time"
print_phase "Phase 04" "$phase04_result" "$phase04_duration" "$phase04_time"

# Summary
echo ""
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

color_header "Summary:"
echo "  Passed: $pass_count | Failed: $fail_count | Running: $run_count | Not Run: $((4 - pass_count - fail_count - run_count))"
echo ""

# Recommendations
if [ "$phase04_result" = "PASS" ]; then
  echo "✅ Distribution ready: all phases passing"
elif [ "$phase03_result" = "PASS" ]; then
  echo "⚠️  Phase 04 (pack matrix) not yet run → Next: cd vagrant-test && make phase04"
elif [ "$phase02_result" = "PASS" ]; then
  echo "⚠️  Phase 03 (verify) not yet run → Next: cd vagrant-test && make verify"
else
  echo "⚠️  Phases not yet run → Start with: cd vagrant-test && make all"
fi

echo ""
echo "Live watch: while true; do clear; bash dashboard.sh; sleep 10; done"
echo "View logs: ls -lh logs/*.log"
echo ""
