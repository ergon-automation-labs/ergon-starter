# Automatic Database Migrations

How to set up bots to automatically create databases and run migrations on startup.

## Problem

Currently, bots fail on startup if their databases don't exist:
```
** (Postgrex.Error) FATAL 3D000 (invalid_catalog_name) database "bot_army_chore" does not exist
```

This happens because:
1. Docker builds don't have database access
2. Migrations must run at **runtime**, not build time
3. Bots need to wait for PostgreSQL to be ready before connecting

## Solution: Release Tasks with Auto-Migrations

### Step 1: Create a Release Task

Add an Ecto migration task to your bot's `mix.exs`:

**File:** `lib/<bot_name>/release.ex`

```elixir
defmodule YourBot.Release do
  @moduledoc """
  Release tasks for database setup and migrations.
  """

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _fun, _state} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
      IO.puts("✓ Migrations complete for #{repo}")
    end
  end

  def create_databases do
    load_app()

    for repo <- repos() do
      case repo.__adapter__.storage_up(repo.config()) do
        :ok ->
          IO.puts("✓ Database created for #{repo}")

        {:error, :already_up} ->
          IO.puts("✓ Database already exists for #{repo}")

        {:error, reason} ->
          IO.puts("✗ Failed to create database for #{repo}: #{inspect(reason)}")
          raise "Could not create database"
      end
    end
  end

  defp repos do
    Application.fetch_env!(:your_bot, :ecto_repos)
  end

  defp load_app do
    Application.load(:your_bot)
  end
end
```

### Step 2: Update Dockerfile to Run Migrations

Modify the Dockerfile to run migrations before starting the bot:

**In `Dockerfile`, change the CMD line:**

```dockerfile
# Before:
# CMD /app/bin/${BOT_NAME} start

# After: Run migrations, then start
CMD ["/bin/sh", "-c", "/app/bin/${BOT_NAME} eval 'YourBot.Release.create_databases()' && /app/bin/${BOT_NAME} eval 'YourBot.Release.migrate()' && /app/bin/${BOT_NAME} start"]
```

Or better, use an entrypoint script:

**Create `scripts/docker-entrypoint.sh`:**

```bash
#!/bin/sh
set -e

BOT_NAME=${BOT_NAME:-unknown}
RELEASE_DIR=${RELEASE_DIR:-/app}
DB_HOST=${DB_HOST:-postgres}
DB_PORT=${DB_PORT:-5432}

echo "[$(date)] Waiting for PostgreSQL..."

# Wait for database to be ready (max 60 seconds)
RETRY=0
while [ $RETRY -lt 30 ]; do
  if nc -z "$DB_HOST" "$DB_PORT" 2>/dev/null; then
    echo "PostgreSQL is ready!"
    break
  fi
  RETRY=$((RETRY + 1))
  sleep 2
done

echo "[$(date)] Creating databases..."
cd "$RELEASE_DIR"
./bin/$BOT_NAME eval 'BotName.Release.create_databases()' || true

echo "[$(date)] Running migrations..."
./bin/$BOT_NAME eval 'BotName.Release.migrate()' || true

echo "[$(date)] Starting bot..."
exec ./bin/$BOT_NAME start
```

**Update `docker-compose.yml`:**

```yaml
services:
  your_bot:
    build: ...
    entrypoint: /app/entrypoint.sh
    environment:
      BOT_NAME: your_bot_bot
      DB_HOST: postgres
      DB_PORT: 5432
```

Or copy entrypoint into the Dockerfile:

```dockerfile
# In Dockerfile, after copying the release:
COPY scripts/docker-entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
```

### Step 3: Configure Ecto Repos

Make sure your `config/config.exs` has ecto_repos configured:

```elixir
# config/config.exs
config :your_bot, ecto_repos: [YourBot.Repo]

config :your_bot, YourBot.Repo,
  database: System.get_env("POSTGRES_DB", "bot_army_your_bot"),
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  pool_size: 2
```

## For Multi-Bot Packs

If your bot pack manages multiple services (like `areas_pack` with chore + fitness bots), create one Release module:

**`lib/areas_pack/release.ex`:**

```elixir
defmodule AreasPack.Release do
  def migrate do
    load_app()

    # Migrate all repos
    [AreasPack.Repo, ChoreBot.Repo, FitnessBot.Repo]
    |> Enum.each(&migrate_repo/1)
  end

  def create_databases do
    load_app()

    [AreasPack.Repo, ChoreBot.Repo, FitnessBot.Repo]
    |> Enum.each(&create_repo/1)
  end

  defp migrate_repo(repo) do
    {:ok, _fun, _state} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    IO.puts("✓ Migrations: #{repo}")
  rescue
    e in Ecto.MigrationError ->
      IO.puts("✗ Migration failed for #{repo}: #{e.message}")
  end

  defp create_repo(repo) do
    case repo.__adapter__.storage_up(repo.config()) do
      :ok -> IO.puts("✓ Created: #{repo}")
      {:error, :already_up} -> IO.puts("✓ Exists: #{repo}")
      {:error, reason} -> IO.puts("✗ Error #{repo}: #{reason}")
    end
  end

  defp load_app do
    Application.load(:areas_pack)
  end
end
```

## Test It

```bash
# Start fresh
docker compose down -v
docker compose up -d

# Watch logs
docker compose logs -f

# Should see:
# ✓ Database created for YourBot.Repo
# ✓ Migrations complete for YourBot.Repo
# [info] Application started
```

## Verify

```bash
make health-check
# Should show all services running

docker compose ps
# Should show all bots "Up"
```

## Troubleshooting

**"Ecto not found" error:**
- Make sure `:ecto` and `:ecto_sql` are in dependencies
- Add `config :your_bot, ecto_repos: [...]` to config.exs

**"Release module not found":**
- Check file is at `lib/<app_name>/release.ex`
- Check module name matches: `defmodule <App>.Release`

**Still failing to start:**
```bash
# Debug by running the release eval directly
docker compose exec your_bot /app/bin/your_bot eval 'YourBot.Release.create_databases()'
docker compose exec your_bot /app/bin/your_bot eval 'YourBot.Release.migrate()'
```

## Using Makefile Targets

Once your bot has the Release task configured, use these Makefile commands:

```bash
# Migrate all bots with databases
make migrate

# Migrate a specific bot
make migrate BOT=<service_name>

# Rollback all bots (1 step)
make rollback

# Rollback a specific bot (N steps)
make rollback BOT=<service_name> STEPS=2

# Check migration status
make migrate-status
```

**Note:** These targets assume your bot has a Release module at `lib/<bot_name>/release.ex` with `migrate()` and `rollback(steps)` functions.

## Next: Update the Starter Dockerfile

This should be integrated into `/Users/abby/code/bot-army-starter/Dockerfile` so all new bots automatically support auto-migrations.

Would you like me to update the shared Dockerfile to include this pattern for all bots?
