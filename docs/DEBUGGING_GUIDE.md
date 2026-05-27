# Debugging Guide

When something goes wrong, use this guide to isolate and fix the issue.

## Diagnostic Flowchart

```
Something broken?
│
├─ All services down?
│  ├─ Check Docker: docker compose ps
│  ├─ Check NATS: nats server info --server nats://localhost:4222
│  └─ Restart: docker compose down && docker compose up -d
│
├─ Specific bot not responding?
│  ├─ Check it's running: docker compose ps | grep <bot_name>
│  ├─ Check logs: docker compose logs <bot_name>
│  ├─ Check NATS health: make health-check
│  └─ Restart bot: docker compose restart <bot_name>
│
├─ Command times out or hangs?
│  ├─ Check NATS is listening: nats server info --server nats://localhost:4222
│  ├─ Check bot is subscribed: nats subscribe --queue-info <subject>
│  ├─ Try increasing timeout: nats request <subject> '{}' --timeout 10s
│  └─ Check bot logs for errors
│
├─ Database connection error?
│  ├─ Check PostgreSQL running: docker compose ps postgres
│  ├─ Check database exists: psql -U postgres -h localhost -l
│  ├─ Run migrations: make migrate BOT=<name>
│  └─ Check bot config for DB credentials
│
└─ Claude can't see data?
   ├─ Check bridge.task.list works: make bridge-check
   ├─ Check bot is publishing data
   └─ Check Claude has right permissions
```

## Step 1: Check System Health

Start here—this validates the entire stack:

```bash
make health-check
```

This verifies:
- ✓ Docker is running
- ✓ NATS is responsive
- ✓ PostgreSQL is accepting connections
- ✓ At least one bot is running
- ✓ Storage volumes exist

If any check fails, jump to **Step 2**.

## Step 2: Check Docker Services

**See what's running:**
```bash
docker compose ps
```

Expected output:
```
NAME              STATUS          PORTS
nats              Up 5 minutes    4222->4222/tcp
postgres          Up 5 minutes    5432->5432/tcp
gtd_bot           Up 3 minutes
bridge_bot        Up 3 minutes
...
```

**If a service isn't running:**
```bash
# Start it
docker compose up -d <service_name>

# Watch startup logs
docker compose logs -f <service_name>
```

**If a service crashes immediately:**
```bash
# See why it crashed
docker compose logs <service_name> | tail -50

# Look for:
# - "error: " — explicit error
# - "Exited with code" — crash
# - "connection refused" — dependency not ready
```

## Step 3: Check NATS Connectivity

**Verify NATS is listening:**
```bash
nats server info --server nats://localhost:4222
```

Expected:
```
Server Information
  Version: 2.9.x
  Uptime: 3h24m
  Connected Clients: 6
  Subscriptions: 42
  ...
```

**If it says "connection refused":**
```bash
# NATS port not open. Check if it's running:
docker compose ps nats

# If not running, start it:
docker compose up -d nats

# If it crashes, check logs:
docker compose logs nats
```

**Test request/reply:**
```bash
# This will hang if no one is subscribed
timeout 3 nats request --server nats://localhost:4222 \
  gtd.task.list \
  '{}' \
  --timeout 2s || echo "No responder (bot might be down)"
```

## Step 4: Check Bot Logs

**See last 50 lines of a bot's logs:**
```bash
docker compose logs <bot_name> | tail -50
```

**Follow logs in real-time:**
```bash
docker compose logs -f <bot_name>
```

**Look for common errors:**

| Error | Meaning | Fix |
|-------|---------|-----|
| `connection refused` | Can't reach NATS or DB | Check NATS/PostgreSQL running |
| `FATAL 3D000` | Database doesn't exist | Run `make migrate` |
| `timeout` | No responder on subject | Check bot is subscribed |
| `EXIT signal: 1` | Unhandled exception | Search logs for stack trace |
| `supervision tree terminated` | OTP crash | Check recent code changes |

**Search logs for a specific error:**
```bash
# Find all "error" lines
docker compose logs <bot_name> 2>&1 | grep -i error | head -20

# Find errors from last 5 minutes
docker compose logs <bot_name> --since 5m 2>&1 | grep -i error

# Follow errors only
docker compose logs -f <bot_name> 2>&1 | grep -E "error|Error|ERROR"
```

## Step 5: Check Database

**Connect to PostgreSQL:**
```bash
# Start a psql session
docker compose exec postgres psql -U postgres
```

**Common queries:**
```sql
-- List all databases
\l

-- Connect to a bot's database
\c bot_army_gtd

-- List tables
\dt

-- Count tasks
SELECT COUNT(*) FROM tasks;

-- See migration history
SELECT * FROM schema_migrations ORDER BY version DESC LIMIT 5;

-- Exit
\q
```

**If database doesn't exist:**
```bash
# Run migrations to create it
make migrate BOT=<bot_name>

# Or manually create
docker compose exec postgres createdb -U postgres bot_army_<bot_name>
```

**If migrations failed:**
```bash
# Check migration status
make migrate-status

# View migration logs
docker compose logs <bot_name> | grep -i migration

# Rollback and retry
make rollback BOT=<bot_name> STEPS=1
make migrate BOT=<bot_name>
```

## Step 6: Test Individual Subjects

**Test a working subject:**
```bash
nats request --server nats://localhost:4222 \
  gtd.task.list \
  '{}' \
  --timeout 3s
```

Expected response:
```json
{
  "tasks": [],
  "count": 0
}
```

**If timeout:**
- Bot isn't subscribed to that subject
- Subject name is wrong
- Bot is crashed or hung
- NATS is down

**Subscribe and listen:**
```bash
# See all messages on a subject
nats subscribe --server nats://localhost:4222 'gtd.>'

# In another terminal, trigger an action:
docker compose exec gtd_bot /app/bin/gtd_bot eval "..."

# You should see events appear
```

## Step 7: Test Claude Integration

**Verify bridge is responding:**
```bash
make bridge-check
```

Expected:
```
✓ bridge.task.list responding
✓ bridge.project.list responding
✓ bridge.internal_docs.query responding
...
```

**If bridge doesn't respond:**
```bash
# Check Bridge bot is running
docker compose ps bridge_bot

# Check it's subscribed to bridge.* subjects
docker compose logs bridge_bot | grep -i subscribe

# Test directly
nats request --server nats://localhost:4222 \
  bridge.task.list \
  '{}' \
  --timeout 3s
```

**If Claude Desktop can't see data:**
1. Verify Bridge is running: `docker compose ps bridge_bot`
2. Test Bridge manually: `make bridge-check`
3. Restart Claude Desktop
4. Check Claude logs: `/var/log/claude/` (if available)
5. Verify MCP server is configured: See `make help-claude-integrate`

## Step 8: Debug Slow Responses

**Measure request latency:**
```bash
time nats request --server nats://localhost:4222 \
  gtd.task.list \
  '{}' \
  --timeout 10s

# real 0m0.234s  <- Total time
```

**If slower than expected (>1s):**
1. **Check bot CPU/memory:**
   ```bash
   docker compose stats <bot_name>
   ```
   Look for high CPU or near-memory-limit.

2. **Check database performance:**
   ```bash
   docker compose logs <bot_name> | grep -i "query took"
   ```

3. **Check NATS latency:**
   ```bash
   nats pub test.latency "ping" && nats sub test.latency
   ```

4. **Increase resources:**
   ```yaml
   services:
     gtd_bot:
       environment:
         POOL_SIZE: 20       # More DB connections
         MAX_CONCURRENT: 50  # More in-flight requests
   ```

## Step 9: Restart Strategy

**Restart just one bot:**
```bash
docker compose restart <bot_name>
```

**Restart all bots (keep NATS/DB):**
```bash
docker compose restart

# Or selective restart
docker compose restart gtd_bot bridge_bot
```

**Full clean restart (nuclear option):**
```bash
docker compose down
docker compose up -d

# This drops all container state but keeps volumes (data)
```

**Restart and watch logs:**
```bash
docker compose restart <bot_name> && \
  docker compose logs -f <bot_name>
```

## Step 10: Advanced Troubleshooting

### Memory Leak (bot gets slower over time)

```bash
# Check memory usage
docker compose stats <bot_name>

# If it keeps growing, likely a memory leak
# Restart bot
docker compose restart <bot_name>

# Report to bot developer
```

### Deadlock (bot hangs completely)

```bash
# Check if process is hung
docker compose exec <bot_name> ps aux | grep beam

# If hung, restart:
docker compose restart <bot_name>

# Check logs for what it was doing
docker compose logs <bot_name> | tail -100 | grep -i "request\|queue"
```

### Database Deadlock

```bash
# View active queries
docker compose exec postgres psql -U postgres -d bot_army_gtd -c \
  "SELECT * FROM pg_stat_activity WHERE query != 'idle';"

# Check logs for deadlock messages
docker compose logs postgres | grep -i deadlock

# Restart database (loses in-flight transactions)
docker compose restart postgres
```

### Port Conflicts

```bash
# Check what's using port 4222
lsof -i :4222

# Or with netstat
netstat -tlnp | grep 4222

# If it's an old container:
docker stop <container_id>
docker compose up -d
```

## Quick Reference: Common Commands

| Problem | Command |
|---------|---------|
| Everything frozen | `make health-check` |
| Bot not responding | `docker compose logs <bot> \| tail -50` |
| Want to see everything | `docker compose logs -f` |
| Test a subject | `nats request nats://localhost:4222 <subject> '{}' --timeout 3s` |
| Check database | `docker compose exec postgres psql -U postgres` |
| Restart one bot | `docker compose restart <bot_name>` |
| Restart everything | `docker compose down && docker compose up -d` |
| Follow a bot's output | `docker compose logs -f <bot_name>` |
| Check memory/CPU | `docker compose stats` |

## Getting Help

If you're still stuck:

1. **Collect diagnostics:**
   ```bash
   make health-check 2>&1 | tee /tmp/health.log
   docker compose logs > /tmp/all-logs.txt
   ```

2. **Check what changed:**
   ```bash
   git log --oneline -5        # Recent commits
   docker compose config       # Current configuration
   ```

3. **Search for similar issues:**
   - `make help-troubleshoot` — Troubleshooting FAQ
   - GitHub issues in the bot repository
   - NATS documentation (nats.io)
   - Elixir error documentation

4. **Report the issue:**
   - Include output of `make health-check`
   - Last 50 lines of relevant logs
   - Steps to reproduce
   - What you expected vs. what happened
