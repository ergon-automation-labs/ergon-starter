#!/bin/bash
# Bot Army one-line installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/ergon-starter/main/install.sh | bash
#
# What it does:
#   1. Checks prerequisites (git, docker, docker compose)
#   2. Installs Docker Desktop if not present (macOS/Linux)
#   3. Starts a local Docker registry for pre-built images
#   4. Clones the starter repo
#   5. Runs `make quickstart` (interactive wizard)
#
# For a non-interactive install with defaults (core bots + Ollama):
#   curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/ergon-starter/main/install.sh | bash -s -- --default

set -euo pipefail

REPO="ergon-automation-labs/ergon-starter"
INSTALL_DIR="bot-army"
REGISTRY_PORT="${REGISTRY_PORT:-32000}"

# --- Helpers ---
info()  { echo "  → $*"; }
ok()    { echo "  ✓ $*"; }
fail()  { echo "  ✗ $*" >&2; exit 1; }

# --- Preflight ---
echo ""
echo "═══════════════════════════════════════════"
echo "  Bot Army Installer"
echo "═══════════════════════════════════════════"
echo ""

echo "Checking prerequisites..."

command -v git >/dev/null 2>&1 || fail "git is required but not installed"
ok "git"

# --- Docker Desktop ---
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  ok "Docker Desktop"
else
  echo "  Docker not found or not running. Installing..."
  UNAME_S="$(uname -s)"
  if [ "$UNAME_S" = "Darwin" ]; then
    # macOS — check for Homebrew
    if command -v brew >/dev/null 2>&1; then
      info "Installing Docker Desktop via Homebrew..."
      brew install --cask docker
      ok "Docker Desktop installed via Homebrew"
    else
      info "Downloading Docker Desktop for Mac..."
      DMG_PATH="/tmp/Docker.dmg"
      curl -fsSL "https://desktop.docker.com/mac/main/arm64/Docker.dmg" -o "$DMG_PATH"
      hdiutil attach "$DMG_PATH" -quiet
      cp -R /Volumes/Docker/Docker.app /Applications/
      hdiutil detach /Volumes/Docker -quiet
      rm -f "$DMG_PATH"
      ok "Docker Desktop downloaded to /Applications"
    fi
    # Start Docker Desktop
    open -a Docker 2>/dev/null || true
    info "Waiting for Docker daemon to start..."
    retries=0
    until docker info >/dev/null 2>&1 || [ $retries -ge 60 ]; do
      sleep 5
      retries=$((retries + 1))
    done
    if ! docker info >/dev/null 2>&1; then
      fail "Docker Desktop did not start — open Docker Desktop manually and re-run"
    fi
    ok "Docker Desktop running"
  elif [ "$UNAME_S" = "Linux" ]; then
    info "Installing Docker Engine via convenience script..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER" 2>/dev/null || true
    sudo systemctl enable docker
    sudo systemctl start docker
    ok "Docker Engine installed and started"
  else
    fail "Unsupported OS ($UNAME_S) — install Docker Desktop manually: https://docs.docker.com/get-docker/"
  fi
fi

docker compose version >/dev/null 2>&1 || fail "docker compose v2 is required (docker compose, not docker-compose)"
ok "docker compose"

# --- Local Registry ---
echo ""
echo "Setting up local Docker registry (port ${REGISTRY_PORT})..."

if curl -s "http://localhost:${REGISTRY_PORT}/v2/_catalog" >/dev/null 2>&1; then
  ok "Registry already running on port ${REGISTRY_PORT}"
else
  # Check if a registry container exists but is stopped
  EXISTING=$(docker ps -a --filter "name=bot-army-registry" --format "{{.Names}}" 2>/dev/null || true)
  if [ -n "$EXISTING" ]; then
    info "Starting existing registry container..."
    docker start bot-army-registry >/dev/null
  else
    info "Creating registry container..."
    docker run -d \
      --name bot-army-registry \
      -p "${REGISTRY_PORT}:5000" \
      -v bot-army-registry-data:/var/lib/registry \
      --restart unless-stopped \
      registry:2 >/dev/null
  fi

  # Wait for registry to be ready
  retries=0
  until curl -s "http://localhost:${REGISTRY_PORT}/v2/_catalog" >/dev/null 2>&1 || [ $retries -ge 20 ]; do
    sleep 1
    retries=$((retries + 1))
  done
  if curl -s "http://localhost:${REGISTRY_PORT}/v2/_catalog" >/dev/null 2>&1; then
    ok "Registry running on port ${REGISTRY_PORT}"
  else
    fail "Registry failed to start on port ${REGISTRY_PORT}"
  fi
fi

# --- Clone ---
echo ""
if [ -d "$INSTALL_DIR" ]; then
  info "$INSTALL_DIR/ already exists, pulling latest..."
  git -C "$INSTALL_DIR" pull --ff-only 2>/dev/null || true
else
  info "Cloning starter repo..."
  git clone "https://github.com/${REPO}.git" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
ok "Starter repo ready"

# --- Run ---
echo ""
export DOCKER_BUILDKIT=1
export REGISTRY="localhost:${REGISTRY_PORT}"
if [ "${1:-}" = "--default" ]; then
  info "Running headless quickstart (core bots + Ollama)..."
  make quickstart-default
else
  info "Launching interactive setup wizard..."
  # Redirect stdin from /dev/tty for interactive mode when piped from curl
  make quickstart < /dev/tty
fi