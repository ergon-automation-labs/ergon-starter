# Bot Army Starter

Get the Bot Army ecosystem running on any machine with Docker.

## One-Click Install

**Interactive setup** with TUI wizard:

```bash
curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/ergon-starter/main/install.sh | bash
```

This launches an interactive 6-step wizard:
1. **Select a Starter Pack** — Choose from Primary (8 core bots), Background (10 domain bots), Infrastructure (10 support services), or Custom
2. **Select Bots** — Multi-select with pack labels showing which bots belong to which pack
3. **Configure Ports** — NATS (default 54222), Monitor (58222), PostgreSQL (55432), Ollama (51434)
4. **Select LLM Providers** — Ollama, Anthropic, OpenAI, OpenRouter (pick one or more)
5. **Configure Environment Variables** — API keys, model names, custom settings per provider
6. **Review Configuration** — Summary + template guide for building custom bots

**Configuration persists** across restarts via `.bot-army.json`, so subsequent runs can skip the wizard.

For headless setup (core bots + Ollama, no prompts):
```bash
curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/ergon-starter/main/install.sh | bash -s -- --default
```

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (includes Docker Compose v2)
- Git
- ~4 GB RAM for builds

## Manual Setup

If you prefer to clone first:

```bash
git clone https://github.com/ergon-automation-labs/ergon-starter.git
cd ergon-starter

# Interactive setup (builds CLI, runs wizard)
make quickstart

# Or headless setup (core bots + Ollama, no prompts)
make quickstart-default

# Start dashboard after wizard completes
# (dashboard auto-launches with docker compose logs)
```

The wizard saves your configuration to `.bot-army.json` for future restarts. To reuse it:
```bash
# Run again — will offer to reuse saved config
make quickstart
```

## Commands

| Command | What it does |
|---------|-------------|
| `make quickstart` | Interactive 6-step wizard → builds CLI → clones bots → starts dashboard |
| `make quickstart-default` | Headless setup: core bots + Ollama (no prompts) |
| `make build` | Build bot-army CLI only (for development) |
| `make up` | Start docker compose services |
| `make down` | Stop services |
| `make logs` | Follow all service logs (or `make logs BOT=gtd`) |
| `make ps` | Show running containers |
| `make add BOT=name` | Add another bot to docker-compose.yml |
| `make clean` | Remove generated files (.env, docker-compose.yml) |

**Reusing configuration:**
```bash
# Wizard saves config to .bot-army.json
# Run again and choose to reuse it:
make quickstart

# Manually remove config to force re-wizard:
rm .bot-army.json
make quickstart
```

## Custom Bots

Add your own bots to the fleet without modifying the wizard. Create a `custom-bots.json`:

```json
{
  "custom_bots": [
    {
      "name": "my-bot",
      "repo": "https://github.com/user/my-bot.git",
      "release_name": "my_bot_bot",
      "env_vars": {
        "API_KEY": "your-key",
        "DEBUG": "false"
      }
    }
  ],
  "custom_mounts": [
    {
      "source": "/host/data",
      "destination": "/app/data"
    }
  ]
}
```

Then run:
```bash
make quickstart --custom-bots custom-bots.json
```

**Key fields:**
- `name` — Bot directory name (e.g., `bot_army_mybot`)
- `repo` — GitHub URL or local path (both supported)
- `release_name` — Docker container name (e.g., `my_bot_bot`)
- `env_vars` — Custom environment variables for this bot
- `custom_mounts` — Host paths to mount into all services

See `custom-bots.example.json` for a template.

## Architecture

```
┌─────────────────────────────────────────────┐
│                  Docker                      │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │   NATS   │  │ Postgres │  │  Ollama   │  │
│  │  :4222   │  │  :5432   │  │  :11434   │  │
│  └────┬─────┘  └────┬─────┘  └─────┬─────┘  │
│       │              │              │         │
│  ┌────┴──────────────┴──────────────┴─────┐  │
│  │              Bot Fleet                 │  │
│  │  gtd · bridge · llm · synapse · ...    │  │
│  └────────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

All bots communicate over NATS. The LLM bot proxies AI requests through your chosen provider(s) with automatic fallback.

## LLM Providers

The wizard lets you pick any combination:

| Provider | API key needed? | Notes |
|----------|----------------|-------|
| Ollama | No | Runs locally, can self-host in Docker |
| Anthropic | Yes | Claude models |
| OpenAI | Yes | GPT models |
| OpenRouter | Yes | Multi-model gateway |

The LLM bot routes requests through your provider chain based on complexity (light/medium/heavy) with health-aware failover.

## Adding bots after initial setup

```bash
# List available bots
make add BOT=help

# Add one to docker-compose.yml
make add BOT=fitness

# Rebuild and start
docker compose up -d --build fitness_bot
```

To add bots **before initial setup**, run the wizard again:
```bash
rm .bot-army.json
make quickstart
```

## Updating

```bash
# Pull latest bot code
make pull-repos

# Rebuild
make rebuild

# Restart
make up
```

## Project structure

```
bot-army-starter/
├── install.sh              # curl | bash bootstrap
├── Makefile                # All operations (quickstart, logs, add, etc.)
├── Dockerfile              # Shared multi-stage build for any bot
├── Dockerfile.build        # Go build environment for CLI
├── cmd/bot-army/
│   └── main.go             # CLI entry point
├── internal/
│   ├── wizard/             # TUI wizard (6-step flow)
│   │   ├── tui.go          # Interactive steps
│   │   ├── registry.go     # Bot/pack catalog loading
│   │   ├── init.go         # Config save/load + setup orchestration
│   │   └── generate.go     # .env and docker-compose.yml generation
│   └── dashboard/          # Live monitoring (Fleet, Logs, NATS, System tabs)
│       ├── dashboard.go    # Main UI
│       ├── fleet.go        # Fleet status tab
│       ├── logs.go         # Live log streaming
│       ├── nats_tab.go     # NATS request/reply tester
│       └── system.go       # Docker stats tab
├── catalog/
│   ├── bots.json           # Auto-generated bot registry (40 bots)
│   └── packs.json          # Preset packs (Primary, Background, Infra)
├── scripts/
│   ├── sync-catalog.sh     # Scans monorepo → catalog
│   └── quickstart-default.sh
├── repos/                  # Cloned bot source code (gitignored)
├── docker-compose.yml      # Generated by wizard (gitignored)
├── .env                    # Generated by wizard (gitignored)
└── .bot-army.json          # Saved config (gitignored)
```
