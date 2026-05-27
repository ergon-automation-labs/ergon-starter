# Bridge API Reference

The Bridge bot exposes a unified API for Claude and other clients to interact with Bot Army. All subjects use `bridge.*` naming.

## Task Management

### bridge.task.create
Create a new task.

**Request:**
```json
{
  "name": "Deploy new feature",
  "description": "Update production servers",
  "due_date": "2026-05-30",
  "priority": "high"
}
```

**Response:**
```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Deploy new feature",
  "status": "pending",
  "created_at": "2026-05-27T14:30:00Z"
}
```

**Example:**
```bash
nats request --server nats://localhost:4222 \
  bridge.task.create \
  '{"name":"My Task","priority":"high"}' \
  --timeout 3s
```

### bridge.task.list
List all tasks, optionally filtered by status.

**Request:**
```json
{
  "status": "pending"        # Optional: pending, in_progress, done, archived
}
```

**Response:**
```json
{
  "tasks": [
    {
      "task_id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Deploy feature",
      "status": "pending",
      "due_date": "2026-05-30",
      "created_at": "2026-05-27T10:00:00Z"
    }
  ],
  "count": 1
}
```

**Example:**
```bash
nats request --server nats://localhost:4222 \
  bridge.task.list \
  '{"status":"pending"}' \
  --timeout 3s
```

### bridge.task.get
Get details of a single task.

**Request:**
```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response:**
```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Deploy feature",
  "description": "Update production servers",
  "status": "pending",
  "due_date": "2026-05-30",
  "priority": "high",
  "created_at": "2026-05-27T10:00:00Z",
  "updated_at": "2026-05-27T10:00:00Z"
}
```

### bridge.task.update
Update a task's fields.

**Request:**
```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "in_progress",
  "priority": "urgent"
}
```

**Response:**
```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "in_progress",
  "updated_at": "2026-05-27T14:35:00Z"
}
```

### bridge.task.delete
Mark a task as archived.

**Request:**
```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response:**
```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "archived",
  "deleted_at": "2026-05-27T14:36:00Z"
}
```

## Projects

### bridge.project.list
List all projects.

**Request:**
```json
{}
```

**Response:**
```json
{
  "projects": [
    {
      "project_id": "abcd1234-ef56-78gh-ijkl-mnopqrstuvwx",
      "name": "Q2 Goals",
      "status": "active",
      "created_at": "2026-05-01T00:00:00Z"
    }
  ]
}
```

### bridge.project.create
Create a new project.

**Request:**
```json
{
  "name": "Website Redesign",
  "description": "Refresh the public website"
}
```

**Response:**
```json
{
  "project_id": "abcd1234-ef56-78gh-ijkl-mnopqrstuvwx",
  "name": "Website Redesign",
  "status": "active",
  "created_at": "2026-05-27T14:40:00Z"
}
```

## Internal Documentation

### bridge.internal_docs.query
Search internal documentation (your project README, schemas, guides).

**Request:**
```json
{
  "query": "authentication flow",
  "limit": 5
}
```

**Response:**
```json
{
  "results": [
    {
      "title": "Auth Architecture",
      "source": "docs/AUTH.md",
      "snippet": "Authentication uses JWT tokens stored in PostgreSQL..."
    }
  ],
  "count": 1
}
```

## Knowledge Graph

### bridge.graph.query
Query the codebase knowledge graph for context.

**Request:**
```json
{
  "repo_path": "/Users/abby/code/elixir_bots",
  "query": "How do bots handle NATS connections?"
}
```

**Response:**
```json
{
  "cached_at": "2026-05-27T12:00:00Z",
  "graph": {
    "entities": [
      {
        "name": "BotArmyRuntime.NATS.Connection",
        "type": "module",
        "file": "bot_army_runtime/lib/bot_army_runtime/nats/connection.ex"
      }
    ],
    "relationships": [
      {
        "from": "BotArmyRuntime.NATS.Connection",
        "to": "Gnat.ConnectionSupervisor",
        "type": "uses"
      }
    ]
  }
}
```

## Random Generation

### bridge.random.roll
Roll dice (useful for games, randomized selection).

**Request:**
```json
{
  "sides": 20,
  "count": 1
}
```

**Response:**
```json
{
  "rolls": [17],
  "total": 17
}
```

## System Health

### system.health
Subscribe to health beacons from all running bots.

**Example:**
```bash
nats subscribe --server nats://localhost:4222 system.health
```

**Response (every bot, every 30 minutes):**
```json
{
  "service": "gtd",
  "status": "healthy",
  "version": "0.7.106",
  "uptime_seconds": 3600,
  "timestamp": "2026-05-27T14:50:00Z"
}
```

## Common Patterns

### Pattern 1: Create + Decompose (Claude)
```bash
# Create a task
task=$(nats request bridge.task.create \
  '{"name":"Build a chatbot","priority":"high"}' \
  --timeout 3s | jq -r '.task_id')

# Ask Claude to decompose it
# (Claude calls bridge.llm.decompose internally)
# Claude replies with subtasks
```

### Pattern 2: List + Filter (Scripts)
```bash
# Get all pending tasks
nats request bridge.task.list \
  '{"status":"pending"}' \
  --timeout 3s | jq '.tasks[] | .name'
```

### Pattern 3: Pub/Sub for Events (Monitoring)
```bash
# Watch all GTD events in real-time
nats subscribe gtd.events.>

# You'll see:
# - task.created
# - task.updated
# - task.completed
```

## Error Handling

All responses include error handling:

**Success:**
```json
{
  "data": {...},
  "status": "ok"
}
```

**Error:**
```json
{
  "error": "Task not found",
  "error_code": "NOT_FOUND",
  "status": "error"
}
```

Common error codes:
- `NOT_FOUND` — Resource doesn't exist
- `INVALID_INPUT` — Validation failed
- `UNAUTHORIZED` — Permission denied
- `INTERNAL_ERROR` — Server error, check logs

## Rate Limiting

No rate limits in dev/test. In production, Bridge applies:
- 100 requests/second per client
- Burst allowance: 10 requests
- Backoff: exponential retry with jitter

## Timeout Guidance

Recommended timeouts by subject:

| Subject | Typical | Timeout |
|---------|---------|---------|
| task.* | 100ms | 3s |
| llm.decompose | 5s | 15s |
| internal_docs.query | 500ms | 5s |
| graph.query | 2s | 30s |

## Testing Bridge Endpoints

```bash
# Start a subscription (in another terminal)
nats subscribe --server nats://localhost:4222 'bridge.>'

# Send a request
nats request --server nats://localhost:4222 \
  bridge.task.list \
  '{}' \
  --timeout 3s

# You should see the response appear
```

## Debugging Bridge Issues

**Bridge not responding?**
```bash
# Check if Bridge bot is running
docker compose ps | grep bridge

# Check logs
docker compose logs bridge_bot | tail -20

# Verify NATS is reachable
nats server info --server nats://localhost:4222
```

**Timeout on requests?**
```bash
# Increase timeout (default 3s may be too short for LLM)
nats request bridge.task.list '{}' --timeout 10s

# Check Bridge logs for slow responses
docker compose logs bridge_bot | grep -i slow
```

**Wrong response format?**
```bash
# Check raw response
nats request bridge.task.list '{}' --timeout 3s | jq .

# Expected structure:
# { "data": {...}, "status": "ok" }
```

## Next Steps

- **Create a bot** that uses Bridge subjects: `make help-create-bot`
- **Test Bridge** yourself: `make health-check` or above examples
- **Integrate Claude**: `make help-claude-integrate`
- **Troubleshoot**: `make help-debugging`
