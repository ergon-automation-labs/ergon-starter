#!/bin/bash
# Bot Army one-line installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/ergon-starter/main/install.sh | bash
#
# What it does:
#   1. Checks prerequisites (git, docker, docker compose)
#   2. Clones the starter repo
#   3. Runs `make quickstart` (interactive wizard)
#
# For a non-interactive install with defaults (core bots + Ollama):
#   curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/ergon-starter/main/install.sh | bash -s -- --default

set -euo pipefail

REPO="ergon-automation-labs/ergon-starter"
INSTALL_DIR="bot-army"

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

command -v docker >/dev/null 2>&1 || fail "docker is required but not installed"
ok "docker"

docker compose version >/dev/null 2>&1 || fail "docker compose v2 is required (docker compose, not docker-compose)"
ok "docker compose"

docker info >/dev/null 2>&1 || fail "Docker daemon is not running — start Docker Desktop first"
ok "Docker daemon running"

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
if [ "${1:-}" = "--default" ]; then
  info "Running headless quickstart (core bots + Ollama)..."
  make quickstart-default
else
  info "Launching interactive setup wizard..."
  # Redirect stdin from /dev/tty for interactive mode when piped from curl
  make quickstart < /dev/tty
fi
