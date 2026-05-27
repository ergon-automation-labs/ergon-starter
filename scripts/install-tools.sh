#!/bin/bash
# Install host-side tools for Bot Army: graphify + ripgrep
#
# Usage: ./scripts/install-tools.sh
#
# Detects OS and uses the appropriate package manager.
# Safe to re-run — skips already-installed tools.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi
      ;;
    *) echo "unknown" ;;
  esac
}

has() { command -v "$1" >/dev/null 2>&1; }

install_ripgrep() {
  if has rg; then
    ok "ripgrep already installed ($(rg --version | head -1))"
    return 0
  fi

  local os
  os="$(detect_os)"

  echo "  Installing ripgrep..."
  case "$os" in
    macos)
      if has brew; then
        brew install ripgrep
      else
        # Fallback: download binary
        install_ripgrep_binary
      fi
      ;;
    linux|wsl)
      if has apt-get; then
        sudo apt-get update -qq && sudo apt-get install -y -qq ripgrep
      elif has dnf; then
        sudo dnf install -y ripgrep
      elif has apk; then
        sudo apk add ripgrep
      else
        install_ripgrep_binary
      fi
      ;;
    *)
      install_ripgrep_binary
      ;;
  esac

  if has rg; then
    ok "ripgrep installed ($(rg --version | head -1))"
  else
    fail "ripgrep installation failed — install manually: https://github.com/BurntSushi/ripgrep#installation"
    return 1
  fi
}

install_ripgrep_binary() {
  local arch url tmpdir
  case "$(uname -m)" in
    x86_64|amd64)  arch="x86_64-unknown-linux-musl" ;;
    aarch64|arm64) arch="aarch64-unknown-linux-musl" ;;
    *)             arch="x86_64-unknown-linux-musl" ;;  # fallback
  esac

  local version="14.1.0"
  url="https://github.com/BurntSushi/ripgrep/releases/download/${version}/ripgrep-${version}-${arch}.tar.gz"

  tmpdir="$(mktemp -d)"
  echo "    Downloading ripgrep ${version}..."
  if curl -fsSL "$url" | tar xz -C "$tmpdir" 2>/dev/null; then
    local rg_bin
    rg_bin="$(find "$tmpdir" -name 'rg' -type f | head -1)"
    if [ -n "$rg_bin" ]; then
      mkdir -p "$HOME/.local/bin"
      cp "$rg_bin" "$HOME/.local/bin/rg"
      chmod +x "$HOME/.local/bin/rg"
      export PATH="$HOME/.local/bin:$PATH"
    fi
  fi
  rm -rf "$tmpdir"
}

install_graphify() {
  if python3 -c "import graphify" 2>/dev/null; then
    local ver
    ver="$(python3 -c "import graphify; print(graphify.__version__)" 2>/dev/null || echo "unknown")"
    ok "graphify already installed (v${ver})"
    return 0
  fi

  echo "  Installing graphifyy (pip)..."
  if pip3 install graphifyy 2>/dev/null; then
    ok "graphify installed"
  elif python3 -m pip install graphifyy 2>/dev/null; then
    ok "graphify installed"
  else
    fail "graphify installation failed — try: pip3 install graphifyy"
    return 1
  fi
}

install_nats_py() {
  if python3 -c "import nats" 2>/dev/null; then
    ok "nats-py already installed"
    return 0
  fi

  echo "  Installing nats-py (pip)..."
  if pip3 install nats-py 2>/dev/null; then
    ok "nats-py installed"
  elif python3 -m pip install nats-py 2>/dev/null; then
    ok "nats-py installed"
  else
    fail "nats-py installation failed — try: pip3 install nats-py"
    return 1
  fi
}

# --- Main ---

echo ""
echo "═══════════════════════════════════════"
echo "  Bot Army — Tool Installation"
echo "═══════════════════════════════════════"
echo ""

# Check for python3
if ! has python3; then
  fail "python3 is required but not installed"
  echo "  Install Python 3: https://www.python.org/downloads/"
  exit 1
fi
ok "python3 ($(python3 --version 2>&1))"

# Check for pip
if ! python3 -c "import pip" 2>/dev/null; then
  warn "pip not found — some tools may fail to install"
fi

echo ""

errors=0

echo "Ripgrep:"
install_ripgrep || ((errors++))

echo ""
echo "Graphify:"
install_graphify || ((errors++))
install_nats_py || ((errors++))

echo ""
if [ "$errors" -eq 0 ]; then
  echo -e "${GREEN}✓ All tools installed${NC}"
  echo ""
  echo "Available commands:"
  echo "  rg              — fast code search"
  echo "  graphify        — knowledge graph extraction"
  echo "  make graphify-refresh — generate graphs for your repos"
else
  echo -e "${YELLOW}⚠ ${errors} tool(s) failed to install${NC}"
  echo "  Re-run or install manually — see errors above"
  exit 1
fi