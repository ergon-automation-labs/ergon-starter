#!/bin/bash
# Build all core bot images tagged for the local Docker registry.
# Requires: repos/ cloned (run quickstart-default.sh first or manually).
#
# Usage:
#   REGISTRY=localhost:32000 ./scripts/registry-build.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

REGISTRY="${REGISTRY:-localhost:32000}"
CATALOG="catalog/bots.json"

if [ ! -f "$CATALOG" ]; then
  echo "Error: $CATALOG not found — run 'make sync' first" >&2
  exit 1
fi

if [ ! -d "repos" ]; then
  echo "Error: repos/ not found — run quickstart-default.sh or clone repos first" >&2
  exit 1
fi

# Ensure .dockerignore exists
if [ ! -f "repos/.dockerignore" ]; then
  cat > repos/.dockerignore << 'DOCKERIGNORE'
**/deps
**/_build
**/.git
**/.elixir_ls
**/doc
**/test
**/*.beam
**/*.ez
DOCKERIGNORE
fi

# Get all core bots (excluding libraries — they're built into the base image)
bots=$(python3 -c "
import json
bots = json.load(open('$CATALOG'))
for b in bots:
    if b['category'] == 'core' and not b['repo'].startswith('bot_army_library_'):
        print(b['repo'], b['release_name'])
")

echo "Building base image (shared libraries)..."
DOCKER_BUILDKIT=1 docker build -f Dockerfile --target base -t bot-army-base:latest ./repos
echo "  ✓ base image"

while IFS=' ' read -r repo release; do
  [ -z "$repo" ] && continue
  tag="${REGISTRY}/${release}:latest"

  echo "  Building ${release}..."
  DOCKER_BUILDKIT=1 docker build -f Dockerfile \
    --build-arg BOT_NAME="${release}" \
    --build-arg BOT_REPO="${repo}" \
    -t "${tag}" \
    ./repos
  echo "  ✓ ${tag}"
done <<< "$bots"

# Also build the MCP server
echo "  Building elixir_tools_mcp_bot..."
DOCKER_BUILDKIT=1 docker build -f Dockerfile \
  --build-arg BOT_NAME=elixir_tools_mcp_bot \
  --build-arg BOT_REPO=bot_army_elixir_tools_mcp \
  -t "${REGISTRY}/elixir_tools_mcp_bot:latest" \
  ./repos
echo "  ✓ ${REGISTRY}/elixir_tools_mcp_bot:latest"

echo ""
echo "✓ All images built. Push with: make registry-push"