#!/bin/bash
# Push built images to the local Docker registry.
#
# Usage:
#   REGISTRY=localhost:32000 ./scripts/registry-push.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

REGISTRY="${REGISTRY:-localhost:32000}"
CATALOG="catalog/bots.json"

if [ ! -f "$CATALOG" ]; then
  echo "Error: $CATALOG not found" >&2
  exit 1
fi

# Verify registry is reachable
if ! curl -s "http://${REGISTRY}/v2/_catalog" >/dev/null 2>&1; then
  echo "Error: Registry at ${REGISTRY} is not reachable" >&2
  echo "Start it with: docker run -d -p 32000:5000 --name registry registry:2" >&2
  exit 1
fi

# Get all core bots (excluding libraries)
bots=$(python3 -c "
import json
bots = json.load(open('$CATALOG'))
for b in bots:
    if b['category'] == 'core' and not b['repo'].startswith('bot_army_library_'):
        print(b['release_name'])
")

# Push MCP + core bot images
for image in elixir_tools_mcp_bot $bots; do
  [ -z "$image" ] && continue
  tag="${REGISTRY}/${image}:latest"

  if docker image inspect "${tag}" >/dev/null 2>&1; then
    echo "  Pushing ${tag}..."
    docker push "${tag}" 2>&1 || echo "  ⚠ Push failed for ${tag}"
  else
    echo "  ⚠ ${tag} not found locally — skip (run make registry-build first)"
  fi
done

echo ""
echo "✓ Images pushed to ${REGISTRY}"