---
doc_status: active
doc_tier: public
owner: abby
last_reviewed: 2026-05-30
review_every_days: 90
source_of_truth: docs/DOCUMENTATION_INDEX.md
---

# Using Bot Army from External Projects

Bot Army exposes a stable NATS interface (`bridge.*` subjects) for other projects, services, and coding agents to integrate with GTD, system health, knowledge graphs, and randomness primitives. This guide covers how to connect any project to Bot Army.

## Architecture

```
Your Project (any language)
         ↓
    NATS Client (Gnat, nats.io, pynats, etc.)
         ↓
  bridge.* (request/reply)
         ↓
  bot_army_claude_bridge (operator RPC façade)
         ↓
  Backend bots (gtd_bot, dispatcher, rpg_bot, etc.)
```

**Key point:** You talk to the bridge, never directly to backend bots. The bridge handles validation, tenant injection, and error mapping.

## Quick Start (5 minutes)

### 1. Verify NATS is reachable

```bash
# Default: localhost:4222 (production)
# Dev: localhost:4223
nats request --server nats://localhost:4222 bridge.system.fact '{}' --timeout 3s
```

If that works, you can connect.

### 2. Create a task (minimal example)

**Elixir:**
```elixir
{:ok, %{"ok" => true, "data" => task}} = 
  Gnat.request(
    :nats_connection,
    "bridge.task.create",
    Jason.encode!(%{
      "title" => "Learn Bot Army integration",
      "description" => "Connect my Go project to Bot Army GTD"
    }),
    timeout: 5000
  )

IO.inspect(task["id"])  # → "task-uuid-here"
```

**Go (nats.go):**
```go
import "github.com/nats-io/nats.go"

nc, _ := nats.Connect("nats://localhost:4222")
defer nc.Close()

msg, _ := nc.Request("bridge.task.create", []byte(`{
  "title": "Learn Bot Army integration",
  "description": "Connect my Go project to Bot Army GTD"
}`), 5*time.Second)

// Response is in msg.Data — parse as JSON
```

**Python (nats-py):**
```python
import asyncio
import json
from nats.aio.client import Client as NATS

async def main():
    nc = NATS()
    await nc.connect("nats://localhost:4222")
    
    msg = await nc.request("bridge.task.create", json.dumps({
        "title": "Learn Bot Army integration",
        "description": "Connect my Python project to Bot Army GTD"
    }).encode(), timeout=5)
    
    task = json.loads(msg.data)
    print(task["data"]["id"])
    
    await nc.close()

asyncio.run(main())
```

**Node.js (nats):**
```javascript
const { connect } = require("nats");

(async () => {
  const nc = await connect({ servers: "nats://localhost:4222" });
  
  const msg = await nc.request("bridge.task.create", JSON.stringify({
    title: "Learn Bot Army integration",
    description: "Connect my Node project to Bot Army GTD"
  }), { timeout: 5000 });
  
  const task = JSON.parse(msg.data);
  console.log(task.data.id);
  
  await nc.close();
})();
```

**cURL + jq (for scripts):**
```bash
nats request --server nats://localhost:4222 bridge.task.create '{
  "title": "Learn Bot Army integration",
  "description": "Connect my shell script to Bot Army GTD"
}' --timeout 5s | jq '.data.id'
```

## Stable Bridge Facades (Public API)

### Task Management

| Subject | Purpose | Request | Response |
|---------|---------|---------|----------|
| **`bridge.task.create`** | Create a new task | `{title, description?, context?, labels?}` | `{ok, data: {id, created_at}}` |
| **`bridge.task.list`** | List tasks with filters | `{limit?, offset?, filters?}` | `{ok, data: {tasks: [], total}}` |
| **`bridge.task.get`** | Get a specific task | `{task_id}` | `{ok, data: {...task}}` |
| **`bridge.task.update`** | Update task fields | `{task_id, title?, status?, ...}` | `{ok, data: {...updated}}` |
| **`bridge.task.complete`** | Mark task done | `{task_id}` | `{ok, data: {completed_at}}` |
| **`bridge.task.search`** | Search tasks by query | `{query, limit?, filters?}` | `{ok, data: {tasks: []}}` |

**Examples:**

```bash
# List all tasks
nats request --server nats://localhost:4222 bridge.task.list '{
  "limit": 50
}' --timeout 5s

# Search tasks
nats request --server nats://localhost:4222 bridge.task.search '{
  "query": "integration",
  "limit": 10
}' --timeout 5s

# Get a specific task
nats request --server nats://localhost:4222 bridge.task.get '{
  "task_id": "abc-123"
}' --timeout 5s

# Complete a task
nats request --server nats://localhost:4222 bridge.task.complete '{
  "task_id": "abc-123"
}' --timeout 5s
```

### Project Management

| Subject | Purpose | Request | Response |
|---------|---------|---------|----------|
| **`bridge.project.create`** | Create a new project | `{title, description?, presentation?}` | `{ok, data: {id, created_at}}` |
| **`bridge.project.list`** | List all projects | `{limit?, offset?}` | `{ok, data: {projects: []}}` |
| **`bridge.project.get`** | Get a specific project | `{project_id}` | `{ok, data: {...project}}` |
| **`bridge.project.update`** | Update project fields | `{project_id, title?, status?, ...}` | `{ok, data: {...updated}}` |

### System & Health

| Subject | Purpose | Request | Response |
|---------|---------|---------|----------|
| **`bridge.system.fact`** | Get a random system fact or live bot status | `{}` | `{ok, data: {fact, fact_source}}` |
| **`bridge.synapse.awareness`** | Full system health snapshot | `{}` | `{ok, data: {bots: [], health: {...}}}` |
| **`bridge.registry.capabilities.list`** | List all registered bots + their subjects | `{}` | `{ok, data: {bots: [{name, version, subjects: []}]}}` |

**Examples:**

```bash
# Get system health
nats request --server nats://localhost:4222 bridge.synapse.awareness '{}' --timeout 5s

# List all bots and their capabilities
nats request --server nats://localhost:4222 bridge.registry.capabilities.list '{}' --timeout 5s

# Get a random fact about the system
nats request --server nats://localhost:4222 bridge.system.fact '{}' --timeout 5s
```

### Knowledge Graph (Codebase Context)

| Subject | Purpose | Request | Response |
|---------|---------|---------|----------|
| **`bridge.graph.query`** | Query Graphify knowledge graph for a repo | `{repo_path}` | `{ok, data: {graph: {...JSON}}}` |

**Example (in a coding agent context):**

```bash
# Get codebase knowledge graph for elixir_bots
nats request --server nats://localhost:4222 bridge.graph.query '{
  "repo_path": "/Users/abby/code/elixir_bots"
}' --timeout 120s | jq '.data.graph'
```

### Randomness (TTRPG, Testing, Variety)

| Subject | Purpose | Request | Response |
|---------|---------|---------|----------|
| **`bridge.random.roll`** | Roll dice or generate random values | `{notation, seed?, purpose?}` | `{ok, data: {rolls: [], total, ...}}` |

**Example:**

```bash
# Roll 2d6 for a fitness challenge variety pick
nats request --server nats://localhost:4222 bridge.random.roll '{
  "notation": "2d6",
  "purpose": "fitness_workout_variety"
}' --timeout 5s
```

### Narrative Briefing

| Subject | Purpose | Request | Response |
|---------|---------|---------|----------|
| **`bridge.chronicle.daily.brief`** | Get a narrative daily briefing | `{presentation?, live?, choice?}` | `{ok, data: {generated_at, opening, signals, snapshot}}` |

**Example:**

```bash
# Get a narrative briefing of today's tasks and system state
nats request --server nats://localhost:4222 bridge.chronicle.daily.brief '{
  "presentation": "plain",
  "live": true
}' --timeout 30s | jq '.data.opening'
```

See [PI_GO_BRIDGE_SUBJECTS.md](PI_GO_BRIDGE_SUBJECTS.md) for full contract details.

## Common Patterns

### Pattern 1: Store Work in Shared GTD

Your project creates tasks in Bot Army's GTD so they show up in the TUI, daily briefings, and other surfaces.

```elixir
# In your Go bot or Elixir app
Gnat.request(
  :nats_connection,
  "bridge.task.create",
  Jason.encode!(%{
    "title" => "Review job_applications bot PR feedback",
    "description" => "Implement requested schema changes and retest",
    "context" => "bot_army_job_applications",
    "labels" => ["review", "merge-blocker"]
  }),
  timeout: 5000
)
```

**Result:** Task appears in GTD TUI, daily brief, and task lists for human + agent operators.

### Pattern 2: Fetch System Context Before Decisions

Your coding agent queries Bot Army before deciding what to work on.

```bash
# In a shell script or Makefile
HEALTH=$(nats request --server nats://localhost:4222 bridge.synapse.awareness '{}' --timeout 5s)

# Check if any bots are unhealthy
UNHEALTHY=$(echo "$HEALTH" | jq '.data.bots[] | select(.status != "healthy")')

if [ ! -z "$UNHEALTHY" ]; then
  echo "System degraded — skipping deployment"
  exit 1
fi
```

### Pattern 3: Inject Randomness

Your bot/TUI uses Bot Army's dice rolls for consistent, reproducible randomness across services.

```go
// In your Go TUI or service
msg, _ := nc.Request("bridge.random.roll", []byte(`{
  "notation": "d100",
  "purpose": "workout_difficulty_roll"
}`), 5*time.Second)

var roll struct {
  Ok   bool `json:"ok"`
  Data struct {
    Total int `json:"total"`
  } `json:"data"`
}
json.Unmarshal(msg.Data, &roll)

difficulty := "hard"
if roll.Data.Total < 40 {
  difficulty = "easy"
}
```

### Pattern 4: Multi-Language Workflow

Your team works across Elixir (bots), Go (TUIs), Python (scripts), and JavaScript (web dashboards). All talk to the same GTD backend.

```python
# Python script in a CI/CD pipeline
import nats
import json

async def check_and_create_blocker():
    nc = await nats.connect("nats://localhost:4222")
    
    # Check if there are unresolved blockers
    msg = await nc.request("bridge.task.search", json.dumps({
        "query": "blocker",
        "filters": {"status": ["open"]}
    }).encode(), timeout=5)
    
    tasks = json.loads(msg.data)
    if len(tasks["data"]["tasks"]) > 3:
        # Too many blockers — create an alert task
        await nc.request("bridge.task.create", json.dumps({
            "title": "⚠️ Too many blockers — triage needed",
            "labels": ["alert", "triage"]
        }).encode(), timeout=5)
```

## Response Format

All bridge responses follow this envelope:

```json
{
  "ok": true,
  "schema_version": "v1",
  "timestamp": "2026-05-30T10:30:00Z",
  "data": {
    "id": "task-123",
    "title": "...",
    ...
  }
}
```

**Error responses:**

```json
{
  "ok": false,
  "error": "invalid_request",
  "errors": [
    {"field": "title", "message": "required"}
  ],
  "timestamp": "2026-05-30T10:30:00Z"
}
```

**Always access payload via `response["data"]`, not top-level fields.**

## Security & Boundaries

### What's Safe to Expose

- ✅ `bridge.task.*` — GTD operations (multi-tenant, validated)
- ✅ `bridge.graph.query` — Read-only codebase context (cached)
- ✅ `bridge.system.fact` — Public system health (anonymized)
- ✅ `bridge.random.roll` — Stateless randomness

### What's NOT for External Callers

- ❌ Direct bot subjects (e.g., `gtd.task.create`) — use `bridge.*` instead
- ❌ Internal subjects (e.g., `dispatcher.intention.*`) — implementation detail
- ❌ Database-backed subjects without validation — bridge adds validation

### Tenant Context

If you're building a multi-tenant system or using Bot Army in shared infrastructure:

```bash
# The bridge injects tenant_id automatically if omitted
# If your auth system provides tenant_id, include it:

nats request --server nats://localhost:4222 bridge.task.create '{
  "title": "...",
  "tenant_id": "company-acme"
}' --timeout 5s
```

## Configuration

### NATS Connection Defaults

| Environment | Host | Port | Use Case |
|-------------|------|------|----------|
| **Production** | localhost (or NATS_SERVERS env var) | **4222** | Live system, bridge service, operators |
| **Development** | localhost | **4223** | Local dev testing (isolated) |
| **Test** | localhost | **4224** | CI/CD test runs (isolated) |

**Choose the right port for your context.** For external projects connecting to a shared Bot Army instance, use **4222** (production).

### Environment Variables

```bash
# In your project's .env or docker-compose.yml

# NATS cluster (comma-separated for HA)
NATS_SERVERS=nats://localhost:4222,nats://localhost:14223

# Timeout for requests (ms)
BOT_ARMY_BRIDGE_TIMEOUT_MS=5000

# Enable TTRPG-flavor responses (optional)
BOT_ARMY_PRESENTATION=plain
# or: presentation=chronicle (for narrative flavor)
```

## Examples by Language

### Elixir

```elixir
defmodule MyBot.BridgeClient do
  def create_task(title, description) do
    {:ok, conn} = Gnat.start_link(name: :nats)
    
    {:ok, response} = Gnat.request(
      conn,
      "bridge.task.create",
      Jason.encode!(%{
        "title" => title,
        "description" => description
      }),
      timeout: 5000
    )
    
    Jason.decode!(response.body)
  end
end
```

### Go

```go
package main

import (
  "encoding/json"
  "github.com/nats-io/nats.go"
  "time"
)

func createTask(nc *nats.Conn, title, desc string) (string, error) {
  payload := map[string]string{
    "title":       title,
    "description": desc,
  }
  data, _ := json.Marshal(payload)
  
  msg, err := nc.Request("bridge.task.create", data, 5*time.Second)
  if err != nil {
    return "", err
  }
  
  var response map[string]interface{}
  json.Unmarshal(msg.Data, &response)
  
  taskID := response["data"].(map[string]interface{})["id"].(string)
  return taskID, nil
}
```

### Python

```python
import asyncio
import json
from nats.aio.client import Client as NATS

async def create_task(nc, title, description):
    msg = await nc.request("bridge.task.create", json.dumps({
        "title": title,
        "description": description
    }).encode(), timeout=5)
    
    response = json.loads(msg.data)
    return response["data"]["id"]

# Usage
nc = await nats.connect("nats://localhost:4222")
task_id = await create_task(nc, "My Task", "Description")
await nc.close()
```

### Node.js

```javascript
const { connect } = require("nats");

async function createTask(title, description) {
  const nc = await connect({ servers: "nats://localhost:4222" });
  
  const msg = await nc.request("bridge.task.create", JSON.stringify({
    title, description
  }), { timeout: 5000 });
  
  const response = JSON.parse(msg.data);
  return response.data.id;
}
```

### Bash / cURL

```bash
#!/bin/bash

create_task() {
  local title="$1"
  local description="$2"
  
  nats request --server nats://localhost:4222 bridge.task.create "{
    \"title\": \"$title\",
    \"description\": \"$description\"
  }" --timeout 5s | jq '.data.id'
}

TASK_ID=$(create_task "Learn NATS" "Explore async messaging")
echo "Created task: $TASK_ID"
```

## Testing & Smoke Tests

### Makefile Targets (from elixir_bots monorepo)

```bash
# All bridge responders available?
make bridge-check

# Test a specific bridge subject?
make bridge-task-list

# Full smoke suite
make bridge-check INCLUDE_BRIDGE_DOCS=1
```

### Manual Smoke Test

```bash
#!/bin/bash
set -e

SERVER="nats://localhost:4222"
TIMEOUT="5s"

echo "Testing bridge.task.list..."
nats request --server $SERVER bridge.task.list '{"limit": 1}' --timeout $TIMEOUT | jq '.ok'

echo "Testing bridge.project.list..."
nats request --server $SERVER bridge.project.list '{}' --timeout $TIMEOUT | jq '.ok'

echo "Testing bridge.system.fact..."
nats request --server $SERVER bridge.system.fact '{}' --timeout $TIMEOUT | jq '.data.fact'

echo "✅ All smoke tests passed"
```

## Deployment Checklist

- [ ] NATS server is accessible (firewall, DNS, port)
- [ ] Choose correct port (4222 = prod, 4223 = dev, 4224 = test)
- [ ] Set `NATS_SERVERS` env var if using HA/remote
- [ ] Test one bridge call before deploying your integration
- [ ] Handle response envelope (`response["data"]`, not top-level)
- [ ] Set appropriate timeout (5-30s depending on subject)
- [ ] Graceful degradation when bridge is unavailable
- [ ] Log NATS errors for debugging

## Troubleshooting

### "No responders"

```
error: no responders available for request
```

**Causes:**
- Bridge bot not running
- Wrong NATS port (check you're using 4222, not 4223)
- Subject typo

**Fix:**
```bash
# Verify bridge is running
make bridge-check

# Check which subjects are available
nats sub --server nats://localhost:4222 \* &
# (hit Ctrl+C after seeing subscriptions)
```

### Timeout

```
error: request timeout
```

**Causes:**
- Network latency (increase timeout)
- Bridge is overloaded
- Graph query too expensive

**Fix:**
```bash
# Increase timeout
timeout: 30000  # milliseconds

# For graph queries specifically
timeout: 120000  # 2 minutes
```

### Invalid response

```
json: cannot unmarshal string into Go value of type map[string]interface{}
```

**Cause:** Response format changed or request malformed.

**Fix:** Check response is valid JSON and has `"ok"` field:
```bash
nats request --server nats://localhost:4222 bridge.task.list '{"limit": 1}' --timeout 5s | jq '.'
```

## Next Steps

1. **Read the full spec** — [PI_GO_BRIDGE_SUBJECTS.md](PI_GO_BRIDGE_SUBJECTS.md) for contract details
2. **Set up NATS client** — Pick your language, add dependency
3. **Test with cURL** — Smoke test one subject before integrating
4. **Integrate into your project** — Start with task creation or system health checks
5. **Join the community** — Questions? See `docs/DOCUMENTATION_INDEX.md` for contact info

## See Also

- [PI_GO_BRIDGE_SUBJECTS.md](PI_GO_BRIDGE_SUBJECTS.md) — Complete bridge contract spec
- [NATS Documentation](https://docs.nats.io/) — NATS request/reply protocol
- [Bot Army Architecture](docs/drawings/overview.mmd) — System diagram
- [Bot Army Starter](../code/bot-army-starter) — One-line distribution tool
