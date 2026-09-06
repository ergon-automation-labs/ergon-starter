#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# tail-build.sh: Live tail of phase build logs from the host
# Reads from synced /vagrant/logs/ (no vagrant ssh needed)
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

PHASE="${1:-02}"
LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/logs" 2>/dev/null && pwd || echo "./logs")"

case "$PHASE" in
  01) LOG_FILE="$LOG_DIR/01-stream.txt" ;;
  02) LOG_FILE="$LOG_DIR/02-install-fixed.log" ;;
  03) LOG_FILE="$LOG_DIR/03-verify.log" ;;
  04) LOG_FILE="$LOG_DIR/04-pack-matrix.log" ;;
  *)
    echo "Usage: $0 [01|02|03|04]"
    echo ""
    echo "Examples:"
    echo "  $0 02          # Tail phase 02 (install-fixed)"
    echo "  $0 04          # Tail phase 04 (pack matrix)"
    echo ""
    exit 1
    ;;
esac

if [ ! -d "$LOG_DIR" ]; then
  echo "Error: logs directory not found at $LOG_DIR"
  echo "Make sure you've run a phase first (e.g., make phase02)"
  exit 1
fi

echo "Tailing Phase $PHASE from host: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo ""
echo "─────────────────────────────────────────────────────────────"
echo ""

tail -f "$LOG_FILE"
