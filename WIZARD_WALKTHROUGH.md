# Bot Army Wizard - Interactive Walkthrough

This document shows what users will experience when running `./bot-army init`.

## Overview

The wizard guides new users through 10 steps to configure their Bot Army system:
1. ✅ Select a Starter Pack (or custom)
2. ✅ Select Individual Bots
3. ✅ Configure Integration Flags
4. ✅ Configure Network Ports
5. ⚙️ GitHub Integration (optional)
6. ✅ Select LLM Provider
7. ✅ Environment Variables (optional)
8. ✅ Terminal Context Helper (optional)
9. ✅ Custom Volume Mounts (optional)
10. ✅ Review & Confirm

Each step includes **inline help text** explaining the purpose, examples, and why the user should care.

---

## Step 1: Select a Starter Pack

```
╔════════════════════════════════════════════════════════════════╗
║                       Bot Army Starter                         ║
║  ●●●●○○  Step 1/6                                             ║
╠════════════════════════════════════════════════════════════════╣
║ 💡 What are Starter Packs?                                     ║
║ Packs are pre-configured bundles of bots with common           ║
║ integrations.                                                  ║
║ • Core           Essential system (GTD, LLM, Dispatcher, PARA) ║
║ • Social Media   Core + Discord/Synapse integration           ║
║ • Learning       Core + Learning bot for research             ║
║ • Areas          Core + Area-specific bots                    ║
║ • Research       Core + Research tools                        ║
║ • Custom         Pick individual bots yourself                ║
║                                                                ║
║ [ ] Core                                                       ║
║ [✓] Social Media  (synapse · notification_router · ...)      ║
║ [ ] Learning                                                   ║
║ [ ] Areas                                                      ║
║ [ ] Research                                                   ║
║ [ ] Custom                                                     ║
╠════════════════════════════════════════════════════════════════╣
║ ↑↓:nav  Space:toggle  s:skip  Enter:next  Esc:cancel  q:quit  ║
╚════════════════════════════════════════════════════════════════╝
```

**What user sees:**
- Clear explanation of what packs are
- Visual examples of what's included in each
- Easy toggle selection with Space bar
- Can select multiple packs or skip for custom mode

---

## Step 2: Select Individual Bots

```
╔════════════════════════════════════════════════════════════════╗
║                       Bot Army Starter                         ║
║  ●●●●●○  Step 2/6                                             ║
╠════════════════════════════════════════════════════════════════╣
║ 💡 About Bots                                                  ║
║ Each bot is a specialized service that handles a specific      ║
║ function.                                                      ║
║ • Core bots      Always required (GTD, LLM, Dispatcher, ...)  ║
║ • Pack bots      Included if you selected a pack above        ║
║ • Toggle to add/remove optional bots to customize your system ║
║                                                                ║
║ [✓] (required) gtd_bot                                [core]   ║
║ [✓] (required) llm_bot                                [core]   ║
║ [✓] llm_proxy                                         [core]   ║
║ [✓] dispatcher_bot                                    [core]   ║
║ [✓] synapse_bot                                   [social]     ║
║ [ ] fitness_bot                                                ║
║ [✓] para_bot                                         [core]    ║
║ [ ] youtube_manager_bot                                        ║
║ [✓] notification_router_bot                      [social]      ║
╠════════════════════════════════════════════════════════════════╣
║ ↑↓:nav  Space:toggle  Enter:next  Esc:cancel  q:quit          ║
╚════════════════════════════════════════════════════════════════╝
```

**What user sees:**
- Explanation of bot types
- Core bots are locked (shown with gray checkmark)
- Pack bots are selected automatically
- Can toggle optional bots like fitness, youtube_manager, etc.

---

## Step 3: Configure Integration Flags

```
╔════════════════════════════════════════════════════════════════╗
║                       Bot Army Starter                         ║
║  ●●●●●●  Step 3/6                                             ║
╠════════════════════════════════════════════════════════════════╣
║ 💡 About Integrations                                          ║
║ Some features are optional and only needed if you use certain  ║
║ bots.                                                          ║
║ • Greyed items    Required (always enabled, can't be changed)  ║
║ • Green items     Enabled because you selected a bot that     ║
║                   needs them                                   ║
║ • Empty items     Disabled (toggle with Space to override)    ║
║ You can disable integrations to reduce resource usage.         ║
║                                                                ║
║ [✓] (required) GTD - Task management system (always required)  ║
║ [✓] BRIDGE - Claude bridge - Central AI interface             ║
║ [✓] LLM - LLM Services - AI/ML processing                     ║
║ [✓] PARA - PARA System - Knowledge persistence                ║
║ [✓] CONTEXT - Context Broker - System state queries           ║
║ [✓] NOTIFICATION - Notifications - User alerts and messages   ║
║ [✓] SYNAPSE - Synapse - Discord/social integration            ║
║ [ ] DISPATCHER - Dispatcher - AI orchestration                 ║
╠════════════════════════════════════════════════════════════════╣
║ ↑↓:nav  Space:toggle  Enter:next  Esc:cancel                  ║
╚════════════════════════════════════════════════════════════════╝
```

**What user sees:**
- Explanation of automatic detection
- Why integrations matter
- Green items are auto-enabled (required by selected bots)
- Can toggle to disable optional ones if needed
- GTD always enabled (core system)

---

## Step 4: Configure Ports

```
╔════════════════════════════════════════════════════════════════╗
║                       Bot Army Starter                         ║
║  ●●●●●●  Step 4/6                                             ║
╠════════════════════════════════════════════════════════════════╣
║ 💡 About Ports                                                 ║
║ These are the TCP ports on your computer where services will   ║
║ listen.                                                        ║
║ • NATS (4222)          Message broker - how bots communicate   ║
║ • Postgres (5432)      Database - where bot data is stored    ║
║ • Ollama (11434)       Local LLM - only if using self-hosted   ║
║ • MCP Server (39900)   Claude Desktop integration port         ║
║ Change if you have other services using these ports.           ║
║                                                                ║
║ NATS port          54222                                       ║
║ NATS monitor port  58222                                       ║
║ PostgreSQL port    55432                                       ║
║ Ollama port        51434                                       ║
║ MCP server port    39900                                       ║
║ Docker registry    32000                                       ║
║                                                                ║
║ [ Next ]  [ Cancel ]                                           ║
╠════════════════════════════════════════════════════════════════╣
║ Enter:save  Esc:cancel                                         ║
╚════════════════════════════════════════════════════════════════╝
```

**What user sees:**
- Clear explanation of what each port does
- Examples of when to change (if ports are in use)
- Sensible defaults shown
- Easy edit fields to customize

---

## Step 5: GitHub Integration (Optional - conditional)

```
╔════════════════════════════════════════════════════════════════╗
║                       Bot Army Starter                         ║
║  ●●●●●●  Step 5/6                                             ║
╠════════════════════════════════════════════════════════════════╣
║ 💡 GitHub Integration (Optional)                               ║
║ Token    A GitHub personal access token for private repo       ║
║          access                                                ║
║ Secret   A random string to secure GitHub webhooks             ║
║          (min 8 characters)                                    ║
║ Leave blank to skip GitHub integration. You can add it later.  ║
║                                                                ║
║ GitHub Token (ghp_...)        _______________________________  ║
║ Webhook Secret (min 8 chars)  _______________________________  ║
║                                                                ║
║ [ Save & Continue ]  [ Skip ]                                  ║
╠════════════════════════════════════════════════════════════════╣
║ Enter:save  Esc:skip  GitHub webhook is optional              ║
╚════════════════════════════════════════════════════════════════╝
```

**What user sees:**
- Optional step (only if github_bot selected)
- Token and secret explained
- Clear that it's optional
- Can skip and add later

---

## Step 6: Select LLM Providers

```
╔════════════════════════════════════════════════════════════════╗
║                       Bot Army Starter                         ║
║  ●●●●●●  Step 6/6                                             ║
╠════════════════════════════════════════════════════════════════╣
║ 💡 LLM Providers                                               ║
║ These are AI services that power Bot Army's intelligent        ║
║ features.                                                      ║
║ • Ollama        Free, local AI model (recommended for learning)║
║ • OpenRouter    Access to many models via single API (Claude)  ║
║ • Anthropic     Official Claude API for production use         ║
║ You can select multiple providers - the first available will   ║
║ be used.                                                       ║
║                                                                ║
║ [✓] Ollama                                                     ║
║ [✓] OpenRouter                                                 ║
║ [ ] Anthropic                                                  ║
╠════════════════════════════════════════════════════════════════╣
║ ↑↓:nav  Space:toggle  Enter:next  Esc:cancel  q:quit          ║
╚════════════════════════════════════════════════════════════════╝
```

**What user sees:**
- Explanation of LLM providers
- Pros/cons of each (free local vs API)
- Can select multiple (failover chain)
- Guided selection helps new users

---

## Step 7: Environment Variables (Optional)

```
╔════════════════════════════════════════════════════════════════╗
║                       Bot Army Starter                         ║
║  ●●●●●●  Step 7/6                                             ║
╠════════════════════════════════════════════════════════════════╣
║ 💡 Environment Variables                                       ║
║ Optional settings for advanced customization (leave blank for  ║
║ defaults).                                                     ║
║ • API Keys          Credentials for external services         ║
║ • Feature Flags     Enable/disable specific features          ║
║ • Timeouts          Customize response wait times             ║
║ Most users can skip this step and use defaults.               ║
║                                                                ║
║ OPENROUTER_API_KEY  _______________________________             ║
║ LOG_LEVEL           [debug ▼]                                 ║
║                                                                ║
║ [ Save ]  [ Skip ]                                             ║
╠════════════════════════════════════════════════════════════════╣
║ Enter:save  Esc:skip                                           ║
╚════════════════════════════════════════════════════════════════╝
```

**What user sees:**
- Advanced customization (clearly optional)
- Shows common env vars
- Guidance that most users skip this
- Defaults are sensible

---

## Step 8: Terminal Context Helper (Optional)

```
╔════════════════════════════════════════════════════════════════╗
║                       Bot Army Starter                         ║
║  ●●●●●●  Step 8/6                                             ║
╠════════════════════════════════════════════════════════════════╣
║ 💡 Terminal Context Helper (Optional)                          ║
║ bot-army-shell adds context awareness to your terminal.        ║
║ • Ctrl+B menu          Quick access to Bot Army commands and   ║
║                        status                                  ║
║ • Auto-detection       Detects when you enter bot directories ║
║ • Smart suggestions    Recommends relevant operations         ║
║ You can install this later via make shell-install.             ║
║                                                                ║
║ [✓] Install bot-army-shell - Enable context-aware prompts     ║
║ [ ] Skip - Install only core bots                             ║
╠════════════════════════════════════════════════════════════════╣
║ Space:toggle  Enter:save  Esc:cancel                           ║
╚════════════════════════════════════════════════════════════════╝
```

**What user sees:**
- Optional enhancement explained
- Features clearly listed
- Can install later (not blocking)
- Helps users understand shell integration

---

## Step 9: Custom Volume Mounts (NEW)

```
╔════════════════════════════════════════════════════════════════╗
║                       Bot Army Starter                         ║
║  ●●●●●●  Step 9/6                                             ║
╠════════════════════════════════════════════════════════════════╣
║ 💡 Custom Volume Mounts                                        ║
║ Volumes let containers access your computer's files and        ║
║ folders.                                                       ║
║ • Host Path           Full path on your computer               ║
║                       (e.g., /Users/you/projects)             ║
║ • Container Path      Where it appears inside the container    ║
║                       (e.g., /projects)                       ║
║ Examples:                                                      ║
║   /Users/you/data → /data           Share a data folder       ║
║   /Users/you/.ssh → /root/.ssh      Share SSH keys for git    ║
║ Leave empty to skip. You can add more volumes later by         ║
║ editing docker-compose.yml.                                    ║
║                                                                ║
║ Host Path               /Users/abby/datasets                   ║
║ Container Path          /data                                  ║
║                                                                ║
║ [ Add Mount ]  [ Skip ]                                        ║
╠════════════════════════════════════════════════════════════════╣
║ Tab:next field  Enter:add  Esc:skip                            ║
╚════════════════════════════════════════════════════════════════╝
```

**What user sees:**
- NEW feature for mounting directories
- Clear examples of common use cases
- Optional - can skip or edit later
- Integrated into docker-compose generation

---

## Step 10: Review & Confirm

```
╔════════════════════════════════════════════════════════════════╗
║                       Bot Army Starter                         ║
║  ●●●●●●  Step 10/6                                            ║
╠════════════════════════════════════════════════════════════════╣
║ 💡 Review Your Configuration                                   ║
║ This is your final chance to review all settings before        ║
║ creating docker-compose.yml.                                   ║
║ ✓ Press Enter to create the configuration and start Bot Army  ║
║ ✗ Press Esc to go back and make changes                        ║
║                                                                ║
║ [yellow]Bot Army Starter Configuration[-]                     ║
║                                                                ║
║ [cyan]Selected Packs[-]                                        ║
║   • social-media                                               ║
║                                                                ║
║ [cyan]Selected Bots[-]                                         ║
║   • gtd_bot (v0.7.150)                                         ║
║   • llm_bot (v0.6.95)                                          ║
║   • synapse_bot (v0.9.20)                                      ║
║   • notification_router_bot (v0.2.5)                           ║
║   ... (8 more)                                                 ║
║                                                                ║
║ [cyan]Integration Flags[-]                                     ║
║   7 of 8 integrations enabled                                  ║
║                                                                ║
║ [cyan]Host Ports[-]                                            ║
║   NATS: 54222                                                  ║
║   PostgreSQL: 55432                                            ║
║                                                                ║
║ [cyan]Custom Volume Mounts[-]                                  ║
║   • /Users/abby/datasets → /data                               ║
║                                                                ║
║ [cyan]LLM Providers[-]                                         ║
║   • Ollama                                                     ║
║   • OpenRouter                                                 ║
║                                                                ║
║ [green]Press Enter to start setup or Esc to go back[-]         ║
╠════════════════════════════════════════════════════════════════╣
║ Enter:start setup  Esc:back  q:quit                            ║
╚════════════════════════════════════════════════════════════════╝
```

**What user sees:**
- Complete summary of all choices
- Shows custom volume mount (NEW)
- Shows integration flags summary
- Final confirmation before creating files
- Can go back to change anything

---

## Key User Experience Improvements

### For Complete Beginners

✅ **Every screen has help text** explaining purpose and options
✅ **Examples provided** for common scenarios
✅ **Guidance on what's required vs optional** (green help text)
✅ **Clear navigation hints** (↑↓:nav, Space:toggle, Enter:next)

### For Experienced Users

✅ **Quick mode** - press Enter through defaults
✅ **Skip optional steps** easily with Esc
✅ **Customize as needed** - ports, env vars, custom mounts
✅ **Flexible** - can edit docker-compose.yml after setup

### For All Users

✅ **Help text is always visible** - no need to memorize
✅ **Review step** lets you verify everything before applying
✅ **Custom volume mounts** now integrated during setup
✅ **Sensible defaults** for everything

---

## Running the Wizard

```bash
cd /Users/abby/code/bot-army-starter

# Run the wizard (interactive TUI)
./bot-army-native init

# Or build first if needed
make build-native
./bot-army-native init
```

### What Gets Created

After completing the wizard:

```
.
├── .bot-army.json           # Your configuration (can re-run wizard)
├── .env                     # Environment variables (for docker-compose)
├── docker-compose.yml       # Main orchestration file
├── otelcol.yaml            # OpenTelemetry config (if enabled)
├── init-databases.sql      # Database initialization
├── Dockerfile.pack         # Per-pack build definition
├── Makefile                # Operational targets
├── catalog/
│   └── bots.json           # Bot catalog
└── data/
    ├── logs/               # Bot logs
    ├── para/               # PARA system data
    └── state/              # Persistent state
```

Then:

```bash
docker compose up -d --build
```

Your Bot Army system is running! 🚀
