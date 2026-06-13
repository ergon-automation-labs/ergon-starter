#!/usr/bin/env python3
"""
Syncs bot shell capabilities to bot-army-shell registry format.

Reads catalog/bots.json (from repos-public.toml) and generates:
  - ~/.config/bot-army-shell/registry/<bot>.json
  - Updates enabled.json with shell capabilities

Usage:
  ./scripts/sync-shell-registry.py
  make shell-sync

Output:
  ~/.config/bot-army-shell/registry/  (per-bot capability files)
  ~/.config/bot-army-shell/enabled.json  (user's enabled bots)
"""

import json
import os
import sys
from pathlib import Path

# Paths
SCRIPT_DIR = Path(__file__).parent.resolve()
STARTER_ROOT = SCRIPT_DIR.parent
CATALOG_FILE = STARTER_ROOT / "catalog" / "bots.json"

# Shell registry paths (same as bot-army-shell expects)
SHELL_CONFIG_DIR = Path.home() / ".config" / "bot-army-shell"
SHELL_REGISTRY_DIR = SHELL_CONFIG_DIR / "registry"
SHELL_ENABLED_FILE = SHELL_CONFIG_DIR / "enabled.json"


def load_bots():
    """Load bots from starter's catalog/bots.json"""
    if not CATALOG_FILE.exists():
        print(f"Error: {CATALOG_FILE} not found")
        print("Run 'make sync' first to generate catalog/bots.json")
        sys.exit(1)

    with open(CATALOG_FILE) as f:
        return json.load(f)


def get_shell_capabilities(bot):
    """
    Determine shell capabilities for a bot based on its category/name.
    Returns dict with shell plugin info.
    """
    name = bot.get("name", "")
    category = bot.get("category", "core")

    # Default capabilities
    capabilities = {
        "enabled": True,
        "plugins": [],
        "nats_subjects": [],
        "terminal_features": [],
    }

    # Per-bot capabilities
    plugin_name = f"bot-army-{name}.zsh"

    # Core bots with full shell integration
    if category == "core":
        capabilities.update({
            "plugins": [plugin_name],
            "nats_subjects": [f"{name}.task.*", f"{name}.project.*"],
            "terminal_features": ["prompt", "title", "menu"],
        })

    # Areas pack bots (fitness, chore, rpg)
    if category == "areas":
        capabilities.update({
            "plugins": [plugin_name],
            "nats_subjects": [f"{name}.task.*", f"{name}.session.*"],
            "terminal_features": ["prompt", "title"],
        })

    # Social media / research bots (lightweight)
    if category in ["social_media", "research"]:
        capabilities.update({
            "plugins": [plugin_name],
            "nats_subjects": [f"{name}.update.*"],
            "terminal_features": ["status"],
        })

    return capabilities


def sync_registry():
    """Sync shell registry from catalog/bots.json"""
    print("Syncing shell registry from bot catalog...")
    print()

    # Load bots
    bots = load_bots()

    # Ensure registry directory exists
    SHELL_REGISTRY_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Registry directory: {SHELL_REGISTRY_DIR}")

    # Process each bot
    enabled_bots = {}
    registry_count = 0

    for bot in bots:
        name = bot.get("name", "unknown")
        release_name = bot.get("release_name", name + "_bot")

        # Get shell capabilities
        capabilities = get_shell_capabilities(bot)

        # Write registry file
        registry_file = SHELL_REGISTRY_DIR / f"{name}.json"
        with open(registry_file, "w") as f:
            json.dump({
                "name": name,
                "release_name": release_name,
                "version": bot.get("channel_ref", "unknown"),
                "category": bot.get("category", "unknown"),
                **capabilities,
                "registry_at": bot.get("remote", ""),
            }, f, indent=2)

        registry_count += 1
        print(f"  ✓ {name}: {', '.join(capabilities['terminal_features'])}")

        # Add to enabled if shell is enabled
        if capabilities.get("enabled", False):
            enabled_bots[name] = {
                "enabled": True,
                "installed": True,
                "plugins": capabilities["plugins"],
            }

    # Write enabled.json
    with open(SHELL_ENABLED_FILE, "w") as f:
        json.dump({
            "version": "1.0",
            "generated_at": "auto",
            "bots": enabled_bots,
        }, f, indent=2)

    print()
    print(f"✓ Synced {registry_count} bots to shell registry")
    print(f"  Enabled: {len(enabled_bots)} bots")
    print(f"  Files: {SHELL_ENABLED_FILE}")
    print()


def main():
    """Main entry point"""
    print("=" * 60)
    print("  Bot Army Shell Registry Sync")
    print("=" * 60)
    print()

    # Check if starter catalog exists
    if not CATALOG_FILE.exists():
        print(f"Error: {CATALOG_FILE} not found")
        print("Run 'make sync' first to generate catalog/bots.json")
        sys.exit(1)

    sync_registry()


if __name__ == "__main__":
    main()
