# Testing Guide

Learn how to test Bot Army subjects, bots, and integrations.

## Testing Subjects with NATS CLI

The fastest way to test: use `nats request` and `nats subscribe`.

### Pattern 1: Simple Request/Reply

**Test a subject that returns data:**
```bash
nats request --server nats://localhost:4222 \
  gtd.task.list \
  '{}' \
  --timeout 3s
```

Expected output:
```json
{
  "tasks": [],
  "count": 0
}
```

**With data:**
```bash
nats request --server nats://localhost:4222 \
  gtd.task.list \
  '{"status":"pending"}' \
  --timeout 3s
```

### Pattern 2: Create + Verify

**Create a task:**
```bash
nats request --server nats://localhost:4222 \
  gtd.task.create \
  '{
    "name": "Test task",
    "priority": "high"
  }' \
  --timeout 3s
```

Capture the task_id from response:
```bash
TASK_ID=$(nats request --server nats://localhost:4222 \
  gtd.task.create \
  '{"name":"Test task"}' \
  --timeout 3s | jq -r '.data.task_id')

echo "Created task: $TASK_ID"
```

**Verify it exists:**
```bash
nats request --server nats://localhost:4222 \
  gtd.task.get \
  "{\"task_id\":\"$TASK_ID\"}" \
  --timeout 3s
```

### Pattern 3: Pub/Sub Listening

**Watch events as they happen:**
```bash
# Terminal 1: Subscribe to all GTD events
nats subscribe --server nats://localhost:4222 'gtd.events.>'
```

**Terminal 2: Trigger an action:**
```bash
nats request --server nats://localhost:4222 \
  gtd.task.create \
  '{"name":"Test event"}' \
  --timeout 3s
```

**Terminal 1 shows:**
```
[#1] Received on "gtd.events.task.created": {
  "task_id": "550e8400...",
  "name": "Test event",
  "timestamp": "2026-05-27T14:50:00Z"
}
```

### Pattern 4: Load Testing

**Send multiple requests in sequence:**
```bash
#!/bin/bash
for i in {1..100}; do
  nats request --server nats://localhost:4222 \
    gtd.task.create \
    "{\"name\":\"Task $i\"}" \
    --timeout 3s > /dev/null
  echo "Created task $i"
done
```

**Send requests in parallel:**
```bash
#!/bin/bash
for i in {1..10}; do
  (
    nats request --server nats://localhost:4222 \
      gtd.task.create \
      "{\"name\":\"Parallel task $i\"}" \
      --timeout 3s > /dev/null
  ) &
done
wait
echo "Created 10 tasks in parallel"
```

### Pattern 5: Testing Error Cases

**Test with invalid input:**
```bash
nats request --server nats://localhost:4222 \
  gtd.task.create \
  '{"name":""}' \
  --timeout 3s

# Expected:
# error: "Name cannot be empty"
```

**Test non-existent resource:**
```bash
nats request --server nats://localhost:4222 \
  gtd.task.get \
  '{"task_id":"nonexistent"}' \
  --timeout 3s

# Expected:
# error: "Task not found"
```

**Test timeout:**
```bash
# Use very short timeout
nats request --server nats://localhost:4222 \
  gtd.task.list \
  '{}' \
  --timeout 100ms

# Should timeout if bot is slow
```

## Testing Bridge (Claude Integration)

### Test bridge.task.list

```bash
nats request --server nats://localhost:4222 \
  bridge.task.list \
  '{}' \
  --timeout 3s
```

### Test bridge.task.create

```bash
nats request --server nats://localhost:4222 \
  bridge.task.create \
  '{
    "name": "Via Bridge",
    "description": "Testing bridge integration"
  }' \
  --timeout 3s
```

### Verify Bridge Endpoints

```bash
# One-line check of all critical endpoints
make bridge-check

# Detailed check with timeout info
echo "Testing bridge.task.list..."
nats request --server nats://localhost:4222 \
  bridge.task.list '{}' --timeout 5s && echo "✓ OK" || echo "✗ Failed"

echo "Testing bridge.task.create..."
nats request --server nats://localhost:4222 \
  bridge.task.create '{"name":"test"}' --timeout 5s && echo "✓ OK" || echo "✗ Failed"
```

## Testing Your Custom Bot

After creating a bot, test it before adding to the fleet.

### Step 1: Start Your Bot Locally

```bash
cd bot_army_mybot
mix deps.get
mix test                           # Run unit tests
mix test --include integration    # Run integration tests
```

### Step 2: Test Its Subjects

```bash
# Terminal 1: Watch your bot's logs
cd bot_army_mybot
mix ecto.create
mix phx.server    # or your startup command
```

```bash
# Terminal 2: Test the subject
nats request --server nats://localhost:4223 \
  mybot.hello \
  '{"name":"World"}' \
  --timeout 3s

# Should return: {"message":"Hello, World!"}
```

### Step 3: Test with Real Database

```bash
# In your bot's mix.exs, ensure test config has:
config :bot_army_mybot, BotArmyMybot.Repo,
  database: "bot_army_mybot_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,  # or your port

# Run tests against real DB
mix test --include integration

# Check data was persisted
psql -U postgres -d bot_army_mybot_test -c "SELECT * FROM mybot_records;"
```

### Step 4: Test with Real NATS

```bash
# Update config to use real NATS
config :bot_army_mybot, :nats_servers, "nats://localhost:4223"

# Start bot
mix phx.server

# In another terminal, send requests
nats request --server nats://localhost:4223 \
  mybot.hello \
  '{"name":"Test"}' \
  --timeout 3s
```

## Testing Integrations

### Test: Bot to Bot Communication

**Setup:**
- Bot A publishes event: `bot_a.events.created`
- Bot B subscribes to `bot_a.events.>`

**Test it:**
```bash
# Terminal 1: Start Bot A
cd bot_army_bot_a && mix phx.server

# Terminal 2: Start Bot B
cd bot_army_bot_b && mix phx.server

# Terminal 3: Watch Bot B's logs
docker compose logs bot_b -f | grep "Received event"

# Terminal 4: Trigger Bot A
nats request --server nats://localhost:4223 \
  bot_a.trigger \
  '{}' \
  --timeout 3s

# Terminal 3 should show Bot B received the event
```

### Test: Claude Integration

**Setup:**
1. Start Bot Army: `docker compose up -d`
2. Verify Bridge: `make bridge-check`
3. Open Claude Desktop

**Test:**
```
You:    "Create a task called 'Test Claude Integration'"
Claude: [calls bridge.task.create internally]
Claude: "I've created a task called 'Test Claude Integration'"
```

**Verify in NATS:**
```bash
nats request --server nats://localhost:4222 \
  bridge.task.list \
  '{}' \
  --timeout 3s | jq '.data.tasks[] | select(.name == "Test Claude Integration")'

# Should return the task you just created
```

### Test: Synapse → Discord

**Setup:**
1. Synapse bot running
2. Surface_Discord bot running
3. Discord webhook configured

**Test:**
```bash
# Trigger an event that Synapse might forward
nats request --server nats://localhost:4223 \
  gtd.task.create \
  '{"name":"Check Discord!"}' \
  --timeout 3s

# If Synapse has a rule, you should see message in Discord
```

**Debug if it doesn't work:**
```bash
# Check Synapse logs
docker compose logs synapse_bot | grep -i discord

# Check Surface Discord logs
docker compose logs surface_discord | grep -i received

# Subscribe to Discord events
nats subscribe synapse.discord.>
```

## Performance Testing

### Measure Bot Latency

```bash
# Single request
time nats request --server nats://localhost:4223 \
  gtd.task.list \
  '{}' \
  --timeout 3s

# Look at "real" time
```

### Measure Throughput

```bash
#!/bin/bash
COUNT=100
START=$(date +%s%N)

for i in $(seq 1 $COUNT); do
  nats request --server nats://localhost:4223 \
    gtd.task.list \
    '{}' \
    --timeout 3s > /dev/null
done

END=$(date +%s%N)
DURATION_MS=$(( (END - START) / 1000000 ))
RATE=$(( COUNT * 1000 / DURATION_MS ))

echo "Completed $COUNT requests in ${DURATION_MS}ms"
echo "Rate: $RATE requests/sec"
```

### Load Test (Sustained)

```bash
# Open multiple terminals, each running:
while true; do
  nats request --server nats://localhost:4223 \
    gtd.task.list \
    '{}' \
    --timeout 3s > /dev/null
  sleep 0.1
done

# Monitor bot CPU/memory:
docker compose stats gtd_bot
```

## Test Automation

### Create a Test Script

```bash
#!/bin/bash
# test-bot-army.sh

set -e

echo "Testing Bot Army..."
echo ""

# 1. Health check
echo "1. System health..."
make health-check || exit 1

# 2. Create task
echo ""
echo "2. Creating task..."
TASK_ID=$(nats request --server nats://localhost:4222 \
  bridge.task.create \
  '{"name":"Automated test"}' \
  --timeout 3s | jq -r '.data.task_id')
echo "   Created: $TASK_ID"

# 3. List tasks
echo ""
echo "3. Listing tasks..."
COUNT=$(nats request --server nats://localhost:4222 \
  bridge.task.list \
  '{}' \
  --timeout 3s | jq '.data.count')
echo "   Total tasks: $COUNT"

# 4. Update task
echo ""
echo "4. Updating task..."
nats request --server nats://localhost:4222 \
  bridge.task.update \
  "{\"task_id\":\"$TASK_ID\",\"status\":\"in_progress\"}" \
  --timeout 3s > /dev/null
echo "   Updated ✓"

# 5. Complete
echo ""
echo "All tests passed! ✓"
```

**Run it:**
```bash
chmod +x test-bot-army.sh
./test-bot-army.sh
```

## Continuous Testing

Add to your CI/CD pipeline:

```bash
# .github/workflows/test.yml
- name: Test Bot Army
  run: |
    docker compose up -d
    sleep 5
    make health-check
    ./test-bot-army.sh
```

## Common Test Scenarios

| Scenario | Test Command |
|----------|--------------|
| Bot responds to request | `nats request <subject> '{}' --timeout 3s` |
| Bot publishes events | `nats subscribe '<bot>.events.>' &` then trigger |
| Bot stores data | `psql ... -c "SELECT COUNT(*) FROM table"` |
| Bot handles errors | `nats request <subject> '{"invalid":""}' --timeout 3s` |
| Bot under load | `for i in {1..100}; do nats request ...; done` |
| Bridge integration | `make bridge-check` |
| Claude can see data | Ask Claude in Desktop app |

## Troubleshooting Tests

**Test times out:**
- Bot might be down: `docker compose ps`
- NATS not responding: `nats server info --server nats://localhost:4222`
- Network issue: try `localhost` vs `127.0.0.1`

**Test returns error:**
- Invalid JSON in request: validate with `jq`
- Bot crashed: check `docker compose logs <bot>`
- Database issue: check `make health-check`

**Performance slower than expected:**
- Check bot CPU: `docker compose stats <bot>`
- Check database: `docker compose logs postgres | grep slow`
- Increase timeout if network is slow

## Next Steps

- **Create a bot:** `make help-create-bot`
- **Debug issues:** `make help-debugging`
- **Understand architecture:** `make help-architecture`
