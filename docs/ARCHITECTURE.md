# Bot Army Architecture

## Why This Design?

Bot Army is built on three core principles:

1. **Decoupled services** — Each bot is independent, with no shared code or tight coupling
2. **Async messaging** — All communication flows through NATS pub/sub for true scalability
3. **Persistent state** — PostgreSQL stores long-lived data; bots are stateless and replaceable

This design lets you:
- Add/remove bots without restarting others
- Scale individual bots based on load
- Build complex workflows from simple, single-purpose bots
- Test bots in isolation with mock NATS

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Your Machine (Docker)                   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                    NATS (Message Bus)                 │  │
│  │                  localhost:4222 (prod)               │  │
│  │                  localhost:4223 (dev)                │  │
│  └──────────────────────────────────────────────────────┘  │
│           ▲              ▲              ▲              ▲    │
│           │              │              │              │    │
│  ┌────────┴──┐  ┌────────┴──┐  ┌───────┴───┐  ┌──────┴──┐ │
│  │    GTD    │  │  Claude   │  │  Synapse  │  │  Custom │ │
│  │    Bot    │  │   Bridge  │  │    Bot    │  │   Bots  │ │
│  └────┬──────┘  └────┬──────┘  └───────┬───┘  └──────┬──┘ │
│       │              │                 │              │    │
│  ┌────┴──────────────┴─────────────────┴──────────────┘    │
│  │           PostgreSQL (Persistent State)                 │
│  │              ~/data/postgres/                           │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              PARA (Knowledge Base)                   │  │
│  │  Projects / Areas / Resources / Archive / Inbox      │  │
│  │              ~/data/para/                            │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Core Concepts

### NATS (Message Bus)

NATS is a lightweight pub/sub system that:
- Delivers messages between bots instantly
- Supports request/reply (RPC-style)
- Handles subscribers joining/leaving without disruption
- Routes based on subject names (like file paths)

**Example:** GTD bot listens on `gtd.task.create`. When you send a request to that subject, GTD bot receives it, processes, and replies.

```bash
# Send a request
nats request gtd.task.create '{"name":"My Task"}' --timeout 3s

# GTD bot:
# 1. Receives request
# 2. Validates input
# 3. Creates task in PostgreSQL
# 4. Replies with task_id + metadata
```

### Subjects (Message Topics)

Subjects follow a naming convention: `service.domain.action`

```
gtd.task.create          Create a task
gtd.task.list            List all tasks
gtd.task.update          Update a task
bridge.task.list         Claude's access to tasks (façade)
system.health            Bot health heartbeats
synapse.discord.send     Send message to Discord
```

### Bots (Workers)

Each bot:
1. **Subscribes** to subjects (listens for requests)
2. **Processes** messages (validates, transforms, stores)
3. **Replies** via embedded reply subject (RPC response)
4. **Publishes events** (tells others what happened)
5. **Reports health** (heartbeat every 30 minutes)

**Example GTD bot flow:**

```elixir
# In lib/bot_army_gtd/nats/consumer.ex:

def handle_request("gtd.task.create", req) do
  # 1. Validate input
  with {:ok, attrs} <- validate_task_create(req) do
    # 2. Persist to database
    case GTD.Repo.insert(Task.changeset(%Task{}, attrs)) do
      {:ok, task} ->
        # 3. Reply success + publish event
        {:ok, %{"task_id" => task.id, "status" => "created"}}
      {:error, reason} ->
        {:error, "Creation failed: #{reason}"}
    end
  end
end
```

### PostgreSQL (Persistent Storage)

Each bot gets its own database schema. Bot Army uses Ecto (Elixir's ORM) for:
- Type-safe schemas
- Migrations
- Query building

**Example schema:**

```elixir
defmodule BotArmyGtd.Schemas.Task do
  use Ecto.Schema

  schema "tasks" do
    field :name, :string
    field :description, :string
    field :status, :string       # pending, in_progress, done
    field :due_date, :date
    timestamps()
  end
end
```

When you run `make migrate`, it creates tables and applies schema changes.

### PARA (Personal Knowledge Base)

PARA is a filesystem-based system:

```
~/data/para/
├── inbox/           Quick captures, unsorted
├── projects/        Active work with deadlines
├── areas/           Ongoing responsibilities
├── resources/       Reference material
└── archive/         Completed items
```

Bots can read/write here (PARA is just files). Claude can query them. You own your data—it's not locked in a database.

## Data Flow Examples

### Example 1: Creating a Task from Claude

```
Claude (Desktop)
    │
    └─→ bridge.task.create (NATS request)
            │
            └─→ Claude Bridge bot receives
                    │
                    └─→ Forwards to gtd.task.create
                            │
                            └─→ GTD bot creates in DB
                                    │
                                    └─→ Replies with task_id
                                            │
                                            └─→ Bridge returns to Claude
                                                    │
                                                    └─→ Claude shows success
```

### Example 2: Synapse Publishes Event to Discord

```
GTD bot creates task
    │
    └─→ Publishes gtd.events.task.created
            │
            └─→ Synapse bot subscribed to gtd.events.*
                    │
                    └─→ Synapse asks: "Is this Discord-relevant?"
                            │
                            └─→ If yes: Publishes to synapse.discord.send
                                    │
                                    └─→ Surface_Discord bot relays to Discord
```

### Example 3: Learning System Analyzes Outcomes

```
User completes task
    │
    └─→ GTD bot publishes gtd.events.task.completed
            │
            └─→ Learning bot subscribed to gtd.events.*
                    │
                    └─→ Analyzes outcome (success? failure?)
                            │
                            └─→ Updates spaced-repetition model
                                    │
                                    └─→ Publishes learning.events.outcome
```

## When Would You Use Bot Army?

✅ **Good fit:**
- Personal automation (GTD, habits, learning, note-taking)
- Multi-step workflows (request → validation → processing → notification)
- Distributed team workflows (bots as shared automations)
- AI-powered agents that coordinate via messaging
- Building a "second brain" that integrates multiple tools

❌ **Not ideal for:**
- Simple CRUD REST APIs (use a web framework like Phoenix)
- High-frequency real-time trading (latency might be too high)
- Embedded systems (too heavy)
- Single-process applications (the overhead of NATS/PostgreSQL isn't worth it)

## Scaling Patterns

### Horizontal Scaling
Add another instance of a busy bot:

```yaml
services:
  gtd_bot_1:
    image: gtd_bot
    environment:
      INSTANCE_ID: 1
  gtd_bot_2:
    image: gtd_bot
    environment:
      INSTANCE_ID: 2
```

All instances listen to the same subjects. NATS queues load-balance requests across them.

### Vertical Scaling
Give a bot more resources:

```yaml
services:
  llm_bot:
    image: llm_bot
    environment:
      POOL_SIZE: 10           # More database connections
      MAX_CONCURRENT: 20      # More in-flight requests
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
```

### Cluster Scaling
Run NATS in HA mode across multiple machines. Bots auto-discover via `NATS_SERVERS`.

## Port Map

| Service | Port | Purpose |
|---------|------|---------|
| NATS | 4222 (prod) | Inter-bot messaging |
| NATS | 4223 (dev) | Manual dev testing |
| PostgreSQL | 35432 | Persistent data |
| Ollama | 11434 | Local LLM inference |
| Monitor | 58222 | Dashboard metrics |

## Messaging Guarantees

NATS provides **at-most-once delivery** by default (fire and forget). For guaranteed delivery, Bot Army adds:

1. **Idempotency keys** — Duplicate requests with same key are deduplicated
2. **Audit logs** — Every action logged for recovery
3. **Retry logic** — Failed requests automatically retry with backoff

This keeps the system resilient without sacrificing performance.

## Security Model

Bot Army assumes:
- **All communication is internal** (containers on same host/network)
- **NATS is trusted** (no auth required in dev/test)
- **PostgreSQL is local** (no external access)
- **Claude Desktop is local** (no remote API)

For production (multi-tenant, cloud):
- Use NATS with TLS + auth
- Run PostgreSQL in a managed service
- Add API gateways and rate limiting
- See `docs/` for enterprise deployment guides

## Next Steps

- **Dive deeper:** See specific bot implementations in `~/code/elixir_bots/bot_army_*`
- **Build a bot:** `make help-create-bot`
- **Test subjects:** `make help-testing`
- **Debug issues:** `make help-debugging`
