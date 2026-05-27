# Troubleshooting

Common issues and solutions when running Bot Army.

## Quick Diagnostics

Before diving into specific issues, run:

```bash
make health-check
```

This checks:
- ✓ Docker daemon
- ✓ NATS connectivity
- ✓ PostgreSQL connectivity
- ✓ Running bots
- ✓ Storage volumes
- ✓ Claude integration

## Installation & Startup

### Dashboard locks up after starting

**Symptom:** Dashboard renders but UI is frozen

**Solution:**
1. Restart: `docker compose restart`
2. Rebuild: `docker compose up -d --build`
3. Check logs: `docker compose logs -f`

See also: [Dashboard Lockup](#dashboard-lockup)

### "docker-compose.yml not found"

**Symptom:** 
```
Error: no docker-compose.yml found — run 'make quickstart' first
```

**Solution:**
```bash
cd /Users/abby/code/bot-army-starter
make quickstart
# Or headless:
make quickstart-default
```

### ".env not found"

**Symptom:**
```
Error: .env not found
```

**Solution:**
The quickstart wizard creates `.env`. If missing:
```bash
make quickstart
# Accept defaults or customize ports
```

## NATS (Message Bus)

### "No responder available"

**Symptom:**
```
nats request system.health '{}' --timeout 3s
No responders available
```

**Means:** Bots aren't running or haven't subscribed yet

**Solution:**
```bash
# 1. Check if bots are running
docker compose ps

# 2. Wait for startup (takes 10-30s)
sleep 30
nats request --server nats://localhost:54222 system.health '{}' --timeout 3s

# 3. Check bot logs
docker compose logs gtd_bot | tail -20
# Should show: "Subscribing to gtd.task.>"
```

### "Connection refused" on NATS port

**Symptom:**
```
Error: dial tcp 127.0.0.1:54222: connection refused
```

**Means:** NATS container isn't running

**Solution:**
```bash
# Start NATS
docker compose up -d nats

# Verify
docker compose logs nats | tail -5
# Should show: "Server is ready"
```

### NATS timeout when sending requests

**Symptom:**
```
nats request timeout
Context deadline exceeded
```

**Means:** Bot is slow to respond or crashed

**Solution:**
```bash
# 1. Increase timeout
nats request --timeout 10s ...

# 2. Check if bot is running
docker compose ps <bot_name>

# 3. Check bot logs for errors
docker compose logs <bot_name> | grep -i error

# 4. Restart bot
docker compose restart <bot_name>
```

## PostgreSQL (Database)

### "PostgreSQL not responding on port 55432"

**Symptom:**
```
Error: PostgreSQL not responding on port 55432
```

**Means:** PostgreSQL container isn't healthy

**Solution:**
```bash
# Check status
docker compose ps postgres

# If not running, start it
docker compose up -d postgres

# Wait for startup (15-30s)
sleep 30

# Check logs
docker compose logs postgres | tail -20
# Should show: "ready to accept connections"
```

### "FATAL: database does not exist"

**Symptom:**
```
Error: FATAL: database "bot_army_dev" does not exist
```

**Means:** Database wasn't initialized

**Solution:**
```bash
# Bots handle migrations automatically on startup
# If still failing:

# 1. Restart PostgreSQL
docker compose restart postgres
sleep 20

# 2. Restart bot (triggers migration)
docker compose restart <bot_name>

# 3. Check bot logs
docker compose logs <bot_name> | grep -i migrat
```

### "Cannot connect to PostgreSQL - password authentication failed"

**Symptom:**
```
Error: FATAL: password authentication failed
```

**Means:** Wrong password in .env or connection string

**Solution:**
```bash
# Default password is "postgres" (dev only)
# Check .env
grep POSTGRES .env

# The connection is via Docker network (not localhost:5432)
# Bots use: ecto://postgres:postgres@postgres:5432/bot_army_dev
```

## Bots

### Bot won't start - "Image build failed"

**Symptom:**
```
docker compose logs mybot_bot
ERROR: Step X/Y in Dockerfile failed
```

**Means:** Code has errors or missing dependencies

**Solution:**
```bash
# 1. Check Dockerfile
cat mybot_bot/Dockerfile

# 2. Check mix.exs for dependencies
grep -A 5 "defp deps" mybot_bot/mix.exs

# 3. Rebuild (should show errors)
docker compose build --no-cache mybot_bot

# 4. Fix errors in code
# Then rebuild

# 5. If bot code is remote (not local)
# Update docker-compose.yml to point to correct repo path
```

### Bot keeps restarting - "restart: unless-stopped"

**Symptom:**
```
docker compose ps
mybot_bot    Restarting (1) 5 seconds ago
```

**Means:** Bot is crashing immediately

**Solution:**
```bash
# Check logs (might scroll quickly)
docker compose logs mybot_bot --tail 50

# Common causes:
# - NATS connection failed (wait for NATS startup)
# - Database not ready (check Postgres)
# - Missing environment variable (check .env)
# - Port already in use (check docker compose logs)

# Stop auto-restart temporarily to debug
docker compose up mybot_bot  # Don't daemonize, see live output

# Or change to
restart: "no"  # in docker-compose.yml temporarily
docker compose up -d mybot_bot
```

### Bot not responding to requests

**Symptom:**
```
nats request gtd.task.list '{}' --timeout 3s
No responders available
```

**Means:** Bot running but not subscribed, or handler crashed

**Solution:**
```bash
# 1. Verify bot is running
docker compose ps gtd_bot
# Should show "Up"

# 2. Check startup logs
docker compose logs gtd_bot | grep -i "subscrib\|ready"
# Should show: "Subscribing to gtd.task.>"

# 3. If subscribed but not responding, handler might be crashing
docker compose logs gtd_bot | tail -20
# Look for errors

# 4. Try simple health check first
nats request --server localhost:54222 system.health '{}' --timeout 3s
# If this works but gtd doesn't, gtd_bot is the issue

# 5. Restart bot
docker compose restart gtd_bot
```

## Docker

### "Cannot connect to Docker daemon"

**Symptom:**
```
Error: Cannot connect to Docker daemon
```

**Means:** Docker Desktop not running

**Solution:**
```bash
# macOS
open /Applications/Docker.app

# Wait for Docker menu bar icon to appear
# Then retry your command
```

### "Disk usage for docker is getting large"

**Symptom:**
```
Docker has consumed X GB of disk
```

**Solution:**
```bash
# See current usage
make disk-check

# Clean up stopped containers & unused images
make docker-clean

# Deep clean (removes all unused layers)
make docker-deep-clean

# Remove all data and start fresh (⚠️ destructive)
make nuke
docker compose up -d --build
```

### Build gets stuck or times out

**Symptom:**
```
docker compose build --build-arg BOT_REPO=...
[Stage X/Y] Step Y/Z ... (hangs)
```

**Means:** Usually a network issue during dependency download

**Solution:**
```bash
# Try building with no-cache
docker compose build --no-cache mybot_bot

# Or increase timeout
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1
docker compose build --progress plain mybot_bot

# Or build locally first (if possible)
cd repos/bot_army_mybot
mix compile
cd -
docker compose build mybot_bot
```

## Claude Integration

### Claude Desktop can't connect to bot-army MCP

**Symptom:**
```
Claude: "I can't connect to the bot-army integration"
```

**Means:** MCP server config is wrong or NATS isn't reachable

**Solution:**
1. Check MCP config:
   ```bash
   cat ~/.claude/claude.json | grep -A 3 bot-army
   ```

2. Verify NATS port (should match your .env):
   ```bash
   grep NATS_PORT .env
   # Default: 54222 (dev) or 4222 (prod)
   ```

3. Test NATS directly:
   ```bash
   nats server check
   # or
   nats request system.health '{}' --timeout 3s
   ```

4. Update claude.json if port is wrong:
   ```json
   {
     "mcpServers": {
       "bot-army": {
         "command": "curl",
         "args": ["-s", "http://localhost:54222/mcp"]
       }
     }
   }
   ```

5. Restart Claude Desktop

### Claude Code can't find skills

**Symptom:**
```
Claude Code: /graphify not found
```

**Means:** Skills not installed or path is wrong

**Solution:**
```bash
# Skills should be in ~/.claude/skills/
ls ~/.claude/skills/

# If missing, clone the repo
git clone <skills-repo> ~/.claude/skills/

# Or symlink from local repo
ln -s /path/to/skills ~/.claude/skills/graphify
```

## Logs

### Where are the logs?

**Locations:**
```bash
# Docker container logs (live)
docker compose logs -f <bot_name>

# Persistent logs (mounted to host)
ls ~/data/logs/

# Docker-specific logs
docker compose logs postgres | head -20
docker compose logs nats | head -20
```

### How to follow logs in real-time?

```bash
# All services
docker compose logs -f

# Specific bot
docker compose logs -f gtd_bot

# Last 50 lines + follow
docker compose logs -f gtd_bot --tail 50

# Search in logs
docker compose logs gtd_bot | grep -i error
```

### Logs are too noisy

**Solution:**
```bash
# Filter by log level (if supported)
docker compose logs gtd_bot | grep -E "ERROR|WARN"

# Or reduce verbosity in bot config
# Check bot's config/ or lib/application.ex for Logger config
```

## Performance

### System is slow after running for a while

**Symptoms:**
- Requests timeout
- Dashboard lags
- CPU usage high

**Solution:**
```bash
# Check Docker resource usage
docker stats

# Check disk space
df -h

# Clean up unused images/containers
make docker-clean

# Restart services
docker compose restart

# Check logs for memory issues
docker compose logs | grep -i "memory\|oom"
```

### One bot is consuming lots of CPU

**Solution:**
```bash
# Identify the bot
docker stats

# Check its logs
docker compose logs <bot_name> | grep -i "loop\|error"

# Restart it
docker compose restart <bot_name>

# Check code for infinite loops or inefficient queries
```

## Getting Help

If you can't find the answer:

1. **Run health check first:**
   ```bash
   make health-check
   ```

2. **Gather logs:**
   ```bash
   docker compose logs > logs.txt
   docker compose ps >> logs.txt
   cat .env >> logs.txt
   ```

3. **Search docs:**
   - `make help-volumes` — Storage issues
   - `make help-create-bot` — Bot creation issues
   - `make claude-integrate` — Claude integration

4. **Check existing issues:**
   - GitHub Issues: https://github.com/ergon-automation-labs/

5. **Ask Claude:**
   ```bash
   cd /Users/abby/code/bot-army-starter
   claude code
   # Upload logs and describe the issue
   ```
