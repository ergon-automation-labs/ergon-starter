#!/bin/bash
set -euo pipefail

# Bot Army one-click installer
# Usage: curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/ergon-starter/main/scripts/one-click-install.sh | bash

STARTER_REPO="https://github.com/ergon-automation-labs/ergon-starter"
INSTALLER_DIR="${HOME}/.local/bot-army"

echo "🤖 Bot Army Starter — One-Click Install"
echo ""

# 1. Clone or update ergon-starter
if [ -d "$INSTALLER_DIR/ergon-starter" ]; then
  echo "✓ ergon-starter already cloned at $INSTALLER_DIR/ergon-starter"
  cd "$INSTALLER_DIR/ergon-starter"
  git pull --quiet
else
  echo "📦 Cloning ergon-starter..."
  mkdir -p "$INSTALLER_DIR"
  git clone --quiet "$STARTER_REPO" "$INSTALLER_DIR/ergon-starter"
  cd "$INSTALLER_DIR/ergon-starter"
fi

echo ""
echo "🔧 Configuration"
echo ""

# 2. Pack selection
echo "Which bot packs would you like to include?"
echo "  (default: core)"
echo ""
echo "Available:"
echo "  core               — Essential 8 bots (GTD, Para, Skills, Dispatcher, Synapse, Bridge, LLM, Scheduler)"
echo "  learning_deepdive  — Learning systems (FSRS-5, terrain, spaced repetition)"
echo "  social_media       — YouTube, media ingestion"
echo "  areas              — Area-specific bots"
echo "  research           — Research & knowledge management (experimental)"
echo ""
read -p "Packs (comma-separated, or press Enter for 'core'): " PACKS
PACKS="${PACKS:-core}"

# 3. Port configuration
echo ""
echo "Port configuration:"
read -p "NATS port (default 4222): " NATS_PORT
NATS_PORT="${NATS_PORT:-4222}"

read -p "PostgreSQL port (default 5432): " PG_PORT
PG_PORT="${PG_PORT:-5432}"

# 4. postgres-age option
echo ""
read -p "Install Apache Postgres-Age for internal docs? (y/n, default: n): " INSTALL_AGE
INSTALL_AGE="${INSTALL_AGE:-n}"

# 5. Generate docker-compose.yml
echo ""
echo "📝 Generating docker-compose.yml..."
make generate-compose \
  PACKS="$PACKS" \
  NATS_PORT="$NATS_PORT" \
  PG_PORT="$PG_PORT" \
  > /dev/null 2>&1

if [ "$INSTALL_AGE" = "y" ] || [ "$INSTALL_AGE" = "Y" ]; then
  echo "📊 Adding postgres-age service..."
  # Append postgres-age service to docker-compose.yml if not already present
  if ! grep -q "postgres-age" docker-compose.yml; then
    cat >> docker-compose.yml << 'COMPOSE_AGE'

  postgres-age:
    image: apache/age:latest
    container_name: postgres-age
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: bot_army_age
    ports:
      - "30002:5432"
    volumes:
      - postgres-age-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres-age-data:
COMPOSE_AGE
  fi
fi

echo ""
echo "✅ Configuration complete!"
echo ""
echo "📋 Summary:"
echo "  Packs:    $PACKS"
echo "  NATS:     localhost:$NATS_PORT"
echo "  PG:       localhost:$PG_PORT"
if [ "$INSTALL_AGE" = "y" ] || [ "$INSTALL_AGE" = "Y" ]; then
  echo "  Postgres-Age: localhost:30002"
fi
echo ""
echo "🚀 Starting Bot Army..."
echo ""

# 6. Bring up services
docker compose up
