# Bot Army Starter
# Build targets use Docker — Go is not required on the host.

BINARY := bot-army
BUILD_IMAGE := bot-army-builder
PLATFORM := $(shell uname -s | tr '[:upper:]' '[:lower:]')-$(shell uname -m)

# Detect OS for Docker socket mounting
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
  DOCKER_SOCK := /var/run/docker.sock
  OS_NAME := macOS
else ifeq ($(UNAME_S),Linux)
  DOCKER_SOCK := /var/run/docker.sock
  OS_NAME := Linux
else ifneq (,$(findstring MINGW,$(UNAME_S)))
  # Windows (Git Bash / MSYS2) - requires WSL2 or native pipe handling
  DOCKER_SOCK := /var/run/docker.sock
  OS_NAME := Windows
else ifneq (,$(findstring CYGWIN,$(UNAME_S)))
  # Cygwin on Windows
  DOCKER_SOCK := /var/run/docker.sock
  OS_NAME := Windows (Cygwin)
else
  # Fallback
  DOCKER_SOCK := /var/run/docker.sock
  OS_NAME := Unknown
endif

# Release channel selection (stable, latest, nightly)
CHANNEL ?= stable

# Port configuration (customize to avoid conflicts)
NATS_PORT ?= 4222
PG_PORT ?= 5432

# Docker registry (local registry for pre-built images)
REGISTRY ?= localhost:32000
REGISTRY_PORT ?= 32000

# Elixir builds are memory-heavy — limit parallel builds to avoid OOM
COMPOSE_BUILD_PARALLEL ?= 3

.PHONY: help quickstart build install sync init add status dashboard up down logs ps clean rebuild pull-repos nuke docker-clean docker-deep-clean docker-health clean-images clean-docker-volumes clean-docker-builder clean-logs clean-caches-safe clean-safe clean-disk disk-check test release-check release-test release-create release-list release-latest registry-build registry-push registry-publish registry-images registry-setup setup-tools claude-integrate help-create-bot help-volumes

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

# --- One-click ---

quickstart: catalog/bots.json ## Full setup: wizard → clone → build → start
	@echo ""
	@echo "═══════════════════════════════════════════"
	@echo "  Bot Army Quickstart ($(OS_NAME))"
	@echo "═══════════════════════════════════════════"
	@echo ""
	@echo "This will walk you through selecting bots"
	@echo "and LLM providers, then build and start"
	@echo "everything in Docker."
	@echo ""
	$(MAKE) build
	docker run --rm -it \
		-v $(PWD):/workspace \
		-v $(HOME)/.config/gh:/root/.config/gh \
		-v $(DOCKER_SOCK):/var/run/docker.sock \
		-w /workspace $(BUILD_IMAGE) /usr/local/bin/$(BINARY) init
	@echo ""
	@echo "Building containers (first run takes ~5 min)..."
	DOCKER_BUILDKIT=1 COMPOSE_PARALLEL_LIMIT=$(COMPOSE_BUILD_PARALLEL) docker compose up -d --build
	@echo ""
	@echo "═══════════════════════════════════════════"
	@echo "  ✓ Bot Army is running!"
	@echo ""
	@echo "  Your data is stored at:"
	@echo "    ~/data/para/              Your notes (PARA)"
	@echo "    ~/data/logs/              Bot logs"
	@echo ""
	@echo "  Next steps:"
	@echo "    make logs                 Follow logs"
	@echo "    make dashboard            Live monitoring"
	@echo "    make help-volumes         Configure storage"
	@echo "    make claude-integrate     Claude setup"
	@echo ""
	@echo "  Build & manage:"
	@echo "    make ps                   Show services"
	@echo "    make help-create-bot      Create your own bot"
	@echo "    make add BOT=name         Add another bot"
	@echo "    make down                 Stop everything"
	@echo "═══════════════════════════════════════════"

quickstart-default: catalog/bots.json ## Headless: core bots + Ollama, no prompts
	@echo "Setting up Bot Army with defaults (core bots + Ollama)..."
	$(MAKE) build
	@# Auto-detect local registry — use pre-built images if available
	@if curl -s http://$(REGISTRY)/v2/_catalog >/dev/null 2>&1 && \
	    curl -s http://$(REGISTRY)/v2/gtd_bot/tags/list 2>/dev/null | grep -q latest; then \
		echo "  Found pre-built images in $(REGISTRY) — using registry"; \
		REGISTRY=$(REGISTRY) ./scripts/quickstart-default.sh; \
		docker compose up -d; \
	else \
		./scripts/quickstart-default.sh; \
		DOCKER_BUILDKIT=1 COMPOSE_PARALLEL_LIMIT=$(COMPOSE_BUILD_PARALLEL) docker compose up -d --build; \
	fi
	@echo ""
	@echo "✓ Bot Army is running with core bots + Ollama"
	@echo "  Run 'make logs' to follow output"

claude-integrate: ## Show Claude Desktop + Claude Code integration guide
	@cat docs/CLAUDE_INTEGRATION.md | less

help-create-bot: ## Step-by-step guide to create your own bot
	@cat docs/CREATE_BOT.md | less

help-volumes: ## Configure PARA, internal docs, and persistent storage
	@cat docs/VOLUMES_AND_STORAGE.md | less

# --- Build ---

# Detect host platform for cross-compilation
HOST_OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
HOST_ARCH := $(shell uname -m | sed 's/x86_64/amd64/' | sed 's/aarch64/arm64/')

build: ## Build the bot-army CLI binary (Linux, inside Docker)
	docker build -f Dockerfile.build -t $(BUILD_IMAGE) .
	docker create --name bot-army-extract $(BUILD_IMAGE) 2>/dev/null || true
	docker cp bot-army-extract:/usr/local/bin/bot-army ./$(BINARY)
	docker rm bot-army-extract
	chmod +x ./$(BINARY)
	@echo "✓ Built ./$(BINARY)"

build-native: ## Build native binary for the host OS (for running dashboard locally)
	docker build -f Dockerfile.build \
		--build-arg GOOS=$(HOST_OS) \
		--build-arg GOARCH=$(HOST_ARCH) \
		--target build \
		-t $(BUILD_IMAGE)-native .
	docker create --name bot-army-extract-native $(BUILD_IMAGE)-native 2>/dev/null || true
	docker cp bot-army-extract-native:/bot-army ./$(BINARY)-native
	docker rm bot-army-extract-native 2>/dev/null || true
	chmod +x ./$(BINARY)-native
	@echo "✓ Built ./$(BINARY)-native ($(HOST_OS)/$(HOST_ARCH))"

install: build ## Build and install to /usr/local/bin
	cp ./$(BINARY) /usr/local/bin/$(BINARY)
	@echo "✓ Installed to /usr/local/bin/$(BINARY)"

# --- Catalog ---

sync: ## Sync bot catalog (CHANNEL=stable|latest|nightly, default: stable)
	./scripts/sync-catalog.sh $(CHANNEL)

# --- Pack Docker Images ---

generate-dockerfiles: ## Generate Dockerfiles for all packs (CHANNEL=stable|latest|nightly)
	@python3 scripts/generate-pack-dockerfiles.py --channel $(CHANNEL) --output-dir .
	@echo ""
	@echo "Generated Dockerfiles (update .gitignore if needed):"
	@ls -1 Dockerfile.* 2>/dev/null || echo "  (no Dockerfiles yet)"

generate-compose: ## Generate docker-compose.yml (PACKS=core,social_media [CHANNEL=stable] [NATS_PORT=4222] [PG_PORT=5432])
	@test -n "$(PACKS)" || (echo "Usage: make generate-compose PACKS=core,social_media [CHANNEL=stable] [NATS_PORT=4222] [PG_PORT=5432]" && exit 1)
	@python3 scripts/generate-compose.py \
		--packs $(PACKS) \
		--channel $(CHANNEL) \
		--nats-client-port $(NATS_PORT) \
		--postgres-port $(PG_PORT) \
		--output docker-compose.yml

build-pack: generate-dockerfiles ## Build a pack image (PACK=core|social_media|learning_deepdive|areas|research)
	@test -n "$(PACK)" || (echo "Usage: make build-pack PACK=<pack_name> [CHANNEL=stable]" && exit 1)
	docker build -f Dockerfile.$(PACK) \
		--build-arg CHANNEL=$(CHANNEL) \
		-t ergon-automation-labs/bot-army-$(PACK):$(CHANNEL) \
		-t ergon-automation-labs/bot-army-$(PACK):latest \
		.
	@echo "✓ Built ergon-automation-labs/bot-army-$(PACK):$(CHANNEL)"

build-packs: generate-dockerfiles ## Build all pack images (CHANNEL=stable|latest|nightly)
	@echo "Building all packs (channel: $(CHANNEL))..."
	@for pack in core social_media learning_deepdive areas research; do \
		echo ""; \
		$(MAKE) build-pack PACK=$$pack CHANNEL=$(CHANNEL); \
	done

push-pack: ## Push a pack image to registry (PACK=<name>, CHANNEL=stable|latest|nightly)
	@test -n "$(PACK)" || (echo "Usage: make push-pack PACK=<pack_name> [CHANNEL=stable]" && exit 1)
	docker push ergon-automation-labs/bot-army-$(PACK):$(CHANNEL)
	docker push ergon-automation-labs/bot-army-$(PACK):latest
	@echo "✓ Pushed ergon-automation-labs/bot-army-$(PACK)"

push-packs: ## Push all pack images to registry (CHANNEL=stable|latest|nightly)
	@echo "Pushing all packs (channel: $(CHANNEL))..."
	@for pack in core social_media learning_deepdive areas research; do \
		echo ""; \
		$(MAKE) push-pack PACK=$$pack CHANNEL=$(CHANNEL); \
	done

# --- Wizard ---

init: build catalog/bots.json ## Run the interactive setup wizard
	docker run --rm -it \
		-v $(PWD):/workspace \
		-v $(HOME)/.config/gh:/root/.config/gh \
		-v $(DOCKER_SOCK):/var/run/docker.sock \
		-w /workspace $(BUILD_IMAGE) /usr/local/bin/$(BINARY) init

catalog/bots.json: scripts/sync-catalog.sh config/repos-public.toml
	@echo "Bot catalog missing — generating from repos-public.toml (channel: $(CHANNEL))..."
	./scripts/sync-catalog.sh $(CHANNEL)

add: build ## Add a bot (usage: make add BOT=fitness)
	@test -n "$(BOT)" || (echo "Usage: make add BOT=<name>" && exit 1)
	docker run --rm \
		-v $(PWD):/workspace \
		-v $(HOME)/.config/gh:/root/.config/gh \
		-v $(DOCKER_SOCK):/var/run/docker.sock \
		-w /workspace $(BUILD_IMAGE) /usr/local/bin/$(BINARY) add $(BOT)

status: build ## Show configured services
	docker run --rm \
		-v $(PWD):/workspace \
		-v $(HOME)/.config/gh:/root/.config/gh \
		-v $(DOCKER_SOCK):/var/run/docker.sock \
		-w /workspace $(BUILD_IMAGE) /usr/local/bin/$(BINARY) status

dashboard: build-native ## Launch TUI dashboard (runs natively, requires terminal)
	exec ./$(BINARY)-native dashboard

# --- Docker Compose ---

up: ## Start all services (builds if needed, uses BuildKit for shared base caching)
	DOCKER_BUILDKIT=1 COMPOSE_PARALLEL_LIMIT=$(COMPOSE_BUILD_PARALLEL) docker compose up -d --build

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

# --- Release Management ---

release-check: ## Verify build succeeds and no uncommitted changes
	@echo "Checking for uncommitted changes..."
	@git diff --quiet || (echo "❌ Uncommitted changes detected" && exit 1)
	@git diff --cached --quiet || (echo "❌ Staged changes detected" && exit 1)
	@echo "✓ Working tree clean"
	@echo ""
	@echo "Building to verify..."
	@$(MAKE) build > /dev/null && echo "✓ Build successful" || (echo "❌ Build failed" && exit 1)

release-test: ## Test installer in a clean temporary directory
	@echo "Testing installer in temporary directory..."
	@TEMP_DIR=$$(mktemp -d) && \
	cd $$TEMP_DIR && \
	echo "Running installer..." && \
	bash -c "curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/ergon-starter/main/install.sh | bash -s -- --help" && \
	echo "✓ Installer test passed" || (echo "❌ Installer test failed" && false)

release-create: release-check ## Create GitHub release (VERSION=x.y.z make release-create)
	@if [ -z "$(VERSION)" ]; then \
		echo "❌ VERSION not specified. Usage: VERSION=v0.2.0 make release-create"; \
		exit 1; \
	fi
	@echo "Creating release $(VERSION)..."
	@git tag -a $(VERSION) -m "Release $(VERSION)" && \
	git push origin $(VERSION) && \
	echo "✓ Tag $(VERSION) created and pushed"
	@echo ""
	@echo "Next: Create release notes on GitHub"
	@echo "  gh release create $(VERSION) --notes <description>"

release-list: ## List all releases
	@echo "Releases:"
	@git tag -l 'v*' | sort -V -r | head -10

release-latest: ## Show latest release version
	@git tag -l 'v*' | sort -V | tail -1

# --- Maintenance ---

setup-tools: ## Install host-side tools (graphify + ripgrep)
	@./scripts/install-tools.sh

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

# --- Disk Cleanup ---
# Granular cleanup targets adapted from the Bot Army ops Makefile.
# All destructive targets default to dry-run. Use APPLY=1 to execute.

disk-check: ## Show disk usage summary
	@echo "═══════════════════════════════════════"
	@echo "  Disk Usage Summary"
	@echo "═══════════════════════════════════════"
	@echo ""
	@echo "Docker:"
	@docker system df 2>/dev/null || echo "  (docker not running)"
	@echo ""
	@echo "Project:"
	@du -sh . 2>/dev/null || echo "  (not in project dir)"
	@if [ -d repos/ ]; then du -sh repos/ 2>/dev/null; fi
	@if [ -d data/ ]; then du -sh data/ 2>/dev/null; fi
	@echo ""
	@echo "System (macOS):"
	@if [ "$$UNAME_S" = "Darwin" ]; then \
		echo "  Caches:  $$(du -sh $$HOME/Library/Caches 2>/dev/null | awk '{print $$1}')"; \
		echo "  Logs:    $$(du -sh $$HOME/Library/Logs 2>/dev/null | awk '{print $$1}')"; \
	fi
	@echo ""
	@echo "Quick wins:"
	@echo "  make clean-images          Remove unused Docker images"
	@echo "  make clean-docker           Full Docker cleanup (images+volumes+builder)"
	@echo "  make clean-logs            Remove old log files (dry-run)"
	@echo "  make clean-caches-safe      Remove safe caches (dry-run)"
	@echo "  make clean-safe             Docker + safe caches + logs (executes immediately)"
	@echo "  make clean-disk             Full cleanup (Docker + caches)"

clean-images: ## Remove unused Docker images
	@echo "Removing unused Docker images..."
	@docker image prune -a -f
	@echo "✓ Docker images cleaned"

clean-docker-volumes: ## Remove unused Docker volumes
	@echo "Removing unused Docker volumes..."
	@docker volume prune -f
	@echo "✓ Docker volumes cleaned"

clean-docker-builder: ## Remove Docker build cache
	@echo "Removing Docker builder cache..."
	@docker builder prune -f
	@echo "✓ Docker builder cache cleaned"

clean-docker: clean-images clean-docker-volumes clean-docker-builder ## Full Docker cleanup (images + volumes + builder)
	@echo "✓ Docker cleanup complete"

docker-clean: ## Stop and remove all bot containers (safe, preserves data)
	@echo "Stopping docker compose services..."
	docker compose down 2>/dev/null || true
	@echo "Removing exited containers..."
	docker container prune -f --filter "status=exited" 2>/dev/null || true
	@echo "✓ Docker cleaned (images and volumes preserved)"

docker-deep-clean: ## Remove all docker images and volumes (WARNING: deletes data)
	@echo "⚠️  WARNING: This will PERMANENTLY DELETE all Docker containers, images, and volumes"
	@echo ""
	@echo "Data that will be lost:"
	@echo "  • PostgreSQL databases (all bot data)"
	@echo "  • NATS message history"
	@echo "  • Ollama model cache"
	@echo "  • Any persistent data mounted in volumes (including data from OTHER PROJECTS)"
	@echo ""
	@echo "This is only safe if you're NOT using Docker for other projects."
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker compose down -v 2>/dev/null || true; \
		echo "Removing unused images..."; \
		docker image prune -a -f 2>/dev/null || true; \
		echo "Removing unused volumes..."; \
		docker volume prune -f 2>/dev/null || true; \
		echo "✓ Deep clean complete"; \
	else \
		echo "Cancelled"; \
	fi

clean-logs: ## Remove old logs (dry-run by default; LOG_RETENTION_DAYS=14 CLEAN_LOGS_APPLY=1)
	@DAYS="$${LOG_RETENTION_DAYS:-14}"; \
	APPLY="$${CLEAN_LOGS_APPLY:-0}"; \
	echo "Scanning logs older than $$DAYS day(s)..."; \
	files="$$( \
		( \
			find "$$HOME/Library/Logs" -type f -mtime +$$DAYS 2>/dev/null; \
			find /tmp -maxdepth 1 -type f -name '*.log' -mtime +$$DAYS 2>/dev/null \
		) | awk 'NF' \
	)"; \
	if [ -z "$$files" ]; then \
		echo "✓ No matching old logs found."; \
		exit 0; \
	fi; \
	count="$$(printf "%s\n" "$$files" | awk 'NF' | wc -l | tr -d ' ')"; \
	echo "Found $$count old log file(s)."; \
	echo "$$files" | sed 's/^/  - /'; \
	if [ "$$APPLY" != "1" ]; then \
		echo ""; \
		echo "Dry-run only. To delete, run:"; \
		echo "  CLEAN_LOGS_APPLY=1 make clean-logs LOG_RETENTION_DAYS=$$DAYS"; \
		exit 0; \
	fi; \
	echo ""; \
	echo "Deleting listed log files..."; \
	printf "%s\n" "$$files" | while IFS= read -r file; do rm -f "$$file"; done; \
	echo "✓ Old logs removed."

clean-caches-safe: ## Remove safe cache folders (dry-run by default; CLEAN_CACHES_APPLY=1)
	@APPLY="$${CLEAN_CACHES_APPLY:-0}"; \
	CACHE_DIRS="$$HOME/Library/Caches/go-build $$HOME/Library/Caches/Homebrew $$HOME/Library/Caches/ms-playwright $$HOME/.cache/go-build"; \
	echo "Scanning safe cache targets..."; \
	for d in $$CACHE_DIRS; do \
		if [ -d "$$d" ]; then \
			size="$$(du -sh "$$d" 2>/dev/null | awk '{print $$1}')"; \
			echo "  - $$d ($$size)"; \
		fi; \
	done; \
	if [ "$$APPLY" != "1" ]; then \
		echo ""; \
		echo "Dry-run only. To clear, run:"; \
		echo "  CLEAN_CACHES_APPLY=1 make clean-caches-safe"; \
		exit 0; \
	fi; \
	echo ""; \
	echo "Clearing cache directory contents..."; \
	for d in $$CACHE_DIRS; do \
		if [ -d "$$d" ]; then \
			rm -rf "$$d"/*; \
			echo "  ✓ Cleared $$d"; \
		fi; \
	done; \
	echo "✓ Safe caches removed."

clean-safe: ## Docker + safe caches + old logs (no app state reset)
	@echo "Running safe cleanup (Docker + safe caches + old logs)..."
	@$(MAKE) clean-docker
	@$(MAKE) clean-caches-safe CLEAN_CACHES_APPLY=1
	@$(MAKE) clean-logs CLEAN_LOGS_APPLY=1 LOG_RETENTION_DAYS="$${LOG_RETENTION_DAYS:-14}"
	@echo "✓ Safe cleanup complete."

clean-disk: clean-docker clean-caches-safe ## Full disk cleanup (Docker + safe caches)
	@CLEAN_CACHES_APPLY=1 $(MAKE) clean-caches-safe
	@echo ""
	@echo "═══════════════════════════════════════"
	@echo "  ✓ Full disk cleanup complete!"
	@echo "═══════════════════════════════════════"

docker-health: ## Show Docker disk usage and diagnostics
	@echo "Docker Disk Usage:"
	docker system df
	@echo ""
	@echo "Running Containers:"
	docker ps --format "table {{.Names}}\t{{.Status}}"
	@echo ""
	@echo "To free up space:"
	@echo "  make disk-check           # Full disk usage summary"
	@echo "  make docker-clean         # Stop services, remove exited containers"
	@echo "  make clean-images         # Remove unused Docker images"
	@echo "  make clean-docker         # Full Docker cleanup"
	@echo "  make clean-safe           # Docker + safe caches + logs"
	@echo "  make docker-deep-clean    # Remove everything (warning: deletes data)"

# --- Local Registry ---

registry-setup: ## Start local Docker registry (REGISTRY_PORT=32000)
	@if curl -s http://localhost:$(REGISTRY_PORT)/v2/_catalog >/dev/null 2>&1; then \
		echo "✓ Registry already running on port $(REGISTRY_PORT)"; \
	else \
		echo "Starting registry on port $(REGISTRY_PORT)..."; \
		docker run -d \
			--name bot-army-registry \
			-p $(REGISTRY_PORT):5000 \
			-v bot-army-registry-data:/var/lib/registry \
			--restart unless-stopped \
			registry:2 >/dev/null; \
		sleep 2; \
		if curl -s http://localhost:$(REGISTRY_PORT)/v2/_catalog >/dev/null 2>&1; then \
			echo "✓ Registry running on port $(REGISTRY_PORT)"; \
		else \
			echo "✗ Registry failed to start" >&2; exit 1; \
		fi; \
	fi
	@echo "Images in $(REGISTRY):"
	@curl -s http://$(REGISTRY)/v2/_catalog | python3 -c "import json,sys; cats=json.load(sys.stdin); [print('  '+r) for r in cats.get('repositories',[])]" 2>/dev/null || echo "  (registry not reachable)"

registry-build: build ## Build all core bot images tagged for local registry
	@echo "Building core bot images for $(REGISTRY)..."
	@./scripts/registry-build.sh
	@echo ""
	@echo "✓ Images built. Push with: make registry-push"

registry-push: ## Push built images to local registry (REGISTRY=localhost:32000)
	@echo "Pushing images to $(REGISTRY)..."
	@./scripts/registry-push.sh
	@echo ""
	@echo "✓ Images pushed to $(REGISTRY)"

registry-publish: registry-build registry-push ## Build and push to local registry
