#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# check-ports.sh: Verify bot-army-starter ports are accessible
# Tests host ports → VM ports → container services
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║ Bot Army Starter — Port Connectivity Check                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Define ports
declare -A PORTS=(
  ["NATS Client"]="54222"
  ["NATS Monitor"]="58222"
  ["PostgreSQL"]="55432"
  ["Ollama"]="51434"
  ["MCP Server"]="39900"
)

# Test function
test_port() {
  local name="$1"
  local port="$2"

  if timeout 2 bash -c "cat < /dev/null > /dev/tcp/localhost/$port" 2>/dev/null; then
    echo "  ✓ $name ($port) — responding"
    return 0
  else
    echo "  ✗ $name ($port) — timeout or not running"
    return 1
  fi
}

echo "Testing host ports (localhost:XXXX):"
echo ""

pass=0
fail=0
for name in "${!PORTS[@]}"; do
  if test_port "$name" "${PORTS[$name]}"; then
    ((pass++)) || true
  else
    ((fail++)) || true
  fi
done

echo ""
echo "Summary: $pass responding, $fail not responding"
echo ""

# Detailed checks
if (( pass > 0 )); then
  echo "Detailed health checks:"
  echo ""

  # NATS Monitor
  if timeout 2 bash -c "cat < /dev/null > /dev/tcp/localhost/58222" 2>/dev/null; then
    echo "  NATS Monitor HTTP:"
    curl -s http://localhost:58222/healthz 2>/dev/null | head -3 || echo "    (no response)"
  fi

  # PostgreSQL (try psql if available)
  if command -v psql >/dev/null 2>&1 && timeout 2 bash -c "cat < /dev/null > /dev/tcp/localhost/55432" 2>/dev/null; then
    echo ""
    echo "  PostgreSQL:"
    psql -h localhost -p 55432 -U postgres -d bot_army -c "SELECT version();" 2>/dev/null | head -1 || echo "    (psql failed, but port is open)"
  fi

  # Ollama
  if timeout 2 bash -c "cat < /dev/null > /dev/tcp/localhost/51434" 2>/dev/null; then
    echo ""
    echo "  Ollama:"
    curl -s http://localhost:51434/api/tags 2>/dev/null | jq '.models | length' 2>/dev/null | xargs echo "    Models loaded:" || echo "    (API error, but port is open)"
  fi
fi

echo ""
echo "For detailed info, see: PORTMAP.md"
echo "To troubleshoot: lsof -i :<port> or docker compose logs <service>"
echo ""
