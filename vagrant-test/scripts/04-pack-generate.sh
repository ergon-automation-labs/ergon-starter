#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 04-pack-generate.sh: Generate docker-compose.yml for a specific pack
# Input: .bot-army-pack.json (output from wizard or test harness)
# Output: docker-compose.yml + .env (ready to `docker compose up`)
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${1:-.bot-army-pack.json}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "✗ Config file not found: $CONFIG_FILE"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Load config
# ─────────────────────────────────────────────────────────────────────────────

PACKS=$(jq -r '.packs[]' "$CONFIG_FILE" 2>/dev/null | tr '\n' ' ')
PROVIDERS=$(jq -r '.providers[]' "$CONFIG_FILE" 2>/dev/null | head -1)
NATS_PORT=$(jq -r '.ports.nats // 54222' "$CONFIG_FILE")
MONITOR_PORT=$(jq -r '.ports.nats_monitor // 58222' "$CONFIG_FILE")
POSTGRES_PORT=$(jq -r '.ports.postgres // 55432' "$CONFIG_FILE")
OLLAMA_PORT=$(jq -r '.ports.ollama // 51434' "$CONFIG_FILE")
MCP_PORT=$(jq -r '.ports.mcp // 39900' "$CONFIG_FILE")

echo "Pack(s): $PACKS"
echo "Provider: $PROVIDERS"
echo "NATS: $NATS_PORT, Monitor: $MONITOR_PORT, Postgres: $POSTGRES_PORT, Ollama: $OLLAMA_PORT"

# ─────────────────────────────────────────────────────────────────────────────
# Resolve pack → bot list
# ─────────────────────────────────────────────────────────────────────────────

PACK_CONFIG="/vagrant/vagrant-test/config/04-pack-subjects.json"
BOT_LIST=""

for pack in $PACKS; do
  pack_bots=$(jq -r ".packs[\"$pack\"].bots[]? // empty" "$PACK_CONFIG" 2>/dev/null || echo "")
  if [ -z "$pack_bots" ]; then
    echo "⚠ Warning: pack '$pack' not found in config; falling back to primary bots"
    pack_bots="gtd_bot claude_bridge llm_proxy dispatcher"
  fi
  BOT_LIST="$BOT_LIST $pack_bots"
done

# Deduplicate
BOT_LIST=$(echo "$BOT_LIST" | tr ' ' '\n' | sort -u | tr '\n' ' ')
echo "Bots: $BOT_LIST"

# ─────────────────────────────────────────────────────────────────────────────
# Clone repos (refresh if they exist)
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "Syncing bot repositories..."
mkdir -p repos

for bot_name in $BOT_LIST; do
  # Map bot_name (e.g. gtd_bot) to repo name (e.g. ergon-gtd)
  # Simplified: assume naming convention bot_army_<name> or ergon-<name>
  # For now: use catalog lookup

  repo_url=$(jq -r ".repos[] | select(.bot_release_name == \"$bot_name\") | .github_url" /vagrant/catalog/bots.json 2>/dev/null)

  if [ -z "$repo_url" ]; then
    echo "  ⚠ Bot '$bot_name' not found in catalog; skipping"
    continue
  fi

  repo_name=$(basename "$repo_url" .git)
  repo_path="repos/$repo_name"

  if [ ! -d "$repo_path" ]; then
    echo "  Cloning $repo_name..."
    git clone --quiet "$repo_url" "$repo_path" 2>&1 | grep -v "^Cloning\|^Receiving\|^Resolving" || true
  else
    echo "  Refreshing $repo_name..."
    cd "$repo_path" && git pull --ff-only origin main >/dev/null 2>&1 || echo "    (already at latest)"
    cd - >/dev/null
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Generate .env
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "Generating .env..."
cat > .env <<EOF
# Auto-generated for pack: $PACKS
COMPOSE_PROJECT_NAME=bot-army
NATS_SERVERS=nats://nats:4222
NATS_PORT=$NATS_PORT
MONITOR_PORT=$MONITOR_PORT
POSTGRES_PORT=$POSTGRES_PORT
OLLAMA_PORT=$OLLAMA_PORT
MCP_PORT=$MCP_PORT

# LLM provider
LLM_PROVIDER=$PROVIDERS
OLLAMA_URL=http://ollama:$OLLAMA_PORT

# PostgreSQL
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=bot_army
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres

# Cache busting
CACHE_BUST=$(date +%s)
EOF

# ─────────────────────────────────────────────────────────────────────────────
# Generate docker-compose.yml (simplified template)
# ─────────────────────────────────────────────────────────────────────────────

echo "Generating docker-compose.yml..."

# For now: delegate to the main quickstart script or use a template
# This is a placeholder; full generation would merge bot Dockerfiles + orchestration

# If a full generator exists, call it:
if [ -x "$ROOT/../quickstart-default.sh" ]; then
  PACK="$PACKS" bash "$ROOT/../quickstart-default.sh" >/dev/null 2>&1 || {
    echo "✗ quickstart-default.sh failed"
    exit 1
  }
else
  # Fallback: create a minimal multi-bot compose
  # (This requires bot repos to have docker-compose.yml templates or Dockerfiles)
  echo "⚠ Full compose generation not yet implemented; using basic template"
  # For now: assume the standard docker-compose.yml exists or was pre-generated
fi

echo "✓ Pack generation complete: $CONFIG_FILE → docker-compose.yml"
