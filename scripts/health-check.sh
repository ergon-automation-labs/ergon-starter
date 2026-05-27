#!/bin/bash
# Health check for Bot Army installation
# Verifies NATS, PostgreSQL, bots, and Claude integration

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

pass() {
  echo -e "${GREEN}✓${NC} $1"
}

fail() {
  echo -e "${RED}✗${NC} $1"
}

warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

header() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Check docker-compose file
header "Infrastructure"

if [ ! -f docker-compose.yml ]; then
  fail "docker-compose.yml not found (run 'make quickstart' first)"
  exit 1
fi
pass "docker-compose.yml found"

# Check .env
if [ ! -f .env ]; then
  fail ".env not found"
  exit 1
fi
pass ".env found"

# Check Docker daemon
if ! docker info >/dev/null 2>&1; then
  fail "Docker daemon not running"
  echo "  Start Docker Desktop"
  exit 1
fi
pass "Docker daemon running"

# Check services
header "Services"

RUNNING_SERVICES=$(docker compose ps --services --filter "status=running" 2>/dev/null || echo "")
TOTAL_SERVICES=$(docker compose config --services 2>/dev/null | wc -l)

info "Configured services: $TOTAL_SERVICES"

if [ -z "$RUNNING_SERVICES" ]; then
  warn "No services running"
  echo "  Start with: docker compose up -d"
else
  RUNNING_COUNT=$(echo "$RUNNING_SERVICES" | wc -l)
  if [ $RUNNING_COUNT -lt $TOTAL_SERVICES ]; then
    warn "$RUNNING_COUNT/$TOTAL_SERVICES services running"
  else
    pass "All services running ($RUNNING_COUNT/$TOTAL_SERVICES)"
  fi
fi

# Check NATS
header "NATS (Message Bus)"

NATS_PORT=$(grep "STARTER_NATS_PORT" .env | cut -d= -f2)
if [ -z "$NATS_PORT" ]; then
  NATS_PORT=54222
fi

if timeout 2 bash -c "echo 'INFO' | nc -w 1 localhost $NATS_PORT" >/dev/null 2>&1; then
  pass "NATS responding on port $NATS_PORT"

  # Try NATS request
  if command -v nats >/dev/null 2>&1; then
    if nats request --server "nats://localhost:$NATS_PORT" "system.health" "{}" --timeout 2s >/dev/null 2>&1; then
      pass "NATS request/reply working"
    else
      warn "NATS connected but no responders (bots may not be running yet)"
    fi
  fi
else
  fail "NATS not responding on port $NATS_PORT"
  echo "  Check: docker compose logs nats"
fi

# Check PostgreSQL
header "PostgreSQL (Database)"

PG_PORT=$(grep "STARTER_POSTGRES_PORT" .env | cut -d= -f2)
if [ -z "$PG_PORT" ]; then
  PG_PORT=55432
fi

if timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/$PG_PORT" 2>/dev/null; then
  pass "PostgreSQL listening on port $PG_PORT"

  # Try connecting
  if command -v psql >/dev/null 2>&1; then
    if PGPASSWORD=postgres psql -h localhost -p $PG_PORT -U postgres -d postgres -c "SELECT 1" >/dev/null 2>&1; then
      pass "PostgreSQL connection successful"
    else
      warn "PostgreSQL running but connection failed (check credentials)"
    fi
  fi
else
  fail "PostgreSQL not responding on port $PG_PORT"
  echo "  Check: docker compose logs postgres"
fi

# Check bots
header "Bots"

if [ -f .bot-army.json ]; then
  BOT_COUNT=$(grep -o '"name"' .bot-army.json | wc -l)
  pass "Configured bots: $BOT_COUNT"

  # Check if any are running
  if docker compose ps --filter "status=running" | grep -q "bot"; then
    pass "At least one bot is running"
  else
    warn "No bots running"
    echo "  Start with: docker compose up -d"
  fi
else
  warn "No .bot-army.json found (configuration may be incomplete)"
fi

# Check volumes
header "Storage"

if [ -d "data" ]; then
  pass "data/ directory found"

  if [ -d "data/para" ]; then
    PARA_ITEMS=$(find data/para -type f 2>/dev/null | wc -l)
    pass "PARA directory found ($PARA_ITEMS files)"
  else
    info "PARA directory not yet created (will be created by para_bot)"
  fi

  if [ -d "data/logs" ]; then
    LOG_FILES=$(find data/logs -type f 2>/dev/null | wc -l)
    info "Logs directory found ($LOG_FILES log files)"
  fi
else
  warn "data/ directory not found"
  echo "  Will be created when bots start"
fi

# Check Claude integration
header "Claude Integration"

if [ -f "$HOME/.claude/claude.json" ]; then
  if grep -q "bot-army" "$HOME/.claude/claude.json"; then
    pass "Claude Desktop MCP configured"
  else
    warn "Claude Desktop configured but no bot-army MCP"
    echo "  See: make claude-integrate"
  fi
else
  warn "Claude Desktop not configured"
  echo "  See: make claude-integrate"
fi

# Check for Claude Code
if command -v claude >/dev/null 2>&1; then
  pass "Claude Code CLI found"
else
  warn "Claude Code CLI not found (optional)"
  echo "  See: make claude-integrate"
fi

# Summary
header "Summary"

echo ""
echo "Next steps:"
echo "  1. Verify all services are running: docker compose ps"
echo "  2. Check logs: docker compose logs -f"
echo "  3. View dashboard: make dashboard"
echo "  4. Try a demo: see docs/QUICK_START.md"
echo ""
