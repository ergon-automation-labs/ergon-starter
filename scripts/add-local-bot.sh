#!/bin/bash
# Add a locally-created bot to docker-compose.yml
# Usage: ./scripts/add-local-bot.sh /path/to/bot_army_mybot

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

error() {
  echo -e "${RED}✗ Error: $1${NC}" >&2
  exit 1
}

success() {
  echo -e "${GREEN}✓ $1${NC}"
}

info() {
  echo -e "${YELLOW}ℹ $1${NC}"
}

# Check arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <path-to-bot-directory>"
  echo ""
  echo "Example:"
  echo "  $0 /Users/abby/code/elixir_bots/bot_army_mybot"
  exit 1
fi

BOT_PATH="$1"
COMPOSE_FILE="docker-compose.yml"

# Validate the path exists
[ -d "$BOT_PATH" ] || error "Bot directory not found: $BOT_PATH"

# Validate it's a valid bot directory
[ -f "$BOT_PATH/mix.exs" ] || error "Not a valid bot directory (no mix.exs found)"

# Extract bot name from path
BOT_DIR=$(basename "$BOT_PATH")
if [[ ! $BOT_DIR =~ ^bot_army_(.+)$ ]]; then
  error "Directory must start with 'bot_army_' (e.g., bot_army_mybot)"
fi

BOT_NAME="${BASH_REMATCH[1]}"
RELEASE_NAME="${BOT_NAME}_bot"

info "Adding bot: $BOT_NAME"
info "Release name: $RELEASE_NAME"
info "Path: $BOT_PATH"

# Check compose file exists
[ -f "$COMPOSE_FILE" ] || error "docker-compose.yml not found — run 'make quickstart' first"

# Check if already present
if grep -q "$RELEASE_NAME:" "$COMPOSE_FILE"; then
  error "$RELEASE_NAME is already in $COMPOSE_FILE"
fi

# Determine if this bot needs PostgreSQL (check for mix.exs dependencies)
NEEDS_DB=false
if grep -q "ecto\|postgres" "$BOT_PATH/mix.exs" 2>/dev/null; then
  NEEDS_DB=true
  info "Detected database dependency"
fi

# Determine relative path from bot-army-starter to bot repo
RELATIVE_PATH=$(python3 -c "import os.path; print(os.path.relpath('$BOT_PATH', '.'))" 2>/dev/null || echo "../elixir_bots/$BOT_DIR")

info "Relative path: $RELATIVE_PATH"

# Build the service definition
SERVICE=$(cat <<EOF

  $RELEASE_NAME:
    build:
      context: $RELATIVE_PATH
      dockerfile: Dockerfile
    image: $RELEASE_NAME:latest
    env_file: .env
    volumes:
      - ./data/logs/$BOT_NAME:/var/log/bot_army
      - para:/opt/app/para
    depends_on:
      nats:
        condition: service_started
EOF
)

if [ "$NEEDS_DB" = true ]; then
  SERVICE+=$(cat <<EOF

      postgres:
        condition: service_healthy
EOF
)
fi

SERVICE+=$(cat <<EOF

    restart: unless-stopped
EOF
)

# Insert before "volumes:" section
if grep -q "^volumes:" "$COMPOSE_FILE"; then
  # Create temp file
  TEMP_FILE=$(mktemp)

  # Insert service before "volumes:"
  awk "/^volumes:/ {print \"$SERVICE\"; print} !/^volumes:/" "$COMPOSE_FILE" > "$TEMP_FILE"

  # Replace original
  mv "$TEMP_FILE" "$COMPOSE_FILE"
else
  # No volumes section, append at end
  echo "$SERVICE" >> "$COMPOSE_FILE"
fi

success "Added $BOT_NAME to docker-compose.yml"
echo ""
echo "Next steps:"
echo "  1. Start the bot: docker compose up -d --build $RELEASE_NAME"
echo "  2. View logs: docker compose logs -f $RELEASE_NAME"
echo "  3. Check status: make status"
echo ""
echo "Or use:"
echo "  docker compose up -d --build  # Start all services"
