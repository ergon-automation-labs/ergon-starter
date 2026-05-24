# Bot Army Starter
# Build targets use Docker — Go is not required on the host.

BINARY := bot-army
BUILD_IMAGE := bot-army-builder
PLATFORM := $(shell uname -s | tr '[:upper:]' '[:lower:]')-$(shell uname -m)
MONOREPO ?= $(HOME)/code/elixir_bots

.PHONY: help quickstart build install sync init add status up down logs ps clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# --- One-click ---

quickstart: catalog/bots.json ## Full setup: wizard → clone → build → start
	@echo ""
	@echo "═══════════════════════════════════════════"
	@echo "  Bot Army Quickstart"
	@echo "═══════════════════════════════════════════"
	@echo ""
	@echo "This will walk you through selecting bots"
	@echo "and LLM providers, then build and start"
	@echo "everything in Docker."
	@echo ""
	$(MAKE) build
	./$(BINARY) init
	@echo ""
	@echo "Building containers (first run takes ~5 min)..."
	docker compose up -d --build
	@echo ""
	@echo "═══════════════════════════════════════════"
	@echo "  ✓ Bot Army is running!"
	@echo ""
	@echo "  Useful commands:"
	@echo "    make logs       Follow logs"
	@echo "    make ps         Show services"
	@echo "    make add BOT=x  Add another bot"
	@echo "    make down       Stop everything"
	@echo "═══════════════════════════════════════════"

quickstart-default: catalog/bots.json ## Headless: core bots + Ollama, no prompts
	@echo "Setting up Bot Army with defaults (core bots + Ollama)..."
	$(MAKE) build
	./scripts/quickstart-default.sh
	docker compose up -d --build
	@echo ""
	@echo "✓ Bot Army is running with core bots + Ollama"
	@echo "  Run 'make logs' to follow output"

# --- Build ---

build: ## Build the bot-army CLI binary
	docker build -f Dockerfile.build -t $(BUILD_IMAGE) .
	docker create --name bot-army-extract $(BUILD_IMAGE) 2>/dev/null || true
	docker cp bot-army-extract:/usr/local/bin/bot-army ./$(BINARY)
	docker rm bot-army-extract
	chmod +x ./$(BINARY)
	@echo "✓ Built ./$(BINARY)"

install: build ## Build and install to /usr/local/bin
	cp ./$(BINARY) /usr/local/bin/$(BINARY)
	@echo "✓ Installed to /usr/local/bin/$(BINARY)"

# --- Catalog ---

sync: ## Sync bot catalog from monorepo (MONOREPO=path)
	./scripts/sync-catalog.sh $(MONOREPO)

# --- Wizard ---

init: build catalog/bots.json ## Run the interactive setup wizard
	./$(BINARY) init

catalog/bots.json: scripts/sync-catalog.sh
	@echo "Bot catalog missing — syncing from $(MONOREPO)..."
	./scripts/sync-catalog.sh $(MONOREPO)

add: build ## Add a bot (usage: make add BOT=fitness)
	@test -n "$(BOT)" || (echo "Usage: make add BOT=<name>" && exit 1)
	./$(BINARY) add $(BOT)

status: build ## Show configured services
	./$(BINARY) status

# --- Docker Compose ---

up: ## Start all services (builds if needed)
	docker compose up -d --build

down: ## Stop all services
	docker compose down

logs: ## Follow all service logs
	docker compose logs -f

ps: ## Show running services
	docker compose ps

migrate: ## Run database migrations for all bots with DB
	@for svc in $$(docker compose config --services); do \
		if docker compose exec $$svc ls /app/bin/* >/dev/null 2>&1; then \
			bot=$$(basename $$(docker compose exec $$svc ls /app/bin/ 2>/dev/null | head -1) 2>/dev/null); \
			if [ -n "$$bot" ]; then \
				echo "Migrating $$svc..."; \
				docker compose exec $$svc /app/bin/$$bot eval "Application.ensure_all_started(:$$svc) && :ok" 2>/dev/null || true; \
			fi; \
		fi; \
	done

# --- Maintenance ---

rebuild: ## Force rebuild all images (no cache)
	docker compose build --no-cache

pull-repos: ## Pull latest code for all cloned repos
	@for dir in repos/*/; do \
		echo "Pulling $$(basename $$dir)..."; \
		git -C "$$dir" pull --ff-only 2>/dev/null || echo "  ⚠ failed"; \
	done

clean: ## Remove generated files (keeps repos)
	rm -f ./$(BINARY) docker-compose.yml .env
	@echo "✓ Cleaned (repos/ preserved)"

nuke: ## Remove everything including cloned repos
	rm -f ./$(BINARY) docker-compose.yml .env
	rm -rf repos/
	docker compose down -v 2>/dev/null || true
	@echo "✓ Nuked"
