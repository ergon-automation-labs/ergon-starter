# Quick Start: First Things to Try

You've just finished `make quickstart`. Here are 5 practical demos to understand how Bot Army works.

**Total time: ~20 minutes**

## Prerequisites

Before starting, verify everything is running:

```bash
make health-check
```

All checks should pass. If not, see `make help-troubleshoot`.

## Demo 1: Check System Health (2 min)

Start with the health check to understand your system:

```bash
make health-check
```

You'll see:
- ✓ NATS responding (message bus)
- ✓ PostgreSQL listening (database)
- ✓ Running bots (count)
- ✓ Storage volumes (where your data lives)

**What you learned:** Bot Army is built on NATS for messaging and PostgreSQL for persistence.

---

## Demo 2: Create Your First GTD Task (3 min)

### Option A: Via NATS CLI (Quickest)

```bash
# Send a request to create a task
nats request --server nats://localhost:54222 \
  gtd.task.create \
  '{
    "name": "First Bot Army Task",
    "description": "Learn how bots communicate via NATS",
    "status": "pending"
  }' \
  --timeout 3s
```

You should see a JSON response with:
```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "First Bot Army Task",
  "created_at": "2026-05-27T...",
  "status": "pending"
}
```

**What you learned:** Bots communicate via NATS pub/sub with JSON messages. The GTD bot listened on `gtd.task.create`, processed your request, and replied.

### Option B: Via Dashboard

```bash
make dashboard
```

**In the dashboard:**
1. Press `1` to go to **Fleet** tab
2. Press `Tab` to go to **Logs** tab
3. You'll see bot activity in real-time

Press `q` to quit.

---

## Demo 3: Ask Claude a Question (5 min)

### Option A: Via Claude Desktop

If you've set up Claude Desktop (`make claude-integrate`):

1. Open Claude Desktop
2. Ask: **"What tasks do I have in my GTD?"**
3. Claude queries `bridge.task.list` and shows your tasks

### Option B: Via Command Line

```bash
# If you created a task in Demo 2, list all tasks
nats request --server nats://localhost:54222 \
  gtd.task.list \
  '{}' \
  --timeout 3s
```

Response: JSON array of your tasks

### Option C: Via the GTD TUI (if available)

```bash
# If GTD TUI is in your fleet, launch it
# (Check your dashboard or docker compose ps)
```

**What you learned:** 
- Bots expose subjects like `gtd.task.list` that other services can query
- Claude can call these subjects to understand your system
- Data flows through NATS, not files or REST APIs

---

## Demo 4: Understand PARA (Your Knowledge Base) (3 min)

PARA is your personal notes system (Projects, Areas, Resources, Archive).

### View your PARA directory

```bash
# Bots write here
ls ~/data/para/

# You should see:
# inbox/     - Quick captures
# projects/  - Active work
# areas/     - Ongoing responsibilities
# resources/ - Reference material
# archive/   - Completed items
```

### Add a note directly

```bash
# Create a quick note
cat > ~/data/para/projects/my-first-note.md << 'EOF'
# My First Bot Army Project

- Learn how bots work
- Try NATS commands
- Set up Claude

**Status:** In Progress
EOF

# Claude can now query this
# "Show me my notes about bot army"
# → Claude reads ~/data/para/ and finds this note
```

### Customize PARA location

By default, PARA lives in `~/data/para/`. To use your own folder:

```bash
# See the guide
make help-volumes

# TL;DR: Edit .env and docker-compose.yml
PARA_DIR=/Users/abby/Documents/knowledge
```

**What you learned:**
- PARA is filesystem-based (accessible from any tool)
- Other bots can read/write to PARA
- You own your data (not locked in a database)

---

## Demo 5: Monitor Bots in Real Time (2 min)

Every bot sends a heartbeat to `system.health` every 30 minutes. Watch them:

```bash
# Subscribe to health beacons
nats subscribe --server nats://localhost:54222 system.health &

# Start bots if they're not running
docker compose up -d

# Wait 10 seconds, you'll see messages like:
# [#1] Received on "system.health": {"service":"gtd","status":"healthy",...}
# [#2] Received on "system.health": {"service":"llm","status":"healthy",...}

# Press Ctrl+C to stop listening
```

Or use the **Dashboard** for a visual view:

```bash
make dashboard
# Press 1 (Fleet tab) to see bot health with colors:
# ● green = healthy
# ◐ yellow = degraded/running
# ○ red = offline
```

**What you learned:**
- All bots report health via NATS
- The system is observable (you can see what's happening)
- Dashboard provides real-time monitoring

---

## What Happens Next?

Now that you've tried basic commands, here are your paths:

### Path 1: Integrate with Claude 💬
```bash
make claude-integrate
# Now Claude can read/write your GTD tasks directly
```

### Path 2: Create Your Own Bot 🤖
```bash
make help-create-bot
# Build a custom bot from the template
```

### Path 3: Configure Your Storage 📁
```bash
make help-volumes
# Use your own Documents folder for PARA
```

### Path 4: Troubleshoot & Debug 🔧
```bash
make help-troubleshoot
# Common issues and how to fix them
```

---

## Key Concepts

### NATS (Message Bus)
All communication flows through NATS on port **54222** (dev) or **4222** (prod).

**Example:**
- You send `gtd.task.create` request
- GTD bot subscribes to that subject
- GTD bot processes and replies
- You receive the response

### Subjects
Organized like filepaths: `service.domain.action`

Examples:
```
gtd.task.create       - Create a task
gtd.task.list         - List tasks
system.health         - Health beacon
bridge.task.*         - Claude's access to GTD
```

### Bots
Each bot:
1. Subscribes to subjects (listens for requests)
2. Processes messages (does work)
3. Replies via embedded reply subject
4. Publishes events (tells others what happened)
5. Reports health (heartbeat every 30 min)

### Storage
- **PostgreSQL** - Persistent data (tasks, state)
- **PARA** (`~/data/para/`) - Personal knowledge base
- **Volumes** - Mounted to containers (`docker-compose.yml`)

---

## Next: Deeper Exploration

### Learn More
- **System architecture:** `docs/` folder has detailed guides
- **Create a bot:** `make help-create-bot`
- **Custom storage:** `make help-volumes`
- **Troubleshooting:** `make help-troubleshoot`
- **Claude integration:** `make claude-integrate`

### Try Advanced Examples

**Example 1: Bot-to-bot communication**
```bash
# Bots publish events that other bots subscribe to
# E.g., GTD bot publishes when task changes
# Synapse bot subscribes and posts to Discord

# Create a task and watch it ripple through the system
nats request gtd.task.create \
  '{"name":"Watch bots talk to each other"}' \
  --timeout 3s

# Watch events in real-time
nats subscribe gtd.events.>

# Now update the task via Claude or TUI
# You'll see events flow through NATS
```

**Example 2: Multi-step workflows**
```bash
# Create task → Ask Claude to decompose → Get subtasks
# All via NATS, no manual steps

# Try from Claude Desktop:
# "Create a task called 'Deploy bot-army' and decompose it"
```

**Example 3: Use Claude Code for development**
```bash
make help-create-bot
# Follow tutorial to create bot_army_experiment
make add-local BOT_PATH=/path/to/bot_army_experiment
docker compose up -d --build
# Now your bot is live and can receive requests
```

---

## Common Questions

**Q: Where are my tasks stored?**
A: PostgreSQL database (persistent, not deleted on restart). Volume mounted at `~/data/postgres/`.

**Q: Can I export my tasks?**
A: Yes! Query GTD bot, convert JSON to CSV/Markdown/whatever you want.

**Q: What's the difference between PARA and GTD tasks?**
A: GTD tasks are tracked in the system (deadlines, status). PARA is your notes (no automation).

**Q: Can I run this without Docker?**
A: Not easily. Docker keeps the system portable. But you could run Elixir/Erlang directly if needed.

**Q: How do I back up my data?**
A: Your data lives in `~/data/`. Back it up like any folder. Or use Git + PostgreSQL dumps.

---

## You're Ready!

You now understand:
- ✅ How NATS messaging works
- ✅ How to create tasks
- ✅ How bots receive and reply to requests
- ✅ How to monitor bot health
- ✅ Where your data lives (PARA + PostgreSQL)

**Next step:** Pick a path (Claude, custom bot, storage, or troubleshooting) and dive deeper!

---

## Going Further?

Once you've mastered the basics, you might want:
- **Enterprise bots** with complex workflows and compliance requirements
- **Industry-specific templates** (sales, HR, finance, customer support)
- **Multi-tenant systems** for teams or customers
- **Production deployment** with high availability and security
- **Expert guidance** on architecture and optimization

**[Ergon Automation Labs](https://ergon-automation-labs.com)** specializes in building sophisticated bots and scaling Bot Army for enterprise use.

**[Get in touch](mailto:contact@ergon-automation-labs.com)** to discuss your next project.
