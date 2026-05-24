#!/bin/bash
# Scans bot repos and generates bots.json catalog for the wizard.
# Source of truth: config/repos.toml from the monorepo + each bot's mix.exs.
#
# Usage:
#   ./scripts/sync-catalog.sh /path/to/elixir_bots
#   make sync MONOREPO=/path/to/elixir_bots
#
# Output: catalog/bots.json

set -euo pipefail

MONOREPO="${1:?Usage: sync-catalog.sh /path/to/elixir_bots}"
REPOS_TOML="${MONOREPO}/config/repos.toml"
BOTS_DIR="${MONOREPO}/../bots"
OUTPUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/catalog"
OUTPUT="${OUTPUT_DIR}/bots.json"

if [ ! -f "$REPOS_TOML" ]; then
  echo "Error: $REPOS_TOML not found" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Scanning bots from $REPOS_TOML..."

bots_json="["
first=true

# Extract bot names from repos.toml (macOS-compatible)
bot_names=$(grep 'name = "bot_army_' "$REPOS_TOML" | sed 's/.*name = "//;s/".*//')

while IFS= read -r name; do
  [ -z "$name" ] && continue

  # Skip framework/infra repos that aren't deployable bots
  case "$name" in
    bot_army_core|bot_army_runtime|bot_army_runtime_config|bot_army_infra|bot_army_schemas*|bot_army_integration_hub|bot_army_markdown_template)
      continue
      ;;
  esac

  # Find the bot directory (monorepo app or sibling repo)
  bot_dir=""
  if [ -d "${MONOREPO}/${name}" ]; then
    bot_dir="${MONOREPO}/${name}"
  elif [ -d "${BOTS_DIR}/${name}" ]; then
    bot_dir="${BOTS_DIR}/${name}"
  else
    echo "  ⚠ ${name}: directory not found, skipping" >&2
    continue
  fi

  mix_exs="${bot_dir}/mix.exs"
  if [ ! -f "$mix_exs" ]; then
    echo "  ⚠ ${name}: no mix.exs, skipping" >&2
    continue
  fi

  # Extract app name: "app: :bot_army_gtd" -> "bot_army_gtd"
  app=$(sed -n 's/.*app: :\([a-z_]*\).*/\1/p' "$mix_exs" | head -1)

  # Extract version: 'version: "0.7.102"' -> "0.7.102"
  version=$(sed -n 's/.*version: "\([0-9.]*\)".*/\1/p' "$mix_exs" | head -1)
  [ -z "$version" ] && version="0.0.0"

  # Extract release name from releases: [name: [...]]
  release_name=$(sed -n 's/.*releases: \[\([a-z_]*\):.*/\1/p' "$mix_exs" | head -1)
  if [ -z "$release_name" ]; then
    # Fallback: derive from app name (bot_army_gtd -> gtd_bot)
    short=$(echo "$name" | sed 's/^bot_army_//')
    release_name="${short}_bot"
  fi

  # Check for database deps
  needs_db="false"
  if grep -qE '\{:ecto_sql|\{:postgrex' "$mix_exs" 2>/dev/null; then
    needs_db="true"
  fi

  # Extract remote name from repos.toml
  remote=$(grep -A1 "name = \"${name}\"" "$REPOS_TOML" | sed -n 's/.*remote = "\([^"]*\)".*/\1/p' | head -1)

  # Detect category from repos.toml section comments
  category="domain"
  line_num=$(grep -n "name = \"${name}\"" "$REPOS_TOML" | head -1 | cut -d: -f1)
  if [ -n "$line_num" ]; then
    section=$(head -n "$line_num" "$REPOS_TOML" | grep '^#' | tail -1)
    case "$section" in
      *Core*|*framework*) category="core" ;;
      *Primary*) category="primary" ;;
      *Domain*) category="domain" ;;
      *Infrastructure*) category="infra" ;;
    esac
  fi

  # Detect required env vars by scanning config/runtime.exs
  env_vars="[]"
  runtime_exs="${bot_dir}/config/runtime.exs"
  if [ -f "$runtime_exs" ]; then
    # Extract System.get_env("VAR") calls, filter out standard ones
    vars=$(grep -o 'System\.get_env("[A-Z_]*"' "$runtime_exs" 2>/dev/null | \
      sed 's/System\.get_env("//;s/"//' | \
      grep -v '^DATABASE_\|^NATS_\|^MIX_ENV\|^PHX_\|^SECRET_KEY\|^BOT_ARMY_' | \
      sort -u || true)
    if [ -n "$vars" ]; then
      env_vars="["
      env_first=true
      while IFS= read -r var; do
        [ -z "$var" ] && continue
        if [ "$env_first" = true ]; then env_first=false; else env_vars+=","; fi

        secret="false"
        case "$var" in
          *KEY*|*SECRET*|*TOKEN*|*PASSWORD*) secret="true" ;;
        esac

        env_vars+="{\"key\":\"${var}\",\"secret\":${secret}}"
      done <<< "$vars"
      env_vars+="]"
    fi
  fi

  # Build JSON entry
  if [ "$first" = true ]; then first=false; else bots_json+=","; fi
  bots_json+="
  {
    \"name\": \"${name#bot_army_}\",
    \"app\": \"${app}\",
    \"release_name\": \"${release_name}\",
    \"repo\": \"${name}\",
    \"remote\": \"${remote}\",
    \"version\": \"${version}\",
    \"needs_db\": ${needs_db},
    \"category\": \"${category}\",
    \"env_vars\": ${env_vars}
  }"

  echo "  ✓ ${name} → ${release_name} v${version} (${category}, db=${needs_db})"

done <<< "$bot_names"

bots_json+="
]"

echo "$bots_json" > "$OUTPUT"
echo ""
echo "✓ Wrote $(echo "$bots_json" | grep -c '"name"') bots to ${OUTPUT}"
