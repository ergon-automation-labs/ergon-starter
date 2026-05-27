# Environment Variables Reference

Complete guide to all configurable settings in Bot Army Starter.

## Quick Reference

| Variable | Default | Purpose |
|----------|---------|---------|
| `NATS_SERVERS` | `nats://nats:4222` | NATS cluster URLs |
| `POSTGRES_HOST` | `postgres` | Database hostname |
| `POSTGRES_DB` | `bot_army` | Database name prefix |
| `POSTGRES_USER` | `postgres` | Database username |
| `POSTGRES_PASSWORD` | (required) | Database password |
| `POSTGRES_PORT` | `5432` | Database port |
| `OLLAMA_URL` | `http://ollama:11434` | Local LLM endpoint |
| `ANTHROPIC_API_KEY` | (optional) | Claude API key |
| `OPENAI_API_KEY` | (optional) | OpenAI API key |
| `OPENROUTER_API_KEY` | (optional) | OpenRouter API key |
| `LOG_LEVEL` | `info` | Logging verbosity |
| `PARA_DIR` | `~/data/para/` | Knowledge base path |

## NATS Configuration

### NATS_SERVERS
**Type:** String (comma-separated URLs)

**Default:** `nats://nats:4222`

**Examples:**
```bash
# Single server (default, in docker-compose)
NATS_SERVERS=nats://nats:4222

# Dev/test (local)
NATS_SERVERS=nats://localhost:4223

# Multiple servers (HA cluster)
NATS_SERVERS=nats://primary:4222,nats://secondary:4222,nats://backup:4222

# With authentication
NATS_SERVERS=nats://user:password@nats:4222

# TLS (production)
NATS_SERVERS=nats://nats:4222?tls=true
```

**When to change:**
- Using a remote NATS cluster
- Setting up multiple Docker networks
- Production with authentication/TLS

### NATS_MAX_RECONNECTS
**Type:** Integer

**Default:** `10`

**Purpose:** How many times to retry connecting to NATS before giving up

**Example:**
```bash
NATS_MAX_RECONNECTS=30  # Retry more aggressively
```

### NATS_RECONNECT_WAIT_MS
**Type:** Integer (milliseconds)

**Default:** `2000`

**Purpose:** Wait time between reconnection attempts

**Example:**
```bash
NATS_RECONNECT_WAIT_MS=5000  # Wait 5s between retries
```

## Database Configuration

### POSTGRES_HOST
**Type:** String (hostname or IP)

**Default:** `postgres` (Docker service name)

**Examples:**
```bash
# Docker network (default)
POSTGRES_HOST=postgres

# Local development
POSTGRES_HOST=localhost

# Remote server
POSTGRES_HOST=db.example.com

# Cloud (AWS RDS)
POSTGRES_HOST=my-db.xxxxx.us-east-1.rds.amazonaws.com
```

### POSTGRES_PORT
**Type:** Integer

**Default:** `5432`

**Examples:**
```bash
# Standard
POSTGRES_PORT=5432

# Custom port on same machine
POSTGRES_PORT=5433

# Docker mapping (external → internal)
# If docker-compose has ports: ["5433:5432"]
POSTGRES_PORT=5433
```

### POSTGRES_USER
**Type:** String

**Default:** `postgres`

**Examples:**
```bash
POSTGRES_USER=postgres
POSTGRES_USER=bot_admin
POSTGRES_USER=readonly_user
```

### POSTGRES_PASSWORD
**Type:** String

**Default:** (None, required)

**Security:**
- ⚠️ Never commit to git
- Use `.env` file (gitignored)
- In production, use secrets manager
- Use strong passwords (30+ chars)

**Examples:**
```bash
POSTGRES_PASSWORD=mysecretpassword123!
POSTGRES_PASSWORD=$(openssl rand -base64 32)
```

### POSTGRES_DB
**Type:** String (prefix)

**Default:** `bot_army`

**Purpose:** Prefix for per-bot databases

**How it works:**
- Bot `gtd_bot` creates database: `bot_army_gtd`
- Bot `synapse_bot` creates database: `bot_army_synapse`
- Prefix: `${POSTGRES_DB}_${BOT_NAME}`

**Examples:**
```bash
POSTGRES_DB=bot_army           # Default
POSTGRES_DB=dev                # Staging
POSTGRES_DB=staging            # Prod staging
POSTGRES_DB=prod               # Production
```

### DATABASE_URL (Alternative)
**Type:** Connection string

**Format:** `postgresql://user:password@host:port/dbname`

**Example:**
```bash
DATABASE_URL=postgresql://postgres:secret@localhost:5432/bot_army
```

**When to use:** Some frameworks prefer this instead of individual vars

## LLM Provider Configuration

### OLLAMA_URL
**Type:** URL

**Default:** `http://ollama:11434` (Docker)

**Purpose:** Endpoint for local LLM inference

**Examples:**
```bash
# Docker (default)
OLLAMA_URL=http://ollama:11434

# Local development
OLLAMA_URL=http://localhost:11434

# Remote Ollama server
OLLAMA_URL=http://192.168.1.100:11434
```

**Models available:**
- `llama2` (7B, 13B)
- `mistral` (7B)
- `neural-chat` (7B)
- Check with: `ollama list`

### ANTHROPIC_API_KEY
**Type:** String (secret)

**Default:** (Optional, set only if using Claude)

**Where to get:**
1. Sign up at [console.anthropic.com](https://console.anthropic.com)
2. Create API key in settings
3. Never commit to git

**Example:**
```bash
ANTHROPIC_API_KEY=sk-ant-v0-abcd1234...
```

**Usage:**
- Claude models for heavy reasoning
- Quality: High
- Cost: Per-token (not included in free tier)

### OPENAI_API_KEY
**Type:** String (secret)

**Default:** (Optional)

**Where to get:**
1. Sign up at [platform.openai.com](https://platform.openai.com)
2. Create API key
3. Set billing method

**Example:**
```bash
OPENAI_API_KEY=sk-proj-abcd1234...
```

**Usage:**
- GPT-4, GPT-3.5 models
- Quality: Good
- Cost: Per-token

### OPENROUTER_API_KEY
**Type:** String (secret)

**Default:** (Optional)

**Where to get:**
1. Sign up at [openrouter.ai](https://openrouter.ai)
2. Create API key
3. Add payment method

**Example:**
```bash
OPENROUTER_API_KEY=sk-or-v1-abcd1234...
```

**Usage:**
- Access multiple models (Claude, GPT, Llama, etc.)
- Quality: Varies by model
- Cost: Per-token, cheaper than direct APIs

### LLM_MODEL_HEAVY
**Type:** String (model name)

**Default:** Varies by provider

**Examples:**
```bash
# Using Anthropic
LLM_MODEL_HEAVY=claude-3-opus

# Using OpenAI
LLM_MODEL_HEAVY=gpt-4

# Using Ollama
LLM_MODEL_HEAVY=mistral

# Using OpenRouter
LLM_MODEL_HEAVY=openai/gpt-4
```

**When used:** Complex reasoning, decomposition, analysis

### LLM_MODEL_MEDIUM
**Type:** String (model name)

**Default:** Varies by provider

**Examples:**
```bash
LLM_MODEL_MEDIUM=claude-3-sonnet
LLM_MODEL_MEDIUM=gpt-3.5-turbo
LLM_MODEL_MEDIUM=neural-chat
```

**When used:** Balanced tasks, general queries

### LLM_MODEL_LIGHT
**Type:** String (model name)

**Default:** Varies by provider

**Examples:**
```bash
LLM_MODEL_LIGHT=claude-3-haiku
LLM_MODEL_LIGHT=gpt-3.5-turbo
LLM_MODEL_LIGHT=llama2
```

**When used:** Fast responses, embeddings, summarization

## Storage Configuration

### PARA_DIR
**Type:** Path (absolute)

**Default:** `~/data/para/`

**Purpose:** Personal knowledge base (Projects, Areas, Resources, Archive)

**Examples:**
```bash
# Default home directory
PARA_DIR=/Users/abby/data/para/

# Custom location
PARA_DIR=/Users/abby/Documents/knowledge/

# Shared team location (not recommended)
PARA_DIR=/Volumes/shared/para/

# External disk
PARA_DIR=/Volumes/ExternalDrive/para/
```

**Subdirectories (created automatically):**
```
PARA_DIR/
├── inbox/
├── projects/
├── areas/
├── resources/
└── archive/
```

### DATABASE_DATA_DIR
**Type:** Path (absolute)

**Default:** `~/data/postgres/`

**Purpose:** PostgreSQL persistent data

**Example:**
```bash
DATABASE_DATA_DIR=/Users/abby/data/postgres/
```

### LOGS_DIR
**Type:** Path (absolute)

**Default:** `~/data/logs/`

**Purpose:** Bot application logs

**Example:**
```bash
LOGS_DIR=/Users/abby/data/logs/
```

## Logging Configuration

### LOG_LEVEL
**Type:** String (enum)

**Default:** `info`

**Options:**
- `debug` — Verbose, all details
- `info` — Standard, important events
- `warn` — Warnings only
- `error` — Errors only

**Examples:**
```bash
# Development (see everything)
LOG_LEVEL=debug

# Production (only important)
LOG_LEVEL=warn

# Debugging specific issue
LOG_LEVEL=debug
```

### LOG_FORMAT
**Type:** String (enum)

**Default:** `json` (structured)

**Options:**
- `json` — Machine-readable (default)
- `text` — Human-readable

**Examples:**
```bash
# Structured logging (for parsing)
LOG_FORMAT=json

# Human readable (for watching logs)
LOG_FORMAT=text
```

## Docker Configuration

### COMPOSE_BUILD_PARALLEL
**Type:** Integer

**Default:** `3`

**Purpose:** Number of images to build in parallel

**When to change:**
- Low memory: Set to `1` or `2`
- High-spec machine: Set to `4` or `5`

**Example:**
```bash
# Build one at a time (less memory)
COMPOSE_BUILD_PARALLEL=1

# Build 5 in parallel (faster, needs 16GB+ RAM)
COMPOSE_BUILD_PARALLEL=5
```

### DOCKER_BUILDKIT
**Type:** Boolean (`0` or `1`)

**Default:** `1` (enabled)

**Purpose:** Use modern Docker build system (faster, better caching)

**Example:**
```bash
# Disable if having issues
DOCKER_BUILDKIT=0 docker compose build
```

## Custom Bot Configuration

When adding custom bots, you can set bot-specific env vars:

```yaml
# In docker-compose.yml
services:
  mybot:
    environment:
      # Standard Bot Army
      NATS_SERVERS: nats://nats:4222
      POSTGRES_HOST: postgres
      
      # Custom to your bot
      MY_BOT_API_KEY: secret123
      MY_BOT_TIMEOUT_MS: 5000
      MY_BOT_FEATURES: feature1,feature2
```

## Setting Variables

### Option 1: .env File (Recommended)
Create `.env` in the project root:

```bash
# .env (gitignored)
POSTGRES_PASSWORD=mysecretpassword
ANTHROPIC_API_KEY=sk-ant-v0-...
OPENAI_API_KEY=sk-proj-...
LOG_LEVEL=debug
```

Docker compose automatically loads it.

### Option 2: Command Line
```bash
export POSTGRES_PASSWORD=mysecretpassword
docker compose up -d
```

### Option 3: In docker-compose.yml
```yaml
services:
  nats:
    environment:
      POSTGRES_PASSWORD: mysecretpassword
```

### Option 4: Docker Compose Override
Create `docker-compose.override.yml`:

```yaml
services:
  postgres:
    environment:
      POSTGRES_PASSWORD: dev_password
```

## Secrets Management

**Never commit secrets to git:**
- `.env` is in `.gitignore` ✓
- `docker-compose.yml` without secrets ✓
- Use secrets manager for production ✓

**For production:**

```bash
# AWS Secrets Manager
aws secretsmanager get-secret-value --secret-id bot-army/db-password

# HashiCorp Vault
vault kv get secret/bot-army/postgres

# Kubernetes Secrets
kubectl get secret postgres-credentials -o jsonpath='{.data.password}'
```

## Validation

Check your configuration:

```bash
# See what's set
env | grep -E "NATS_|POSTGRES_|ANTHROPIC_|OPENAI_|LOG_"

# Check .env file
cat .env

# Verify Docker sees it
docker compose config | grep -A 20 "environment:"
```

## Troubleshooting

**"Connection refused" to NATS:**
- Check `NATS_SERVERS` is correct
- Verify NATS container is running: `docker compose ps nats`

**"Unknown database" from PostgreSQL:**
- Check `POSTGRES_HOST`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- Run migrations: `make migrate`

**"API key invalid" from LLM:**
- Check key is copied correctly (no spaces)
- Verify it's set in `.env`: `grep API_KEY .env`
- Try with a new API key (old one might be revoked)

**Timeout connecting to LLM:**
- Check `OLLAMA_URL` is reachable: `curl http://ollama:11434/api/tags`
- For remote Ollama, verify firewall allows access

## Common Configurations

### Development (Local)
```bash
# .env
NATS_SERVERS=nats://localhost:4223
POSTGRES_HOST=localhost
POSTGRES_PASSWORD=dev_password
OLLAMA_URL=http://localhost:11434
LOG_LEVEL=debug
PARA_DIR=~/data/para
```

### Testing (CI/CD)
```bash
# .env.test
NATS_SERVERS=nats://nats:4222
POSTGRES_HOST=postgres
POSTGRES_PASSWORD=test
POSTGRES_DB=bot_army_test
LOG_LEVEL=warn
```

### Production (Cloud)
```bash
# .env.prod (use secrets manager)
NATS_SERVERS=nats://primary.prod.example.com:4222,nats://secondary.prod.example.com:4222
POSTGRES_HOST=db.prod.example.com
POSTGRES_PASSWORD=$(aws secretsmanager get-secret-value ...)
ANTHROPIC_API_KEY=$(aws secretsmanager get-secret-value ...)
LOG_LEVEL=warn
PARA_DIR=/mnt/shared/para
```

### Multi-Tenant SaaS
```bash
# Each customer gets:
POSTGRES_DB=customer_123
PARA_DIR=/data/customers/123/para
NATS_SERVERS=nats://tenant-123.nats.svc.cluster.local:4222
```

## Next Steps

- **See all help:** `make help`
- **Check current settings:** `cat .env` or `docker compose config`
- **Change a variable:** Edit `.env` and restart: `docker compose restart`
- **Troubleshoot issues:** `make help-debugging`
- **Integrate Claude:** `make claude-integrate`
