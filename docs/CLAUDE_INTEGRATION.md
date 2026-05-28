# Claude Desktop & Claude Code Integration

After running `make quickstart`, integrate your Bot Army ecosystem with Claude Desktop and Claude Code for AI-assisted development and task management.

## Overview

Bot Army exposes its capabilities via **MCP (Model Context Protocol)** servers:

- **Claude Desktop** — Claude can read/write to your GTD tasks, search logs, query the knowledge graph
- **Claude Code** — CLI tool for rapid development, fully integrated with Bot Army's NATS/Bridge API

## Claude Desktop Setup

### 1. Install Claude Desktop

Download from [claude.ai/download](https://claude.ai/download) and install.

### 2. Configure MCP Servers

Claude Desktop reads MCP server configs from (macOS) `~/Library/Application Support/Claude/claude_desktop_config.json`. Add your Bot Army bridge:

```json
{
  "mcpServers": {
    "bot-army": {
      "url": "http://localhost:39900/mcp"
    }
  }
}
```

**Note:** Port `39900` is the default MCP host port. If you changed it during `make quickstart`, use that value instead.

### 3. Restart Claude Desktop

Close and reopen Claude Desktop. You should see a **🤖 Bot Army** badge in the toolbar once connected.

### 4. What You Can Do

Once connected, Claude can:

**Task Management (GTD)**
- `bridge.task.list` — List all tasks with status
- `bridge.task.create` — Create new tasks
- `bridge.task.update` — Update task status, decomposition, notes
- `bridge.task.get` — Fetch a specific task

**Knowledge Graph**
- `bridge.graph.query` — Query codebase structure, dependencies, architecture

**Logs & Debugging**
- `bridge.logs.search` — Search bot logs by query
- `bridge.system.health` — Check bot health status

**Examples:**
```
Claude: "Create a GTD task for implementing the new auth flow"
→ Uses bridge.task.create, returns task_id

Claude: "Show me recent errors in the GTD bot"
→ Uses bridge.logs.search, shows filtered logs

Claude: "What's the dependency graph for bot_army_runtime?"
→ Uses bridge.graph.query, shows architecture
```

## Claude Code Setup

Claude Code is a terminal-based IDE interface. It's deeply integrated with Bot Army.

### 1. Install Claude Code CLI

```bash
# If using Claude Code from the desktop app or web:
# It's built-in. For CLI:
curl -s https://claude.ai/claude-code | bash
# Or use your system's package manager
```

### 2. Launch Claude Code in Your Bot Army Directory

```bash
cd /Users/abby/code/bot-army-starter
claude code
# Or from any bot repo:
cd /Users/abby/code/elixir_bots/bot_army_gtd
claude code
```

### 3. Using Skills (MCP Tools)

Claude Code has access to **skills** — specialized MCP tools for common Bot Army tasks:

#### Available Skills

| Skill | What it does | Trigger |
|-------|-------------|---------|
| `graphify` | Index/query codebase knowledge graph | `/graphify` |
| `synapse-gtd-create-safe` | Safely create GTD tasks via Synapse | `/synapse-gtd-create-safe` |
| `nats-websocket` | Test NATS connectivity and pub/sub | `/nats-websocket` |

#### Using a Skill

In Claude Code, type the skill name with `/`:

```
/graphify

→ Indexes the codebase and creates knowledge graph
→ Returns graph structure, architecture, dependencies

---

/synapse-gtd-create-safe

→ Safely creates GTD tasks via Synapse bridge
→ Validates NATS connectivity first
→ Returns task_id on success
```

### 4. Common Workflows

**Add a new feature to a bot:**
```bash
cd /Users/abby/code/elixir_bots/bot_army_gtd
claude code

# In Claude Code:
/graphify
# → Understand current structure

# Ask Claude to implement feature...
# Claude modifies code, runs tests

make test
```

**Debug a failing test:**
```bash
cd /Users/abby/code/elixir_bots/bot_army_gtd
claude code

# Show failing test output
cat test_output.txt

# Ask Claude to fix...
# Claude reads test, suggests fixes, implements

make test
```

**Create a GTD task from Discord:**
```
# In Discord #operations channel:
@claude "Claude, create a GTD task: implement voice capture feature"

→ Claude uses bridge.task.create (routed through Synapse)
→ Task appears in GTD TUI immediately
→ You can decompose and work on it
```

## Architecture: How It Works

```
┌─────────────────────────────────────────────────┐
│         Claude Desktop / Claude Code            │
│  (Your AI IDE + task management interface)      │
└────────────────┬────────────────────────────────┘
                 │ MCP Calls
                 ▼
┌─────────────────────────────────────────────────┐
│  Claude Bridge (bot_army_claude_bridge)         │
│  - Exposes bridge.* subjects over NATS          │
│  - Routes to GTD, Synapse, LLM, etc.            │
└────────────────┬────────────────────────────────┘
                 │ NATS Pub/Sub
                 ▼
┌─────────────────────────────────────────────────┐
│           Bot Fleet (Docker)                    │
│  - GTD Bot (task management)                    │
│  - LLM Bot (AI processing)                      │
│  - Synapse (Discord + Discord bridge)           │
│  - Your custom bots...                          │
└─────────────────────────────────────────────────┘
```

**Flow Example: Create GTD Task from Claude Desktop**

1. Claude Desktop → `bridge.task.create` (NATS request)
2. Claude Bridge routes to GTD Bot
3. GTD Bot validates, stores in PostgreSQL
4. Returns `task_id` + metadata
5. Claude Desktop shows confirmation, returns task_id
6. You can now edit/decompose in GTD TUI or Discord

## Troubleshooting

**Claude Desktop doesn't see MCP server:**
```bash
# Check if MCP server is running
curl http://localhost:39900/mcp

# If no response, ensure bots are up:
docker compose ps | grep bridge

# Check NATS port in .env
cat .env | grep NATS
```

**Claude Code can't find a skill:**
```bash
# Skills live in .claude/skills/
ls ~/.claude/skills/

# If missing, reinstall:
git pull origin main
# Skills are version-controlled
```

**NATS connection fails:**
```bash
# Verify NATS is up
nats server check

# Or via Docker:
docker compose ps nats

# Check your .env port matches Claude Desktop config
cat .env | grep NATS_PORT
```

## Next Steps

1. **Open Claude Desktop** and start asking:
   - "What tasks are in my GTD?"
   - "Show me recent errors in the LLM bot"
   - "What's the dependency graph for bot_army_runtime?"

2. **Use Claude Code** to develop features:
   ```bash
   cd /Users/abby/code/elixir_bots/bot_army_gtd
   claude code
   # Ask Claude to add features, run tests, etc.
   ```

3. **Automate via Synapse** (Discord):
   - Mention Claude in Discord: `@claude create a task for X`
   - Claude creates task via bridge.task.create
   - Task appears in GTD and Synapse channels

4. **Monitor via Dashboard**:
   ```bash
   make dashboard
   # Fleet, Logs, NATS, System tabs
   # Real-time bot status
   ```

## Resources

- **[Bot Army Docs](../README.md)** — System overview, architecture
- **[GTD Bot Guide](https://github.com/ergon-automation-labs/bot_army_gtd/blob/main/docs)** — Task management
- **[Claude Bridge Docs](https://github.com/ergon-automation-labs/bot_army_claude_bridge/blob/main/docs)** — MCP contract, available subjects
- **[Synapse Guide](https://github.com/ergon-automation-labs/bot_army_synapse/blob/main/docs)** — Discord integration
