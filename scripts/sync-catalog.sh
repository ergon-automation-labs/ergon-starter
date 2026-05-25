#!/bin/bash
# Generates bots.json catalog for the wizard from repos-public.toml.
# Source of truth: config/repos-public.toml (independent of main monorepo)
#
# Usage:
#   ./scripts/sync-catalog.sh [CHANNEL]
#   make sync                                    # defaults to stable
#   CHANNEL=nightly make sync                    # use nightly releases
#
# Supported channels: stable, latest, nightly
# Output: catalog/bots.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STARTER_ROOT="$(dirname "$SCRIPT_DIR")"
REPOS_PUBLIC_TOML="${STARTER_ROOT}/config/repos-public.toml"
OUTPUT_DIR="${STARTER_ROOT}/catalog"
OUTPUT="${OUTPUT_DIR}/bots.json"

# Channel selection (default: stable)
CHANNEL="${1:-${CHANNEL:-stable}}"

if [ ! -f "$REPOS_PUBLIC_TOML" ]; then
  echo "Error: $REPOS_PUBLIC_TOML not found" >&2
  exit 1
fi

if [ "$CHANNEL" != "stable" ] && [ "$CHANNEL" != "latest" ] && [ "$CHANNEL" != "nightly" ]; then
  echo "Error: CHANNEL must be one of: stable, latest, nightly (got: $CHANNEL)" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Generating catalog from repos-public.toml (channel: $CHANNEL)..."

bots_json="["
first=true

# Extract bot names from repos-public.toml
bot_names=$(grep '^name = "bot_army_' "$REPOS_PUBLIC_TOML" | sed 's/.*name = "//;s/".*//')

while IFS= read -r name; do
  [ -z "$name" ] && continue

  # Extract fields for this bot (next 4 lines after name declaration)
  bot_section=$(awk "/^name = \"${name}\"/{flag=1; next} flag && /^$|^\\[/{flag=0} flag" "$REPOS_PUBLIC_TOML")

  remote=$(echo "$bot_section" | grep 'remote = ' | sed 's/.*remote = "//;s/".*//')
  category=$(echo "$bot_section" | grep 'category = ' | sed 's/.*category = "//;s/".*//')
  stability=$(echo "$bot_section" | grep 'stability = ' | sed 's/.*stability = "//;s/".*//' || echo "stable")

  # Extract channel reference (e.g., stable = "stable", latest = "latest", nightly = "main")
  channels_line=$(echo "$bot_section" | grep 'channels = ')
  channel_ref=$(echo "$channels_line" | sed -n "s/.*$CHANNEL = \"\([^\"]*\)\".*/\1/p")

  if [ -z "$channel_ref" ]; then
    echo "  ⚠ ${name}: no $CHANNEL channel defined, skipping" >&2
    continue
  fi

  if [ -z "$remote" ]; then
    echo "  ⚠ ${name}: no remote defined, skipping" >&2
    continue
  fi

  if [ -z "$category" ]; then
    category="uncategorized"
  fi

  # Derive release name from bot name (bot_army_gtd -> gtd_bot)
  short_name="${name#bot_army_}"
  release_name="${short_name}_bot"

  # Build JSON entry
  if [ "$first" = true ]; then first=false; else bots_json+=","; fi

  bots_json+="
  {
    \"name\": \"${short_name}\",
    \"repo\": \"${name}\",
    \"remote\": \"${remote}\",
    \"release_name\": \"${release_name}\",
    \"category\": \"${category}\",
    \"stability\": \"${stability}\",
    \"channel\": \"${CHANNEL}\",
    \"channel_ref\": \"${channel_ref}\"
  }"

  echo "  ✓ ${name} → ${release_name} (${category}, stability=${stability}, ${CHANNEL}=${channel_ref})"

done <<< "$bot_names"

bots_json+="
]"

echo "$bots_json" > "$OUTPUT"
echo ""
echo "✓ Wrote $(echo "$bots_json" | grep -c '"name"') bots to ${OUTPUT} (channel: $CHANNEL)"
