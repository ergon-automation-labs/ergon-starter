# Create Your Own Bot

Step-by-step guide to building a custom Bot Army bot from the minimal template.

## What is a Bot?

A **Bot Army bot** is an Elixir/OTP GenServer that:
- Listens to NATS subjects for incoming requests
- Processes data (fetch, transform, store, call APIs)
- Responds with results or publishes events
- Reports health status every 30 minutes
- Gets deployed as a Docker container in your fleet

**Examples:**
- GTD Bot: Manages tasks, stores in PostgreSQL, responds to task queries
- LLM Bot: Calls Claude/GPT, returns completions
- Synapse: Listens to Discord, relays messages to other bots
- Your Bot: Whatever you need!

## Prerequisites

Before starting, ensure:
- Bot Army is running: `make quickstart` completed
- You have the bot template: `/Users/abby/code/elixir_bots/bot_template`
- Elixir installed (or use Docker)

## Step 1: Create Your Bot

Use the template setup script to scaffold a new bot:

```bash
cd /Users/abby/code/elixir_bots/bot_template
./setup_new_bot.sh bot_army_mybot mybot_bot mybot "My Bot"
```

**Arguments:**
- `bot_army_mybot` — Elixir app name (use `bot_army_` prefix)
- `mybot_bot` — OTP release name (use `_bot` suffix)
- `mybot` — GitHub repo suffix (lowercase, underscores OK)
- `"My Bot"` — Human-readable title

**Output:**
```
Created bot_army_mybot/
├── lib/bot_army_mybot/
│   ├── application.ex
│   ├── nats/
│   │   └── consumer.ex          (listens to NATS)
│   ├── handlers/
│   │   └── example_handler.ex   (your business logic)
│   └── stores/
│       └── example_store.ex     (database access)
├── test/
│   ├── bot_army_mybot_test.exs
│   ├── nats/
│   │   └── consumer_test.exs
│   └── handlers/
│       └── example_handler_test.exs
├── mix.exs
├── Makefile
└── README.md
```

## Step 2: Understand the Structure

### application.ex
Starts your bot's services:
```elixir
def start(_type, _args) do
  children = [
    BotArmyRuntime.NATS.Connection,    # Connects to NATS
    BotArmyMybot.NATS.Consumer,        # Subscribes to subjects
    BotArmyMybot.PulsePublisher,       # Reports health every 30 min
  ]
  
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### NATS Consumer
Listens to subjects and routes to handlers:
```elixir
# lib/bot_army_mybot/nats/consumer.ex
def init(_) do
  BotArmyRuntime.NATS.subscribe("mybot.request", &handle_message/2)
end

defp handle_message(msg, _context) do
  # Decode JSON body
  case Jason.decode(msg.data) do
    {:ok, payload} ->
      # Route to handler
      reply = MyBot.Handlers.Example.execute(payload)
      # Reply to caller
      Gnat.pub(nc, msg.reply, Jason.encode!(reply))
    {:error, _} ->
      handle_error(msg)
  end
end
```

### Handlers
Pure functions that do the work:
```elixir
# lib/bot_army_mybot/handlers/example_handler.ex
defmodule BotArmyMybot.Handlers.ExampleHandler do
  def execute(payload) do
    # Your business logic here
    %{"result" => "done"}
  end
end
```

### Stores
Database access via Ecto:
```elixir
# lib/bot_army_mybot/stores/example_store.ex
defmodule BotArmyMybot.Stores.ExampleStore do
  def get_data(id) do
    YourRepo.get(YourSchema, id)
  end
end
```

## Step 3: Implement Your First Handler

Replace the example handler with your logic:

```elixir
# lib/bot_army_mybot/handlers/my_logic_handler.ex
defmodule BotArmyMybot.Handlers.MyLogicHandler do
  @moduletag :handlers  # For test filtering
  
  def execute(%{"query" => q}) do
    # Process the query
    result = do_work(q)
    {:ok, result}
  end
  
  def execute(_), do: {:error, "invalid payload"}
  
  defp do_work(query) do
    # Your business logic
    %{"answer" => query <> " processed"}
  end
end
```

## Step 4: Write Tests

Test your handler in isolation (no NATS, no DB):

```elixir
# test/handlers/my_logic_handler_test.exs
defmodule BotArmyMybot.Handlers.MyLogicHandlerTest do
  use ExUnit.Case
  @moduletag :handlers
  
  test "processes query" do
    result = BotArmyMybot.Handlers.MyLogicHandler.execute(%{"query" => "test"})
    assert {:ok, %{"answer" => "test processed"}} = result
  end
  
  test "rejects invalid input" do
    result = BotArmyMybot.Handlers.MyLogicHandler.execute(%{})
    assert {:error, "invalid payload"} = result
  end
end
```

Run tests:
```bash
cd bot_army_mybot
make test                    # Unit tests only (fast)
make test-handlers          # Just handler tests
make test-integration       # With real DB/NATS (slower)
```

## Step 5: Test Locally

### Start your bot in dev mode:

```bash
cd bot_army_mybot
mix ecto.setup              # Setup database
iex -S mix                  # Start interactive shell + bot
```

You'll see:
```
[info] Starting NATS connection...
[info] Subscribing to mybot.request
[info] Health publisher started
iex(1)>
```

### Test from another terminal:

```bash
# Send a test request via NATS
nats request --server nats://localhost:4223 mybot.request '{"query":"test"}' --timeout 3s
```

Expected response:
```json
{"answer": "test processed"}
```

### Or test from iex:

```elixir
# In the iex shell from above:
{:ok, nc} = Gnat.start_link()
{:ok, reply} = Gnat.request(nc, "mybot.request", ~s({"query":"test"}), timeout: 3000)
IO.puts(reply.body)
```

## Step 6: Add to Your Fleet

Once your bot is working locally, add it to docker-compose:

```bash
cd /Users/abby/code/bot-army-starter
make add BOT=mybot
```

This updates `docker-compose.yml` to build and run your bot.

Verify:
```bash
docker compose ps
# You should see mybot_bot starting
```

## Step 7: Verify Integration

### Check bot health:

```bash
docker compose logs mybot_bot | tail -20
# Should see: "Health publisher started" and no errors
```

### Test via NATS from the host:

```bash
nats request --server nats://localhost:54222 mybot.request '{"query":"hello"}' --timeout 3s
```

### Test from Claude:

```
# In Claude Desktop or Claude Code:
/synapse-gtd-create-safe

→ Creates a task that your bot might handle
→ Your bot receives the event and processes it
```

## Step 8: Deploy to Production

Once your bot is stable:

1. **Bump the version** in `mix.exs`:
   ```elixir
   def project do
     [
       app: :bot_army_mybot,
       version: "0.1.1",    # ← Increment this
       ...
     ]
   end
   ```

2. **Commit and push**:
   ```bash
   git add mix.exs
   git commit -m "bump: v0.1.1"
   git push
   ```

3. **Pre-push hooks will**:
   - Compile the code
   - Run tests
   - Build an OTP release
   - Create a GitHub release

4. **Jenkins will**:
   - Download the release
   - Deploy to production cluster
   - Restart the bot

## Common Patterns

### Call an External API

```elixir
defmodule BotArmyMybot.APIClient do
  def fetch_data(url) do
    case HTTPoison.get(url) do
      {:ok, response} -> Jason.decode(response.body)
      {:error, reason} -> {:error, reason}
    end
  end
end

# In tests, mock it:
defmodule BotArmyMybot.APIClientMock do
  def fetch_data(_url) do
    {:ok, %{"data" => "mocked"}}
  end
end
```

### Store Data in PostgreSQL

```elixir
defmodule BotArmyMybot.Stores.TaskStore do
  def create(attrs) do
    %BotArmyMybot.Schemas.Task{}
    |> BotArmyMybot.Schemas.Task.changeset(attrs)
    |> BotArmyMybot.Repo.insert()
  end
  
  def get(id) do
    BotArmyMybot.Repo.get(BotArmyMybot.Schemas.Task, id)
  end
end

# Create the schema:
defmodule BotArmyMybot.Schemas.Task do
  use Ecto.Schema
  
  schema "tasks" do
    field :name, :string
    field :status, :string, default: "pending"
    timestamps()
  end
  
  def changeset(struct, attrs) do
    struct |> Ecto.Changeset.cast(attrs, [:name, :status])
  end
end
```

### Publish Events

```elixir
defmodule BotArmyMybot.Publishers do
  def task_completed(task_id) do
    event = %{
      "event" => "task_completed",
      "task_id" => task_id,
      "timestamp" => DateTime.utc_now()
    }
    
    BotArmyRuntime.NATS.publish("mybot.events.task_completed", event)
  end
end
```

## Troubleshooting

**Bot won't start:**
```bash
docker compose logs mybot_bot
# Check for compilation or NATS connection errors
```

**NATS connection fails:**
```bash
# Verify NATS is up
docker compose ps nats

# Check port is correct in .env
cat .env | grep NATS

# From host, verify connectivity
nats server check
```

**Tests fail:**
```bash
cd bot_army_mybot
make test-integration  # Run with real services
docker compose logs postgres  # Check if DB is up
```

**Handler logic is wrong:**
```bash
# Add debug output
require Logger
Logger.info("Debug: #{inspect(result)}")

# Run just your handler test:
cd bot_army_mybot
mix test test/handlers/my_logic_handler_test.exs --trace
```

## Next Steps

1. **Read the template docs** — More patterns and best practices:
   ```bash
   cat /Users/abby/code/elixir_bots/bot_template/TEMPLATE_README.md
   ```

2. **Explore example bots** — See real implementations:
   ```bash
   ls /Users/abby/code/elixir_bots/bot_army_gtd/lib/bot_army_gtd/handlers/
   ```

3. **Check the bridge contract** — What other bots expose:
   ```bash
   nats request --server nats://localhost:54222 bot_army.registry.capabilities.list '{}' --timeout 3s
   ```

4. **Join the community** — Share your bot with the Bot Army team

Happy building! 🚀
