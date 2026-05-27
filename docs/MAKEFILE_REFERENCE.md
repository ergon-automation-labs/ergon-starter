# Makefile Reference

Complete guide to all `make` commands in Bot Army Starter.

## Quick Lookup

**Just getting started?**
```bash
make quickstart              # Full setup wizard
make quick-start            # 5 demos to learn the system
make health-check           # Verify everything works
```

**Need help?**
```bash
make help                   # Show all targets with descriptions
make help-architecture      # Why this design?
make help-bridge-api        # Claude integration endpoints
make help-create-bot        # Build your own bot
make help-debugging         # Troubleshoot problems
make help-testing           # Test subjects and bots
make help-volumes           # Configure storage
make help-troubleshoot      # FAQ and common fixes
make help-environment       # All env vars explained
make help-makefile          # This guide
```

**Running services?**
```bash
make up                     # Start all services
make down                   # Stop all services
make ps                     # Show running services
make logs                   # Follow all logs
make logs BOT=gtd           # Follow one bot's logs
make dashboard              # Launch TUI dashboard
make health-check           # Verify health
```

**Managing bots?**
```bash
make add BOT=fitness        # Add a catalog bot
make add-local BOT_PATH=... # Add your custom bot
make status                 # Show configured services
```

**Database operations?**
```bash
make migrate                # Run all migrations
make migrate BOT=gtd        # Migrate one bot
make rollback               # Rollback all (1 step)
make rollback BOT=gtd STEPS=2  # Rollback specific bot
make migrate-status         # Check migration status
```

**Development?**
```bash
make build                  # Build CLI only
make build-native           # Build native binary (run dashboard locally)
make rebuild                # Rebuild all images (no cache)
make pull-repos             # Pull latest bot code
```

**Cleanup?**
```bash
make clean                  # Remove generated files (keep repos)
make nuke                   # Remove everything including repos
make disk-check             # Show disk usage
```

## Complete Reference

### Setup & Onboarding

#### quickstart
```bash
make quickstart
```
**Does:** Full interactive setup wizard (6 steps) → selects bots/LLMs → builds → starts everything

**Time:** ~5 minutes (first run can be longer for builds)

**Result:** Docker compose running with your selected bots, `.env` and `docker-compose.yml` created

**Next:** `make quick-start` or `make health-check`

#### quickstart-default
```bash
make quickstart-default
```
**Does:** Headless setup with defaults (core bots + Ollama, no wizard)

**When:** CI/CD, scripting, no user interaction needed

**Result:** Same as quickstart but skips wizard prompts

#### quick-start
```bash
make quick-start
```
**Does:** Show 5 practical demos (create task, ask Claude, monitor health)

**Time:** ~20 minutes

**Demos:**
1. Health check
2. Create GTD task
3. Ask Claude a question
4. Understand PARA
5. Monitor bots

#### help
```bash
make help
```
**Does:** Show all available targets with one-line descriptions

**Output:** 50+ targets listed alphabetically

#### help-architecture
```bash
make help-architecture
```
**Does:** Show architectural overview (why NATS? System diagrams? Data flow)

**Topics:**
- Design rationale
- System overview (NATS, PostgreSQL, PARA)
- Core concepts (bots, subjects, messaging)
- Data flow examples
- When to use Bot Army
- Scaling patterns

#### help-bridge-api
```bash
make help-bridge-api
```
**Does:** Show complete Bridge API reference (all subjects, examples, error handling)

**Includes:**
- Task management (create, list, get, update, delete)
- Projects
- Internal documentation search
- Knowledge graph queries
- System health endpoints
- Testing examples
- Error codes
- Rate limiting
- Timeouts

#### help-create-bot
```bash
make help-create-bot
```
**Does:** Step-by-step guide to create a custom bot from template

**Covers:**
- Bot structure (handlers, schemas, stores)
- NATS integration
- Subject naming conventions
- Database setup
- Testing
- Adding to fleet

#### help-debugging
```bash
make help-debugging
```
**Does:** Troubleshooting flowchart and step-by-step debugging

**Covers:**
- Diagnostic flowchart
- Docker services check
- NATS connectivity
- Bot logs analysis
- Database issues
- Claude integration issues
- Performance debugging
- Advanced troubleshooting

#### help-testing
```bash
make help-testing
```
**Does:** How to test Bot Army subjects and integrations

**Covers:**
- NATS CLI testing patterns
- Testing subjects (request/reply, pub/sub)
- Load testing
- Error case testing
- Bridge testing
- Performance testing
- Test automation

#### help-volumes
```bash
make help-volumes
```
**Does:** Configure storage volumes (PARA, internal docs, persistent data)

**Covers:**
- Default locations
- Custom paths
- PARA filesystem structure
- Internal docs indexing
- Backup strategies
- Troubleshooting

#### help-troubleshoot
```bash
make help-troubleshoot
```
**Does:** FAQ and common issues with solutions

**Topics:**
- Dashboard issues
- Bot crashes
- Database problems
- Claude integration
- Performance
- Port conflicts

#### health-check
```bash
make health-check
```
**Does:** Verify entire system is healthy

**Checks:**
- Docker is running
- NATS is responding
- PostgreSQL is accepting connections
- At least one bot is running
- Storage volumes exist

**Output:**
```
✓ Docker is running
✓ NATS is responding (6 clients)
✓ PostgreSQL is listening
✓ 4 bots running (gtd, bridge, synapse, llm)
✓ Data volumes OK
```

#### help-environment
```bash
make help-environment
```
**Does:** Show all environment variables and what they control

**Covers:**
- NATS ports and clustering
- Database credentials
- LLM provider keys
- Storage locations
- Logging levels
- Custom bot settings

#### claude-integrate
```bash
make claude-integrate
```
**Does:** Show Claude Desktop + Claude Code integration guide

**Result:** Opens docs/CLAUDE_INTEGRATION.md with setup instructions

### Running Services

#### up
```bash
make up
```
**Does:** Start all services using docker-compose (with BuildKit)

**Builds:** Only rebuilds images if needed

**Result:** All containers from docker-compose.yml running

**Equivalent:** `docker compose up -d --build`

#### down
```bash
make down
```
**Does:** Stop all services without removing volumes

**Preserves:** All data in PostgreSQL, PARA, logs

**Equivalent:** `docker compose down`

#### logs
```bash
make logs
make logs BOT=gtd
make logs BOT=gtd --since 5m
```
**Does:** Follow service logs in real-time

**With BOT=:** Show only one bot's logs

**Common options:**
- `--since 5m` — Last 5 minutes
- `--tail 50` — Last 50 lines
- `-f` — Follow (default)

#### ps
```bash
make ps
```
**Does:** Show status of all running containers

**Output:**
```
NAME              IMAGE           STATUS           PORTS
nats              nats:latest     Up 5 minutes     0.0.0.0:4222->4222/tcp
postgres          postgres:14     Up 5 minutes     0.0.0.0:5432->5432/tcp
gtd_bot           gtd_bot:latest  Up 3 minutes
bridge_bot        bridge_bot:latest Up 3 minutes
```

#### dashboard
```bash
make dashboard
```
**Does:** Launch interactive TUI dashboard

**Requires:** Native binary (builds automatically)

**Tabs:**
1. Fleet — Bot status and health
2. Logs — Real-time log streaming
3. NATS — Request/reply tester
4. System — Docker stats (CPU, memory)

**Controls:** Arrow keys to navigate, `q` to quit

#### rebuild
```bash
make rebuild
```
**Does:** Force rebuild all images from scratch (no Docker cache)

**When:** Cache might be stale, or you changed Dockerfile

**Time:** 5-10 minutes

#### pull-repos
```bash
make pull-repos
```
**Does:** Update all cloned bot repositories to latest code

**When:** Bot developers pushed new code to GitHub

**What it does:**
- For each bot in `repos/`, run `git pull --ff-only`
- Won't force-pull if you have uncommitted changes

#### status
```bash
make status
```
**Does:** Show configured services (from docker-compose.yml)

**Output:** Services list, images, ports

### Managing Bots

#### add
```bash
make add BOT=fitness
make add BOT=help     # Shows available bots
```
**Does:** Add a bot from the catalog to docker-compose.yml

**When:** You want to add a pre-built bot (not creating custom)

**Process:**
1. Updates docker-compose.yml
2. Rebuilds only that service
3. Starts it

#### add-local
```bash
make add-local BOT_PATH=/Users/abby/code/bot_army_mybot
```
**Does:** Add a locally-created bot to docker-compose.yml

**Validates:** Bot structure, detects database usage, configures volumes

**When:** After creating a bot with `make help-create-bot`

### Database Operations

#### migrate
```bash
make migrate
make migrate BOT=gtd
```
**Does:** Run Ecto migrations to set up databases

**Without BOT=:** Migrates all bots with databases

**With BOT=:** Migrate only that bot

**Result:**
```
Running migrations for all bots...
→ Migrating gtd_bot...
✓ Migrations complete
```

#### rollback
```bash
make rollback
make rollback BOT=gtd STEPS=2
```
**Does:** Rollback migrations (undo recent changes)

**STEPS=:** How many migrations to undo (default 1)

**When:** Migration failed, need to revert

#### migrate-status
```bash
make migrate-status
```
**Does:** Show migration status for each bot

**Output:** Latest applied migration version per bot

### Building & Development

#### build
```bash
make build
```
**Does:** Build the bot-army CLI binary in Docker

**Result:** Creates `./bot-army` executable

**Runs in:** Docker (no Go required on host)

#### build-native
```bash
make build-native
```
**Does:** Build native binary for your OS (macOS/Linux)

**Use case:** Run dashboard locally without Docker

**Result:** Creates `./bot-army-native`

#### sync
```bash
make sync
make sync CHANNEL=latest
```
**Does:** Sync bot catalog from GitHub (updates catalog/bots.json)

**CHANNEL:** stable (default), latest, or nightly

**When:** New bots added to bot registry

#### init
```bash
make init
```
**Does:** Run the interactive setup wizard

**Same as:** `make quickstart` (only the wizard part)

#### setup-tools
```bash
make setup-tools
```
**Does:** Install host-side tools (graphify, ripgrep, etc.)

**When:** Running analysis tools that need local binaries

### Release Management

#### release-check
```bash
make release-check
```
**Does:** Pre-flight checks before release (no uncommitted changes, build succeeds)

**Output:**
```
✓ Working tree clean
✓ Build successful
```

#### release-test
```bash
make release-test
```
**Does:** Test installer script in temporary directory

**When:** Making changes to install.sh before publishing

#### release-create
```bash
make release-create VERSION=v0.2.0
```
**Does:** Create a GitHub release tag and push it

**Requires:** VERSION parameter, clean working tree, successful build

**Result:** Tag created on GitHub, asset downloads available

#### release-list
```bash
make release-list
```
**Does:** Show last 10 releases (tags)

**Output:**
```
v0.1.5
v0.1.4
v0.1.3
...
```

#### release-latest
```bash
make release-latest
```
**Does:** Show the most recent release version

**Output:** Single version string (e.g., `v0.1.5`)

### Cleanup

#### clean
```bash
make clean
```
**Does:** Remove generated files (`.env`, `docker-compose.yml`, `./bot-army`)

**Keeps:** `repos/` directory (all cloned bot code)

**When:** Starting fresh wizard or resetting config

#### nuke
```bash
make nuke
```
**Does:** Remove everything (generated files, cloned repos, containers)

**⚠️ Warning:** This is destructive! Data in volumes is preserved.

**When:** Complete reset to clean state

#### disk-check
```bash
make disk-check
```
**Does:** Show disk usage summary

**Output:**
```
Docker:
  Images: 2.3GB
  Containers: 1.5GB
  Volumes: 250MB

Project:
  repos/: 850MB
  data/: 120MB
```

## Makefile Variables

You can pass variables to customize behavior:

```bash
# NATS port (default 4222)
make up NATS_PORT=4223

# PostgreSQL port (default 5432)
make up PG_PORT=5433

# Build parallelism (default 3, less OOM on low-memory systems)
make up COMPOSE_BUILD_PARALLEL=2

# Channel for bot registry (stable, latest, nightly)
make sync CHANNEL=latest

# Specific bot to operate on
make logs BOT=gtd
make migrate BOT=gtd

# Rollback steps
make rollback STEPS=2
```

## Common Workflows

### First Time Setup
```bash
make quickstart           # Interactive wizard
make health-check         # Verify
make quick-start          # Learn the system
```

### Daily Development
```bash
make up                   # Start services
make logs -f              # Watch output
make health-check         # Verify health
# Make changes to bots...
make rebuild              # Rebuild images
make restart gtd_bot      # Restart one bot
```

### Adding a Custom Bot
```bash
# After creating bot_army_mybot...
make add-local BOT_PATH=/path/to/bot_army_mybot
make ps                   # Verify it's running
make logs BOT=mybot       # Check logs
```

### Database Management
```bash
make migrate              # Apply all pending migrations
make migrate-status       # Check status
# If something fails:
make rollback BOT=gtd STEPS=1  # Undo last migration
make migrate BOT=gtd           # Try again
```

### Troubleshooting
```bash
make health-check         # Quick diagnostic
make help-debugging       # Read guide
make logs                 # See errors
docker compose ps         # Check containers
make dashboard            # Watch in real-time
```

## Getting Help

- **See all targets:** `make help`
- **Understand the design:** `make help-architecture`
- **Create a bot:** `make help-create-bot`
- **Test subjects:** `make help-testing`
- **Debug issues:** `make help-debugging`
- **Troubleshoot:** `make help-troubleshoot`
- **Configure storage:** `make help-volumes`
- **Use Bridge API:** `make help-bridge-api`
- **Check env vars:** `make help-environment`

## Tips

- **Don't memorize.** Use `make help` to discover targets.
- **Read the guides.** Each `make help-*` target opens a detailed guide.
- **Check logs first.** When something fails, `make logs` usually shows why.
- **Use `make ps`** before `make up` to see what's already running.
- **Increase timeout** for slow networks: `timeout 10 nats request ...`

## Next Steps

- **Learn the design:** `make help-architecture`
- **Create your first bot:** `make help-create-bot`
- **Test the system:** `make help-testing`
- **Integrate Claude:** `make claude-integrate`
