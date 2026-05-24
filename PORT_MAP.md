# Bot Army Starter — Port Map

Host ports are configurable to avoid collisions with existing services.
Inside Docker, all services use standard ports.

## Default host ports

| Service | Host port | Container port | Override env var |
|---------|-----------|----------------|------------------|
| NATS | 54222 | 4222 | `NATS_HOST_PORT` |
| NATS Monitor | 58222 | 8222 | `NATS_MONITOR_HOST_PORT` |
| PostgreSQL | 55432 | 5432 | `POSTGRES_HOST_PORT` |
| Ollama | 51434 | 11434 | `OLLAMA_HOST_PORT` |

## Connecting from host

```bash
# NATS CLI
nats sub ">" --server nats://localhost:54222

# PostgreSQL
psql -h localhost -p 55432 -U postgres

# TUI management console
./bot-army tui --nats-port 54222

# NATS monitor (browser)
open http://localhost:58222
```

## Fresh machine (no port conflicts)

Override to use standard ports:

```bash
NATS_HOST_PORT=4222 POSTGRES_HOST_PORT=5432 make quickstart-default
```

## Coexisting with production Bot Army

The defaults (54xxx range) are chosen to avoid collision with:
- Production NATS: 4222, 14223, 14224
- Dev NATS: 4223
- Test NATS: 4224
- Production PostgreSQL: 35432
- Local Ollama: 11434
