#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# watch-all.sh: Watch ALL logs from the host in real-time
# - Phase wrapper logs (01, 02, 03, 04)
# - Docker compose logs
# - Container application logs
# - Build output
#
# Usage: bash watch-all.sh [phase]
#   watch-all.sh 02   # Watch phase 02 + docker logs
#   watch-all.sh      # Watch current/all phases
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

PHASE="${1:-02}"
LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/logs" 2>/dev/null && pwd || echo "./logs")"

# Map phase to log file
case "$PHASE" in
  01) PHASE_LOG="$LOG_DIR/01-stream.txt" ;;
  02) PHASE_LOG="$LOG_DIR/02-install-fixed.log" ;;
  03) PHASE_LOG="$LOG_DIR/03-verify.log" ;;
  04) PHASE_LOG="$LOG_DIR/04-pack-matrix.log" ;;
  all)
    # No single phase — watch all logs that exist
    PHASE_LOG=""
    ;;
  *)
    echo "Usage: $0 [01|02|03|04|all]"
    echo ""
    echo "Watch all logs from the host (no vagrant ssh needed)"
    echo ""
    echo "What it captures:"
    echo "  ✓ Phase wrapper output (01/02/03/04)"
    echo "  ✓ Docker compose build output"
    echo "  ✓ Container application logs"
    echo "  ✓ Migrations, compilation, boot output"
    echo ""
    echo "Examples:"
    echo "  bash watch-all.sh 02      # Phase 02 + docker logs"
    echo "  bash watch-all.sh 04      # Phase 04 pack matrix"
    echo "  bash watch-all.sh all     # All phase logs"
    echo ""
    exit 1
    ;;
esac

if [ ! -d "$LOG_DIR" ]; then
  mkdir -p "$LOG_DIR"
  echo "Created logs directory: $LOG_DIR"
  echo "Run a phase first: make phase02"
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Start tailing
# ─────────────────────────────────────────────────────────────────────────────

clear
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ Bot Army Starter — Live Log Watch (from host)                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ -n "$PHASE_LOG" ] && [ ! -f "$PHASE_LOG" ]; then
  echo "⚠️  Phase log not found: $PHASE_LOG"
  echo "   Run: cd vagrant-test && make phase$PHASE"
  echo ""
  exit 1
fi

# Tail phase log + docker logs together
if [ -n "$PHASE_LOG" ]; then
  echo "Tailing Phase $PHASE + Docker output..."
  echo ""
  echo "─────────────────────────────────────────────────────────────"
  echo "PHASE LOG: $PHASE_LOG"
  echo "─────────────────────────────────────────────────────────────"
  echo ""

  # Start phase log in background
  tail -f "$PHASE_LOG" &
  TAIL_PID=$!

  # Also capture docker logs if VM is running
  if command -v vagrant >/dev/null 2>&1 && [ -f "Vagrantfile" ]; then
    sleep 2  # Give phase log a moment
    echo ""
    echo "─────────────────────────────────────────────────────────────"
    echo "DOCKER & CONTAINER LOGS"
    echo "─────────────────────────────────────────────────────────────"
    echo ""

    vagrant ssh -c "cd ~/bot-army 2>/dev/null && docker compose logs -f 2>&1 || echo 'Docker not running yet'" &
    DOCKER_PID=$!
  fi

  # Wait for interruption
  trap "kill $TAIL_PID 2>/dev/null; kill $DOCKER_PID 2>/dev/null; exit 0" INT TERM
  wait
else
  # Watch ALL phase logs
  echo "Tailing all phase logs (as they complete)..."
  echo ""

  # Find all log files and tail them
  if ls "$LOG_DIR"/*.log >/dev/null 2>&1; then
    tail -f "$LOG_DIR"/*.log
  else
    echo "No logs found in $LOG_DIR"
    echo "Run a phase: make phase02"
    exit 1
  fi
fi
