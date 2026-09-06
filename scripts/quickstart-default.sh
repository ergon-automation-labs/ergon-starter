#!/bin/bash
# Headless quickstart: core bots + Ollama, no interactive prompts.
# For the interactive version, use `make quickstart` instead.
#
# Override host ports via env:
#   NATS_HOST_PORT=4222 POSTGRES_HOST_PORT=5432 ./scripts/quickstart-default.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

CATALOG="catalog/bots.json"
if [ ! -f "$CATALOG" ]; then
  echo "Error: $CATALOG not found — run 'make sync' first" >&2
  exit 1
fi

GIT_ORG="ergon-automation-labs"

# Docker registry — when set, pull pre-built images instead of building from source
REGISTRY="${REGISTRY:-}"

# P8 (2026-09-06, vagrant-test): some bots don't read the generic DATABASE_*
# env vars — they carry old-monorepo defaults that don't exist in Docker
# (e.g. job_scheduler dialed localhost:30003 and never read DATABASE_HOST).
# Steer them with their own config env names. Bots whose DEFAULT database
# name is used as-is (gtd→ergon_gtd, llm→ergon_llm, dispatcher→
# bot_army_dispatcher, skills→bot_army_skills_dev, synapse→ergon_synapse_dev)
# need no override — postgres-init.sql creates those names.
declare -A BOT_ENV_OVERRIDES=(
  [job_scheduler_bot]='    environment:\n      BOT_ARMY_JOB_DB_HOST: postgres\n      BOT_ARMY_JOB_DB_PORT: "5432"\n      BOT_ARMY_JOB_DB_NAME: ergon_job_scheduler'
  # internal_docs hand-rolls its env chain with a _BOT_ prefix segment and
  # hardcodes 127.0.0.1:30006 (operator's PgBouncer) — DATABASE_* never
  # reaches it. youtube_manager speaks a k8s dialect (DB_HOST/DB_PASS with
  # a postgres.default.svc.cluster.local default).
  [internal_docs_bot]='    environment:\n      BOT_ARMY_INTERNAL_DOCS_BOT_DB_HOST: postgres\n      BOT_ARMY_INTERNAL_DOCS_BOT_DB_PORT: "5432"'
  [youtube_manager_bot]='    environment:\n      DB_HOST: postgres\n      DB_PASS: postgres'
)

# Host ports — high defaults to avoid collisions with local services
NATS_HOST_PORT="${NATS_HOST_PORT:-54222}"
NATS_MONITOR_HOST_PORT="${NATS_MONITOR_HOST_PORT:-58222}"
POSTGRES_HOST_PORT="${POSTGRES_HOST_PORT:-55432}"
OLLAMA_HOST_PORT="${OLLAMA_HOST_PORT:-51434}"
MCP_HOST_PORT="${MCP_HOST_PORT:-39900}"

# LLM model — written to OLLAMA_MODEL_* in .env and pulled after the stack
# comes up. install.sh --model <name> sets MODEL_NAME; change later by editing
# .env and running 'make pull-model'.
# Default gemma4:e2b (P12 bench, 4 vCPU CPU-only: 13.8 tok/s think-off / 12.6
# think-on, 6.7 GB weights) — 2–3× faster than e4b (6.5/4.5) with half the
# RAM. Dense 8B models (llama3.1) time out on 4 vCPU.
MODEL_NAME="${MODEL_NAME:-gemma4:e2b}"

# Select bots: PACKS env (comma/space-separated pack names from
# catalog/packs.json — e.g. PACKS="core social_media") or the default
# core-category set. Unknown bot names inside a pack are skipped (e.g.
# packs.json's 'github' alias), library aliases resolve to their catalog
# names. Output: remote repo_name release_name bot_name needs_db
core_bots=$(PACKS="${PACKS:-}" python3 -c "
import json, os, sys
bots = json.load(open('$CATALOG'))
packs_env = os.environ.get('PACKS', '').strip()
if packs_env:
    pack_names = [p.strip() for p in packs_env.replace(',', ' ').split() if p.strip()]
    try:
        packs = json.load(open('catalog/packs.json'))
    except FileNotFoundError:
        print('ERROR: PACKS set but catalog/packs.json not found', file=sys.stderr); sys.exit(1)
    items = packs if isinstance(packs, list) else packs.get('packs', [])
    chosen = set()
    for p in items:
        if p.get('name') in pack_names:
            chosen.update(p.get('bots', []))
    if not chosen:
        print('ERROR: no bots found for packs: ' + packs_env, file=sys.stderr); sys.exit(1)
    for b in bots:
        if b['name'] in chosen:
            remote = b.get('remote', b['repo'])
            print(remote, b['repo'], b['release_name'], b['name'], str(b.get('needs_db', False)).lower())
else:
    for b in bots:
        if b['category'] == 'core':
            remote = b.get('remote', b['repo'])
            print(remote, b['repo'], b['release_name'], b['name'], str(b.get('needs_db', False)).lower())
")

if [ -n "$REGISTRY" ]; then
  echo "Using pre-built images from ${REGISTRY} (skipping source clone)..."
else
  echo "Cloning core bot repos..."
fi
mkdir -p repos
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

if [ -z "$REGISTRY" ]; then

# Helper: clone repo using gh auth when available, fallback to HTTPS
clone_repo() {
  local remote="$1"
  local dest="$2"
  if [ -d "$dest" ]; then
    # P4/P6 (2026-09-06, Vagrant fresh-user test): re-runs must pick up fixes
    # published after the first clone — ff-only refresh, non-fatal on failure.
    if git -C "$dest" pull --ff-only origin >/dev/null 2>&1; then
      echo "  ↻ $remote (exists, refreshed to $(git -C "$dest" log --oneline -1 2>/dev/null | head -1))"
    else
      echo "  ⚠ $remote (exists, ff-pull failed — keeping existing copy)" >&2
    fi
    return 0
  fi
  echo "  ⏳ $remote..."
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh repo clone "${GIT_ORG}/${remote}" "$dest" -- --depth 1 2>&1; then
      echo "  ✓ $remote"
      return 0
    fi
  fi
  if git clone --depth 1 "https://github.com/${GIT_ORG}/${remote}.git" "$dest" 2>&1; then
    echo "  ✓ $remote"
    return 0
  fi
  echo "  ✗ $remote (clone failed)" >&2
  return 1
}

  # Clone library repos (remote names differ from local dir names)
  declare -A lib_remotes=(
    ["bot_army_library_runtime"]="ergon-library-runtime"
    ["bot_army_library_core"]="ergon-library-core"
    ["bot_army_library_learning"]="ergon-library-learning"
  )
  for lib in "${!lib_remotes[@]}"; do
    remote="${lib_remotes[$lib]}"
    clone_repo "$remote" "repos/$lib" || exit 1
  done
fi

needs_db=false
bot_services=""

while IFS=' ' read -r remote repo release bot_name db_flag; do
  [ -z "$repo" ] && continue

  # Libraries are path deps — clone only, no docker-compose service
  if [[ "$repo" == bot_army_library_* ]]; then
    if [ -z "$REGISTRY" ]; then
      clone_repo "$remote" "repos/$repo" || exit 1
    fi
    continue
  fi

  # Clone source when building from source (no registry)
  if [ -z "$REGISTRY" ]; then
    clone_repo "$remote" "repos/$repo" || exit 1
  fi

  [ "$db_flag" = "true" ] && needs_db=true

  dep_block="      nats:\n        condition: service_started"
  if [ "$db_flag" = "true" ]; then
    dep_block="$dep_block\n      postgres:\n        condition: service_healthy"
  fi
  dep_block="$dep_block\n      ollama:\n        condition: service_started"

  if [ -n "$REGISTRY" ]; then
    bot_services+="
  ${release}:
    image: ${REGISTRY}/${release}:latest
    env_file: .env
$(echo -e "${BOT_ENV_OVERRIDES[$release]:-}")
    volumes:
      - ./data/logs/${bot_name}:/var/log/bot_army
    depends_on:
$(echo -e "$dep_block")
    restart: unless-stopped
"
  else
    bot_services+="
  ${release}:
    build:
      context: ./repos
      dockerfile: ../Dockerfile
      args:
        BOT_NAME: ${release}
        BOT_REPO: ${repo}
    env_file: .env
$(echo -e "${BOT_ENV_OVERRIDES[$release]:-}")
    volumes:
      - ./data/logs/${bot_name}:/var/log/bot_army
    depends_on:
$(echo -e "$dep_block")
    restart: unless-stopped
"
  fi
done <<< "$core_bots"

# P3 (2026-09-06, Vagrant fresh-user test): the runtime Dockerfile COPYs
# scripts/docker-entrypoint.sh from the ./repos build context, but no public
# bot repo carries it — stage the starter's copy so from-source builds don't
# fail on a missing file.
if [ -z "$REGISTRY" ]; then
  mkdir -p repos/scripts
  cp "$SCRIPT_DIR/docker-entrypoint.sh" repos/scripts/docker-entrypoint.sh
  echo "  ✓ staged repos/scripts/docker-entrypoint.sh"
fi

# Create data directories
mkdir -p data/logs data/para data/backups

# P8: stage the postgres init SQL (creates every core bot's database with
# the bot's own config-default name — some intentionally carry dev
# suffixes). Runs on first pgdata volume initialization.
mkdir -p postgres-init
cp "$SCRIPT_DIR/postgres-init.sql" postgres-init/01-create-databases.sql
echo "  ✓ staged postgres-init/01-create-databases.sql"

# P10 (phase 4): PACKS selections include bots outside the static init —
# append a CREATE DATABASE for every selected bot whose repo config names
# one (the same value the bot's runtime dials, so the list cannot drift).
# The catalog's needs_db flag is unreliable (None for all non-core bots),
# so discovery is config-driven. Deduped against the staged static file.
printf '\n-- dynamic: databases for PACKS-selected bots (from repo configs) --\n' >> postgres-init/01-create-databases.sql
CORE_BOTS_ROWS="$core_bots" python3 - <<'PYEOF' >> postgres-init/01-create-databases.sql
import os, re, pathlib
rows = os.environ.get('CORE_BOTS_ROWS', '')
known = pathlib.Path('postgres-init/01-create-databases.sql').read_text()
for row in rows.splitlines():
    parts = row.split()
    if len(parts) < 2:
        continue
    repo, bot_name = parts[1], parts[3] if len(parts) > 3 else parts[1]
    cfgdir = pathlib.Path('repos') / repo / 'config'
    if not cfgdir.is_dir():
        continue
    # Release-time dial: runtime.exs > prod.exs > config.exs > dev.exs.
    # test.exs is never the release dial (MIX_ENV=prod in the starter
    # Dockerfile) and is deliberately skipped.
    name = None
    for fname in ('runtime.exs', 'prod.exs', 'config.exs', 'dev.exs'):
        f = cfgdir / fname
        if not f.exists():
            continue
        text = f.read_text()
        # Stanza-ownership filter: a database: entry belongs to the nearest
        # preceding `config :` stanza; that stanza must name a module ending
        # in ".Repo" (BotArmyInternalDocs.Repo) — excludes satellite stores
        # like *.GraphRepo (postgres-age, different server) which would
        # otherwise win on file priority. Comment lines between the header
        # and the entry are fine (distance-free matching).
        def repo_backed(pos, txt):
            head = txt[:pos]
            starts = list(re.finditer(r'^[ \t]*config[ \t]+:', head, re.M))
            if not starts:
                return True  # no config stanza anywhere — conservative accept
            stanza_head = head[starts[-1].start():]
            first2 = '\n'.join(stanza_head.splitlines()[:2])
            return bool(re.search(r'[A-Za-z0-9_.]+\.Repo[ \t]*,', first2))
        # pass 1: line-anchored entries (incl. multi-line env chains)
        for m in re.finditer(r'^[ \t]*database:[ \t]*(.*)$', text, re.M):
            if not repo_backed(m.start(), text):
                continue
            chunk = m.group(1) + '\n'
            if not m.group(1).strip().endswith(','):
                for line in text[m.end():].splitlines()[:8]:
                    chunk += line + '\n'
                    if line.rstrip().endswith(','):
                        break
            lits = re.findall(r'"([^"]+)"', chunk)
            if lits and lits[-1]:
                name = lits[-1]
                break
        # pass 2: the library's own resolve() default is by definition a
        # release-time database name (RuntimeDbConfig.resolve("PREFIX",
        # database: "name", ...)) — no stanza check needed.
        if not name:
            m = re.search(
                r'RuntimeDbConfig\.resolve\((?:[^)]|\n)*?database:[ \t]*"([^"]+)"', text
            )
            if m:
                name = m.group(1)
        if name:
            break
    if not name:
        # No literal anywhere: the library RuntimeDbConfig's own fallback
        # for a Repo bot is the lowercase env prefix (bot_army_<name>);
        # create that so an unknown chain shape can't 404 at runtime.
        has_repo = any(
            'defmodule' in p.read_text() and re.search(r'defmodule [A-Za-z_.]+\.Repo', p.read_text())
            for p in (pathlib.Path('repos') / repo / 'lib').rglob('*.ex')
        ) if (pathlib.Path('repos') / repo / 'lib').is_dir() else False
        if has_repo:
            name = 'bot_army_' + bot_name
    if not name or name in known or any(name in r for r in out):
        continue
    out.append(name)
    print(f'CREATE DATABASE {name};')
PYEOF

echo ""
echo "Generating .env..."
cat > .env << ENVEOF
# Bot Army — generated by quickstart-default
# Edit this file to add API keys or change models.

# Host ports (connect from outside Docker)
STARTER_NATS_PORT=${NATS_HOST_PORT}
STARTER_NATS_MONITOR_PORT=${NATS_MONITOR_HOST_PORT}
STARTER_POSTGRES_PORT=${POSTGRES_HOST_PORT}
STARTER_OLLAMA_PORT=${OLLAMA_HOST_PORT}
STARTER_MCP_PORT=${MCP_HOST_PORT}

# PostgreSQL (internal — bots use these inside Docker)
POSTGRES_PASSWORD=postgres
DATABASE_HOST=postgres
DATABASE_PORT=5432
DATABASE_USER=postgres
DATABASE_PASSWORD=postgres

# NATS (internal)
NATS_HOST=nats
NATS_PORT=4222

# LLM — Ollama (local)
BOT_ARMY_LLM_PROVIDER_CHAIN=ollama
OLLAMA_BASE_URL=http://ollama:11434
OLLAMA_MODEL_LIGHT=${MODEL_NAME}
OLLAMA_MODEL_MEDIUM=${MODEL_NAME}
# llm_bot's OllamaHealthChecker speaks its own env dialect (OLLAMA_URL, not
# OLLAMA_BASE_URL) and probes with a tiny dedicated model (default gemma3:1b,
# non-thinking, cheap — pulled alongside MODEL_NAME).
OLLAMA_URL=http://ollama:11434
OLLAMA_PROBE_MODEL=gemma3:1b
# P10 fleet-test fixes: dispatcher's MultiServiceHealthMonitor probes the
# operator's air/mini topology (nothing answers in a single-VM fleet); the
# job_scheduler seed chain re-creates the operator's personal schedules in
# every fresh DB (their jobs embed real machine paths and can never succeed
# here). Empty value = idle monitor; unset = legacy behavior.
DISPATCHER_HEALTH_SERVICES=
JOB_SCHEDULER_DISABLE_SEEDS=1
ENVEOF
echo "  ✓ .env"

echo "Generating docker-compose.yml..."

# Build MCP service entry (registry vs build-from-source)
if [ -n "$REGISTRY" ]; then
  mcp_service="
  mcp:
    image: ${REGISTRY}/elixir_tools_mcp_bot:latest
    env_file: .env
    environment:
      MCP_PORT: \"39900\"
      MCP_TRANSPORT: \"http\"
      NATS_SERVERS: \"nats:4222\"
    ports:
      - \"${MCP_HOST_PORT}:39900\"
    depends_on:
      nats:
        condition: service_started
    restart: unless-stopped"
else
  mcp_service="
  mcp:
    build:
      context: ./repos
      dockerfile: ../Dockerfile
      args:
        BOT_NAME: elixir_tools_mcp_bot
        BOT_REPO: bot_army_elixir_tools_mcp
    env_file: .env
    environment:
      MCP_PORT: \"39900\"
      MCP_TRANSPORT: \"http\"
      NATS_SERVERS: \"nats:4222\"
    ports:
      - \"${MCP_HOST_PORT}:39900\"
    depends_on:
      nats:
        condition: service_started
    restart: unless-stopped"
fi

cat > docker-compose.yml << COMPEOF
# Bot Army — generated by quickstart-default
# Rebuild: docker compose up -d --build
#
# Host ports: NATS=${NATS_HOST_PORT}  Monitor=${NATS_MONITOR_HOST_PORT}  Postgres=${POSTGRES_HOST_PORT}  Ollama=${OLLAMA_HOST_PORT}  MCP=${MCP_HOST_PORT}
# TUI connect: nats://localhost:${NATS_HOST_PORT}
# Claude Desktop MCP: http://localhost:${MCP_HOST_PORT}/mcp

services:
  nats:
    image: nats:2.10-alpine
    ports:
      - "${NATS_HOST_PORT}:4222"
      - "${NATS_MONITOR_HOST_PORT}:8222"
    command: ["--jetstream", "--http_port", "8222"]
    restart: unless-stopped

  postgres:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
    ports:
      - "${POSTGRES_HOST_PORT}:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./postgres-init:/docker-entrypoint-initdb.d:ro
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  ollama:
    image: ollama/ollama
    ports:
      - "${OLLAMA_HOST_PORT}:11434"
    volumes:
      - ollama_data:/root/.ollama
    restart: unless-stopped
${mcp_service}
${bot_services}
volumes:
  pgdata:
  ollama_data:
COMPEOF
echo "  ✓ docker-compose.yml"

bot_count=$(echo "$core_bots" | grep -c '.' || true)
echo ""
echo "✓ Configured ${bot_count} core bots + NATS + PostgreSQL + Ollama"
echo "  LLM model: ${MODEL_NAME} (OLLAMA_MODEL_* in .env — change + 'make pull-model' to switch)"
echo ""
echo "Port map:"
echo "  NATS:      localhost:${NATS_HOST_PORT}  (internal 4222)"
echo "  Monitor:   localhost:${NATS_MONITOR_HOST_PORT}  (internal 8222)"
echo "  Postgres:  localhost:${POSTGRES_HOST_PORT}  (internal 5432)"
echo "  Ollama:    localhost:${OLLAMA_HOST_PORT}  (internal 11434)"
echo "  MCP:       localhost:${MCP_HOST_PORT}  (internal 39900)"
echo ""
echo "Data directories:"
echo "  ./data/logs/     Bot logs (mounted from containers)"
echo "  ./data/para/     PARA output (mount to para_bot)"
echo "  ./data/backups/  DB backups (mount to backup_bot)"
echo ""

# Install host-side tools (graphify + ripgrep)
if [ -z "$REGISTRY" ]; then
  echo "Installing host-side tools..."
  "$SCRIPT_DIR/install-tools.sh" || echo "  Warning: some tools failed to install (non-fatal)"
  echo ""
fi

if [ -n "$REGISTRY" ]; then
  echo "To start (pulling images from ${REGISTRY}):"
  echo "  docker compose up -d"
else
  echo "To build and start:"
  echo "  DOCKER_BUILDKIT=1 docker compose up -d --build"
fi
echo ""
echo "After services are up:"
echo "  1. Run 'make setup-tools' to install graphify + ripgrep (if skipped above)"
echo "  2. Run 'make graphify-refresh' to generate knowledge graphs (requires LLM bot running)"
