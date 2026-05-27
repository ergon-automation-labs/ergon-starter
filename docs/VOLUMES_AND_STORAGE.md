# Volumes and Persistent Storage

How to configure PARA (your personal knowledge base), internal docs, and persistent bot data.

## Overview

Bot Army uses **Docker volumes** for persistent storage. Two types:

| Type | Purpose | Customizable | Examples |
|------|---------|--------------|----------|
| **Named volumes** | Portable, managed by Docker | Limited | `para:/opt/app/para` |
| **Bind mounts** | Host directory mapped to container | Fully customizable | `/Users/abby/Documents/knowledge:/ opt/app/para` |

You can customize where your **PARA notes** and **internal docs** live, so they're accessible outside Docker and backed up with your other files.

## Quick Setup

By default, `make quickstart` creates:
```
~/data/
├── logs/              (all bot logs)
├── para/              (your notes)
└── state/             (bot state files)
```

To customize this, edit `.env`:

```bash
# Before or after quickstart:
cat .env
```

You'll see:
```env
STARTER_NATS_PORT=54222
STARTER_POSTGRES_PORT=55432
# Volumes configuration (see docs/VOLUMES_AND_STORAGE.md)
```

## PARA: Your Personal Knowledge Base

**PARA** = Projects, Areas, Resources, Archive

The `para` bot reads/writes to `/opt/app/para` inside containers, which maps to your host filesystem.

### Default Setup

After quickstart, your PARA directory is created at:
```
~/data/para/
├── inbox/           (quick captures)
├── projects/        (active projects)
├── areas/           (ongoing areas of focus)
├── resources/       (reference material)
└── archive/         (completed/closed items)
```

**Inside Docker**, bots write here:
```
/opt/app/para/        ← Inside container
```

**On your Mac**, view/edit:
```
~/data/para/          ← Your host machine
```

### Customize PARA Location

To use your own Documents or Notes folder, edit `docker-compose.yml`:

**Before editing, stop everything:**
```bash
docker compose down
```

**Find the volumes section:**
```yaml
services:
  para_bot:
    volumes:
      # Old: named volume (Docker-managed)
      - para:/opt/app/para
      
      # New: bind mount to your folder
      - /Users/abby/Documents/knowledge:/opt/app/para
```

**Or use an environment variable in `.env`:**

Add to `.env`:
```env
PARA_DIR=/Users/abby/Documents/knowledge
```

Then in `docker-compose.yml`:
```yaml
para_bot:
  volumes:
    - ${PARA_DIR}:/opt/app/para
```

**Create the directory on your Mac first:**
```bash
mkdir -p ~/Documents/knowledge
mkdir -p ~/Documents/knowledge/{inbox,projects,areas,resources,archive}
```

**Restart everything:**
```bash
docker compose up -d
```

### Access Your Notes

**From the GTD TUI:**
- Your tasks are stored in PostgreSQL
- Related notes appear in the PARA folders

**From your Mac directly:**
```bash
# Edit notes in your preferred editor
open ~/Documents/knowledge/projects/

# Or from command line
cat ~/Documents/knowledge/projects/myproject.md
```

**From Claude:**
```
Claude: "Show me my PARA resources on machine learning"
→ Uses bridge.para.fs.read to query ~/Documents/knowledge/resources/
→ Returns matching notes
```

**From Python or scripts:**
```python
import os
para_path = os.path.expanduser("~/Documents/knowledge")
projects = [f for f in os.listdir(f"{para_path}/projects")]
# Your notes are accessible from any tool
```

## Internal Docs

**Internal Docs** = Your team's documentation, runbooks, architecture docs.

This is separate from PARA. Create a volume for:
- README files
- Setup guides
- Architecture diagrams
- Incident runbooks
- API documentation

### Setup Internal Docs Volume

In `docker-compose.yml`, add a volume for your docs repo:

```yaml
services:
  # ... existing bots ...
  
  # Named volume for your docs
  internal_docs:
    volumes:
      - internal_docs:/opt/app/internal_docs

volumes:
  internal_docs:
```

Or use a bind mount to your actual docs folder:

```yaml
services:
  internal_docs:
    volumes:
      - /Users/abby/code/my-team-docs:/opt/app/internal_docs
```

### Index and Search Internal Docs

Bot Army includes an **internal docs bot** that indexes your documentation:

```bash
# The wizard will ask if you want to enable internal_docs
# If you selected it, it's already configured

# Verify it's running
docker compose logs internal_docs_bot | grep "indexed"
```

**Search your docs from Claude:**
```
Claude: "Show me the incident runbook for database failover"
→ Searches /opt/app/internal_docs/
→ Returns matching runbook
```

**Build the index manually:**
```bash
# Force a re-index of your docs
docker compose exec internal_docs_bot \
  ./bin/internal_docs_bot eval \
  "BotArmyInternalDocs.Indexer.reindex()"
```

## Custom Bot Volumes

If you're creating a custom bot that needs persistent data, add volumes to its `docker-compose.yml`:

```yaml
services:
  mybot_bot:
    image: mybot:latest
    volumes:
      # Your data directory
      - mybot_data:/opt/app/data
      
      # Or bind mount to your host
      - /Users/abby/code/mybot/data:/opt/app/data
      
      # Shared PARA
      - para:/opt/app/para

volumes:
  mybot_data:
```

Then in your bot code:

```elixir
def get_data_path do
  System.get_env("DATA_PATH") || "/opt/app/data"
end

def read_file(filename) do
  path = Path.join(get_data_path(), filename)
  File.read(path)
end
```

## Full Customization Example

Here's a complete `.env` and `docker-compose.yml` setup:

### `.env`
```env
# Ports
STARTER_NATS_PORT=54222
STARTER_POSTGRES_PORT=55432

# Custom volume paths (edit these!)
PARA_DIR=/Users/abby/Documents/knowledge
LOGS_DIR=/Users/abby/code/bot-army-logs
STATE_DIR=/Users/abby/code/bot-army-state
INTERNAL_DOCS_DIR=/Users/abby/code/team-docs
```

### `docker-compose.yml` (services section)
```yaml
services:
  para_bot:
    image: workspace-para_bot:latest
    volumes:
      - ${PARA_DIR}:/opt/app/para
      
  gtd_bot:
    image: workspace-gtd_bot:latest
    volumes:
      - ${PARA_DIR}:/opt/app/para
      - ${STATE_DIR}:/opt/app/state
      
  internal_docs_bot:
    image: workspace-internal_docs_bot:latest
    volumes:
      - ${INTERNAL_DOCS_DIR}:/opt/app/internal_docs
      - ${STATE_DIR}/internal_docs:/opt/app/state
      
  # ... other services ...

volumes:
  # Keep named volumes for portability, but reference env vars
  # (docker-compose automatically creates these)
```

## Backup Your Data

Since everything lives on your Mac, back it up with your regular tools:

```bash
# Time Machine (automatic on macOS)
# ~/Documents/knowledge/ is included

# Or manual backup
cp -r ~/Documents/knowledge ~/Documents/knowledge.backup.$(date +%Y%m%d)

# Or sync to GitHub (for docs)
cd ~/code/team-docs
git add .
git commit -m "daily backup"
git push
```

## Troubleshooting

**PARA folder is empty after starting bots:**
```bash
# Check the volume is mounted correctly
docker inspect workspace-para_bot | grep -A 10 Mounts

# Should show your path, not a named volume
```

**Permission denied when writing to PARA:**
```bash
# Docker container is running as root, your Mac user owns the folder
# Fix:
chmod -R 777 ~/Documents/knowledge

# Better: use the docker-compose USER setting
# (add to docker-compose.yml)
```

**Internal docs bot isn't indexing:**
```bash
# Check if it's running
docker compose ps internal_docs_bot

# Check logs
docker compose logs internal_docs_bot -f

# Force re-index
docker compose restart internal_docs_bot
```

**Can't access docs from Claude:**
```bash
# Verify internal_docs bot is in your fleet
docker compose ps | grep internal_docs

# Check if it's registered with the bridge
nats request --server nats://localhost:54222 \
  bridge.internal_docs.query '{"path":"runbooks"}' \
  --timeout 3s

# If no responder, the bot might not be running
```

## Advanced: Symbolic Links

You can link folders to organize better:

```bash
# Link your Obsidian vault as PARA
ln -s /Users/abby/Obsidian/vault ~/data/para

# Link your team wiki as internal docs
ln -s /Users/abby/code/team-wiki ~/data/internal_docs
```

Then tell Docker to use `~/data/para` instead of the full path.

## Advanced: Selective Sync

If you want PARA synced to iCloud/Dropbox but internal_docs on local disk only:

```env
PARA_DIR=/Users/abby/iCloud\ Drive/Documents/knowledge
INTERNAL_DOCS_DIR=/Users/abby/code/team-docs  # Local only
```

Now:
- PARA syncs automatically (iCloud)
- Internal docs stays local (faster)
- Both accessible from Claude and bots

## Next Steps

1. **Run quickstart** and let it create default volumes:
   ```bash
   make quickstart
   ```

2. **View your PARA directory**:
   ```bash
   ls ~/data/para/
   ```

3. **Customize locations** (optional):
   - Edit `.env` with your preferred paths
   - Create those directories on your Mac
   - Update `docker-compose.yml` with bind mounts
   - Restart: `docker compose down && docker compose up -d`

4. **Access from Claude**:
   ```bash
   make claude-integrate
   # Then ask Claude about your notes
   ```

5. **Set up backups**:
   ```bash
   # Add ~/data/para to Time Machine or git
   ```
