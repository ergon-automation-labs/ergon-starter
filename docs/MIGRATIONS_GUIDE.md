# Database Migrations Guide

Learn how to manage database schema changes in Bot Army.

## Quick Start

**Run all pending migrations:**
```bash
make migrate
```

**Migrate a specific bot:**
```bash
make migrate BOT=gtd
```

**Check migration status:**
```bash
make migrate-status
```

**Rollback the last migration:**
```bash
make rollback
```

**Rollback multiple steps:**
```bash
make rollback STEPS=2
```

## What Are Migrations?

Migrations are version-controlled changes to your database schema. Instead of manually running SQL, you define changes in code:

```elixir
# priv/repo/migrations/20260527120000_create_tasks.exs
defmodule BotArmyGtd.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :name, :string, null: false
      add :status, :string, default: "pending"
      add :due_date, :date
      timestamps()
    end
  end
end
```

When you run `make migrate`, Ecto:
1. Detects pending migrations
2. Executes them in order
3. Records completion in `schema_migrations` table
4. Allows rollback if needed

**Benefits:**
- ✓ Version control your schema changes
- ✓ Deploy consistently across environments
- ✓ Rollback if something breaks
- ✓ Track what changed and when

## How Bot Army Migrations Work

### Setup (One-time per bot)

Each bot needs a Release module to handle migrations:

**File:** `lib/<bot_name>/release.ex`

```elixir
defmodule BotArmyGtd.Release do
  def migrate do
    load_app()
    for repo <- repos() do
      {:ok, _fun, _state} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
      IO.puts("✓ Migrations complete for #{repo}")
    end
  end

  def rollback(steps \\ 1) do
    load_app()
    for repo <- repos() do
      {:ok, _fun, _state} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, num: steps))
      IO.puts("✓ Rolled back #{steps} step(s) for #{repo}")
    end
  end

  defp repos do
    Application.fetch_env!(:bot_army_gtd, :ecto_repos)
  end

  defp load_app do
    Application.load(:bot_army_gtd)
  end
end
```

**Configuration:** `config/config.exs`

```elixir
config :bot_army_gtd, ecto_repos: [BotArmyGtd.Repo]

config :bot_army_gtd, BotArmyGtd.Repo,
  database: System.get_env("POSTGRES_DB", "bot_army_gtd"),
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  pool_size: 2
```

### Automatic Migrations on Docker Startup

**Dockerfile entrypoint:**

```dockerfile
# scripts/docker-entrypoint.sh
#!/bin/sh
set -e

echo "[$(date)] Creating databases..."
./bin/$BOT_NAME eval 'BotName.Release.create_databases()' || true

echo "[$(date)] Running migrations..."
./bin/$BOT_NAME eval 'BotName.Release.migrate()' || true

echo "[$(date)] Starting bot..."
exec ./bin/$BOT_NAME start
```

This runs automatically when the container starts, so databases and schema are always ready.

## Common Workflows

### Workflow 1: First-Time Setup

When you start Bot Army for the first time:

```bash
# 1. Start services
docker compose up -d

# 2. Wait for containers to be ready
sleep 10

# 3. Run migrations (creates databases + schema)
make migrate

# 4. Verify
make migrate-status
```

Expected output:
```
Running migrations for all bots with databases...

→ Migrating gtd_bot...
✓ Migrations complete

→ Migrating synapse_bot...
✓ Migrations complete

→ Migrating bridge_bot...
✓ Migrations complete

✓ Migrations complete
```

### Workflow 2: Add a New Schema to a Bot

After adding a new table to a bot's code:

**1. Create migration file:**
```bash
cd bot_army_gtd
mix ecto.gen.migration add_projects_table
```

Ecto creates: `priv/repo/migrations/20260527120000_add_projects_table.exs`

**2. Write the migration:**
```elixir
defmodule BotArmyGtd.Repo.Migrations.AddProjectsTable do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false
      add :description, :text
      add :status, :string, default: "active"
      timestamps()
    end
  end
end
```

**3. Test locally:**
```bash
mix ecto.migrate
```

**4. Commit and push:**
```bash
git add priv/repo/migrations/
git commit -m "Add projects table"
git push
```

**5. Deploy (runs automatically on Docker startup):**
```bash
docker compose up -d --build
make migrate  # Or automatic via entrypoint
```

### Workflow 3: Rollback a Failed Migration

If a migration breaks something:

**1. Check status:**
```bash
make migrate-status
```

**2. Rollback the last migration:**
```bash
make rollback BOT=gtd STEPS=1
```

**3. Fix the migration file:**
```bash
# Edit priv/repo/migrations/20260527120000_migration_name.exs
# Fix the bug

# Or delete and recreate if it's wrong
rm priv/repo/migrations/20260527120000_bad_migration.exs
mix ecto.gen.migration fix_migration_name
```

**4. Re-apply:**
```bash
make migrate BOT=gtd
```

### Workflow 4: Modify an Existing Column

**Example: Change a column from nullable to required**

**1. Create migration:**
```bash
cd bot_army_gtd
mix ecto.gen.migration make_task_name_required
```

**2. Write migration:**
```elixir
defmodule BotArmyGtd.Repo.Migrations.MakeTaskNameRequired do
  use Ecto.Migration

  def change do
    # First, set existing NULLs to a default value
    execute("UPDATE tasks SET name = 'Untitled' WHERE name IS NULL")
    
    # Then make the column NOT NULL
    alter table(:tasks) do
      modify :name, :string, null: false
    end
  end
end
```

**3. Test and deploy:**
```bash
mix ecto.migrate
# Test with: mix test
# Then commit and push
make migrate BOT=gtd
```

### Workflow 5: Add a Foreign Key

**Example: Link tasks to projects**

```elixir
defmodule BotArmyGtd.Repo.Migrations.AddProjectToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :project_id, references(:projects, on_delete: :cascade)
    end
  end
end
```

**Deploy:**
```bash
make migrate BOT=gtd
```

## Migration Commands Reference

### make migrate
**Runs all pending migrations for all bots with databases**

```bash
make migrate
```

Output shows which migrations were applied:
```
Running migrations for all bots with databases...
→ Migrating gtd_bot...
✓ Migrations complete
✓ Migrations complete
```

**With specific bot:**
```bash
make migrate BOT=gtd
```

Output:
```
Migrating gtd...
✓ Migrations complete
```

### make rollback
**Undo migrations (default: last 1 step)**

**Rollback all bots:**
```bash
make rollback          # Undo 1 step on all bots
make rollback STEPS=3  # Undo 3 steps on all bots
```

**Rollback specific bot:**
```bash
make rollback BOT=gtd          # Undo 1 step
make rollback BOT=gtd STEPS=2  # Undo 2 steps
```

### make migrate-status
**Show which migrations have been applied**

```bash
make migrate-status
```

Output:
```
Migration status:

→ gtd:
  Applied migrations: 3
  Latest: 20260527120000_create_tasks

→ synapse:
  Applied migrations: 2
  Latest: 20260527110000_create_messages
```

## Creating a Migration

### Step 1: Generate File
```bash
cd bot_army_gtd
mix ecto.gen.migration create_tasks_table
```

Creates: `priv/repo/migrations/20260527_120000_create_tasks_table.exs`

### Step 2: Edit the Migration

**Creating a new table:**
```elixir
defmodule BotArmyGtd.Repo.Migrations.CreateTasksTable do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :name, :string, null: false
      add :description, :text
      add :status, :string, default: "pending"
      add :due_date, :date
      add :priority, :integer, default: 0
      timestamps()                    # Adds inserted_at, updated_at
    end

    create index(:tasks, [:status])   # Speed up queries
  end
end
```

**Modifying a table:**
```elixir
defmodule BotArmyGtd.Repo.Migrations.AddProjectsColumn do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :project_id, references(:projects)
      modify :status, :string, default: "pending"
      remove :old_column
    end
  end
end
```

**Data migration:**
```elixir
defmodule BotArmyGtd.Repo.Migrations.PopulateDefaults do
  use Ecto.Migration

  def change do
    execute("UPDATE tasks SET status = 'pending' WHERE status IS NULL")
  end
end
```

### Step 3: Test
```bash
mix ecto.create
mix ecto.migrate
mix test
```

### Step 4: Commit
```bash
git add priv/repo/migrations/
git commit -m "Add tasks table"
```

## Troubleshooting

### "Database does not exist"
**Error:**
```
** (Postgrex.Error) FATAL 3D000 (invalid_catalog_name) database "bot_army_gtd" does not exist
```

**Fix:**
```bash
# Option 1: Run automatic database creation (via Release task)
docker compose exec gtd_bot /app/bin/gtd_bot eval \
  'BotArmyGtd.Release.create_databases()'

# Option 2: Create manually
docker compose exec postgres createdb -U postgres bot_army_gtd

# Then run migrations
make migrate BOT=gtd
```

### "Migration already applied"
**Error:**
```
Migration cannot be applied: it is not reversible and it is already applied
```

**Fix:**
Don't modify an already-applied migration. Create a new one:

```bash
# Instead of editing the old one:
# OLD: priv/repo/migrations/20260527_120000_create_tasks.exs

# Create a NEW migration:
mix ecto.gen.migration fix_tasks_table
# NEW: priv/repo/migrations/20260527_120100_fix_tasks_table.exs
```

### "Cannot rollback non-reversible migration"
**Error:**
```
** (Ecto.MigrationError) cannot rollback migration that does not have a down
```

**Fix:**
This happens if you used `execute()` without a corresponding down:

```elixir
# ❌ Bad (not reversible)
def change do
  execute("UPDATE tasks SET status = 'done'")
end

# ✅ Good (reversible)
def change do
  execute(
    "UPDATE tasks SET status = 'done'",    # up
    "UPDATE tasks SET status = 'pending'"  # down
  )
end
```

### "Rollback failed"
**Error:**
```
Rollback failed: foreign key constraint violated
```

**Fix:**
If a rollback fails due to constraints, manually fix the data first:

```bash
# Connect to database
docker compose exec postgres psql -U postgres -d bot_army_gtd

# See what's preventing rollback
SELECT * FROM tasks WHERE project_id IS NOT NULL;

# Option 1: Delete the data
DELETE FROM tasks WHERE project_id IS NOT NULL;

# Option 2: Update foreign keys
UPDATE tasks SET project_id = NULL WHERE project_id NOT IN (SELECT id FROM projects);

# Then retry rollback
make rollback BOT=gtd

# Exit psql
\q
```

### "Port already in use"
**Error:**
```
Error response from daemon: Ports are not available: exposing port TCP 0.0.0.0:5432 -> 0.0.0.0:5432: listen tcp 0.0.0.0:5432: bind: address already in use
```

**Fix:**
```bash
# Check what's using the port
lsof -i :5432

# Stop the other container
docker stop <container_name>

# Or use a different port
make up POSTGRES_PORT=5433
```

### "Schema migration table missing"
**Error:**
```
** (DBConnection.ConnectionError) connection refused
```

**Fix:**
```bash
# Ensure database exists
docker compose exec postgres psql -U postgres -c "CREATE DATABASE bot_army_gtd;"

# Run migrations (creates schema_migrations table)
make migrate BOT=gtd
```

## Best Practices

### ✅ Do

- **Create descriptive migration names:**
  ```bash
  mix ecto.gen.migration add_status_to_tasks     # Good
  mix ecto.gen.migration fix                     # Bad
  ```

- **Keep migrations small and focused:**
  ```elixir
  # ✅ Good: One change per migration
  def change do
    add :status, :string
  end

  # ❌ Bad: Multiple unrelated changes
  def change do
    add :status, :string
    add :priority, :integer
    modify :name, :string
    remove :old_field
  end
  ```

- **Test data migrations:**
  ```bash
  mix ecto.create
  mix ecto.migrate
  mix test
  ```

- **Always rollback before committing:**
  ```bash
  make rollback BOT=gtd
  make migrate BOT=gtd
  # Verify it works both ways
  ```

- **Include data safety in migrations:**
  ```elixir
  def change do
    execute("UPDATE tasks SET status = 'pending' WHERE status IS NULL")
    alter table(:tasks) do
      modify :status, :string, null: false
    end
  end
  ```

### ❌ Don't

- **Don't modify applied migrations** — create new ones instead
- **Don't use bare `execute()` without reversibility**
- **Don't assume column existence** — guard with `if_exists`
- **Don't deploy without testing rollback**
- **Don't create indexes on large tables without CONCURRENTLY**

## Common Ecto Types

```elixir
:id              # Integer primary key
:string          # VARCHAR (255)
:text            # TEXT (unlimited)
:integer         # INT
:bigint          # BIGINT (for large numbers)
:float           # FLOAT
:decimal         # NUMERIC (for money)
:boolean         # BOOLEAN
:date            # DATE
:time            # TIME
:datetime        # TIMESTAMP
:utc_datetime    # TIMESTAMP with UTC
:binary          # BYTEA
:uuid            # UUID
:json            # JSON
:jsonb           # JSONB (better for queries)
:enum            # ENUM (custom type)
```

## Examples

### Example 1: Create a tasks table with indexes

```elixir
defmodule BotArmyGtd.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :name, :string, null: false
      add :description, :text
      add :status, :string, default: "pending"
      add :priority, :integer, default: 0
      add :due_date, :date
      add :user_id, references(:users, on_delete: :delete_all)
      timestamps()
    end

    create index(:tasks, [:status])
    create index(:tasks, [:user_id])
    create index(:tasks, [:due_date])
  end
end
```

### Example 2: Safely rename a column

```elixir
defmodule BotArmyGtd.Repo.Migrations.RenameStatusToState do
  use Ecto.Migration

  def change do
    rename table(:tasks), :status, to: :state
  end
end
```

### Example 3: Add unique constraint

```elixir
defmodule BotArmyGtd.Repo.Migrations.AddUniqueEmailConstraint do
  use Ecto.Migration

  def change do
    create unique_index(:users, [:email])
  end
end
```

## Next Steps

- **Set up a new bot:** `make help-create-bot`
- **Troubleshoot issues:** `make help-debugging`
- **Understand database schema:** Check `priv/repo/migrations/` in any bot
- **Learn Ecto:** [hexdocs.pm/ecto](https://hexdocs.pm/ecto)
- **PostgreSQL docs:** [postgresql.org/docs](https://www.postgresql.org/docs/)
