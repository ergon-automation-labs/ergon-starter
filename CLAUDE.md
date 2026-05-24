# bot-army-starter

One-line installer for Bot Army ecosystem. Downloads bot repos, generates docker-compose.yml, starts services.

## Purpose

Distribute Bot Army as a portable installation: interactive wizard → docker-compose up → working fleet with NATS, PostgreSQL, optional Ollama, and 20+ bots.

Targets: developers wanting to run the full ecosystem locally, teams onboarding new members, teaching/demo environments.

## Tech Stack

- **Language**: Go (CLI + TUI, no system dependencies)
- **UI**: tview (TUI library, not bubbletea — see Migration notes below)
- **Distribution**: Docker multi-stage + docker-compose
- **Shell**: Bash (install.sh, scripts/)
- **Data**: YAML/JSON (catalog, config)

## Project Structure

```
bot-army-starter/
├── cmd/
│   └── bot-army/main.go           # CLI entry point (init, add, status)
├── internal/
│   └── wizard/
│       ├── init.go                # First-run setup (TUI)
│       ├── selector.go            # Multi-select bot/provider picker (TUI)
│       ├── add.go                 # Add bot to existing install
│       ├── generate.go            # Generate docker-compose.yml + .env
│       └── registry.go            # Load bot catalog
├── catalog/
│   ├── bots.json                  # All 40 bots + metadata (auto-generated)
│   └── packs.json                 # Preset groups (core, full, teaching)
├── scripts/
│   ├── sync-catalog.sh            # Scan monorepo → catalog
│   ├── quickstart-default.sh      # Headless setup
│   └── entrypoint.sh              # Migration-on-boot (optional)
├── Dockerfile                     # Multi-stage for any bot
├── Makefile                       # All operations
├── install.sh                     # curl | bash bootstrap
└── README.md                      # User docs
```

## Build & Run

```bash
# Build the CLI
make build

# Interactive wizard (bot selection + provider config)
./bot-army init

# Start services
docker compose up -d

# View status
make status

# Add a bot to running system
make add BOT=fitness

# Follow logs
make logs
```

## Testing

```bash
# Validate catalog against monorepo
make validate-catalog

# Test wizard flow (dry-run)
make test-wizard
```

## Architecture

1. **Wizard Phase** (interactive TUI)
   - Prompt user for desired bots
   - Choose LLM providers (Ollama, Anthropic, OpenAI, OpenRouter)
   - Generate docker-compose.yml + .env

2. **Docker Phase**
   - Multi-stage Dockerfile builds any bot from source
   - Shared base layers (Erlang, Go) cached
   - All bots share NATS, PostgreSQL, Ollama (optional)

3. **Dashboard Phase** (post-wizard, needs implementation)
   - TUI showing:
     - Bot fleet status (running, healthy, log tails)
     - NATS subject browser
     - PostgreSQL query interface
     - System health (CPU, RAM, disk)
   - Replace wizard UI once init complete

## Current State

- ✅ Wizard: bot selection, provider config
- ✅ Catalog: scans monorepo, JSON registry
- ✅ Docker: multi-stage builds, compose generation
- 🚧 **TUI Migration**: bubbletea → tview (IN PROGRESS)
- 🚧 **Dashboard**: NATS/SQL/logs screens (TODO)
- 🚧 **Volume mounts**: persistent config (TODO)

## TUI Migration (Next)

### Why: Switch from bubbletea → tview

- **tview**: Structured layout (panels, tabs, borders), stable API, used in GTD TUI
- **bubbletea**: Great for simple CLIs, but overkill for dashboard work
- **Goal**: Reuse GTD TUI patterns, add persistent state management

### What to migrate

1. **Selector** (`internal/wizard/selector.go`) — Multi-select bots
2. **Init** (`internal/wizard/init.go`) — Provider config flow
3. Both currently use bubbletea, will move to tview layouts

### Dashboard Screens (Post-wizard)

Once init completes, show persistent TUI with:

1. **Fleet Tab** — `gtd status` equivalent
   - List running bots
   - Health indicators (responding, log tail, version)
   - Filter by tag (handlers, stores, core)

2. **NATS Tab** — Subject explorer
   - List all subjects
   - Pub/sub smoke test
   - Message browser

3. **SQL Tab** — PostgreSQL query interface
   - Quick queries (top tasks, bot errors)
   - Pre-built snippets

4. **Logs Tab** — Aggregate bot logs
   - Search + filter
   - Live tail

5. **System Tab** — Resource usage
   - CPU, RAM, disk per container
   - Docker stats

### UI Standards

See **CLAUDE.md** in `~/code/elixir_bots` for surfaces UI rules. Key:
- Panel titles include key hints
- Always show context-sensitive header (what keys work now?)
- Empty states guide the user
- Status bar reflects current state

## How to Work

- **Be direct** — Implement screen-by-screen, test in docker compose
- **No comments** — Code is self-documenting
- **Makefile-first** — Add targets for new operational tasks (e.g., `make test-dashboard`)
- **Commit per feature** — Wizard → Dashboard → Volume Mounts as separate PRs
- **Test in docker** — Always run locally with `make quickstart` before pushing

## Dependencies

```
go get -u github.com/rivo/tview
go get -u github.com/nats-io/nats.go
go get -u github.com/lib/pq
```

## References

- **GTD TUI**: `~/code/surfaces/golang_tui/gtd-tui/` — copy tview patterns from here
- **Bot Catalog**: `~/code/elixir_bots/config/repos.toml` — source of truth
- **NATS**: primary 4222, dev 4223, test 4224
- **PostgreSQL**: `localhost:5432` (or 35432 port-forward on host)
