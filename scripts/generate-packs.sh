#!/bin/bash
# Generates pack mix.exs files from catalog/packs.json + catalog/bots.json.
# Each pack becomes one OTP release containing multiple bot applications.
#
# Output: repos/packs/{primary,background,infra}/mix.exs + config/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKS_JSON="${ROOT_DIR}/catalog/packs.json"
BOTS_JSON="${ROOT_DIR}/catalog/bots.json"
PACKS_DIR="${ROOT_DIR}/repos/packs"

if [ ! -f "$PACKS_JSON" ] || [ ! -f "$BOTS_JSON" ]; then
  echo "Error: catalog/packs.json or catalog/bots.json not found" >&2
  exit 1
fi

echo "Generating pack releases..."

# Use python3 to join packs + bots and generate mix.exs files
python3 << 'PYEOF'
import json, os, textwrap

root = os.environ.get("ROOT_DIR", ".")
packs_dir = os.path.join(root, "repos", "packs")

with open(os.path.join(root, "catalog", "packs.json")) as f:
    packs = json.load(f)
with open(os.path.join(root, "catalog", "bots.json")) as f:
    bots_list = json.load(f)

bots_by_name = {b["name"]: b for b in bots_list}

for pack in packs:
    pack_name = pack["name"]
    release_name = pack["release_name"]
    pack_dir = os.path.join(packs_dir, pack_name)
    os.makedirs(os.path.join(pack_dir, "config"), exist_ok=True)
    os.makedirs(os.path.join(pack_dir, "lib", f"bot_army_pack_{pack_name}"), exist_ok=True)

    # Collect all bots in this pack
    pack_bots = []
    all_path_deps = set()  # track unique deps across all bots in pack

    for bot_name in pack["bots"]:
        bot = bots_by_name.get(bot_name)
        if not bot:
            print(f"  ⚠ {bot_name}: not in catalog, skipping")
            continue
        pack_bots.append(bot)

    if not pack_bots:
        print(f"  ⚠ {pack_name}: no bots found, skipping")
        continue

    # Build deps list — each bot is a path dep, plus shared libs
    deps_lines = []
    app_lines = []

    # Shared deps (always needed)
    deps_lines.append('      {:bot_army_core, path: "../../bot_army_core"}')
    deps_lines.append('      {:bot_army_runtime, path: "../../bot_army_runtime"}')

    # Check if any bot in the pack needs learning or dispatcher
    all_repos = set()
    for bot in pack_bots:
        repo = bot["repo"]
        all_repos.add(repo)
        # Read the bot's mix.exs to find its path deps
        mix_path = os.path.join(root, "repos", repo, "mix.exs")
        if os.path.exists(mix_path):
            with open(mix_path) as mf:
                for line in mf:
                    if 'path: "../bot_army_' in line:
                        dep = line.split('path: "../')[1].split('"')[0]
                        if dep not in ("bot_army_core", "bot_army_runtime"):
                            all_path_deps.add(dep)

    # Add shared path deps (learning, dispatcher, etc.)
    for dep in sorted(all_path_deps):
        if dep not in all_repos:
            deps_lines.append(f'      {{:{dep}, path: "../../{dep}"}}')

    # Add each bot as a dep
    for bot in pack_bots:
        deps_lines.append(f'      {{:{bot["app"]}, path: "../../{bot["repo"]}"}}')
        app_lines.append(f'          {bot["app"]}: :permanent')

    deps_str = ",\n".join(deps_lines)
    apps_str = ",\n".join(app_lines)

    mix_exs = textwrap.dedent(f"""\
    defmodule BotArmyPack.{pack_name.title()}.MixProject do
      use Mix.Project

      def project do
        [
          app: :bot_army_pack_{pack_name},
          version: "0.1.0",
          elixir: "~> 1.17",
          start_permanent: Mix.env() == :prod,
          deps: deps(),
          releases: [
            {release_name}: [
              applications: [
    {apps_str}
              ]
            ]
          ]
        ]
      end

      def application do
        [
          extra_applications: [:logger, :runtime_tools]
        ]
      end

      defp deps do
        [
    {deps_str}
        ]
      end
    end
    """)

    # Write mix.exs
    mix_path = os.path.join(pack_dir, "mix.exs")
    with open(mix_path, "w") as f:
        f.write(mix_exs)

    # Write minimal config — each bot reads env vars at runtime via its own Application
    config_path = os.path.join(pack_dir, "config", "config.exs")
    with open(config_path, "w") as f:
        f.write('import Config\n\nconfig :logger, level: :info\n')

    runtime_config_path = os.path.join(pack_dir, "config", "runtime.exs")
    with open(runtime_config_path, "w") as f:
        f.write('import Config\n')

    # Write minimal lib module (required for mix)
    lib_path = os.path.join(pack_dir, "lib", f"bot_army_pack_{pack_name}", "application.ex")
    with open(lib_path, "w") as f:
        f.write(textwrap.dedent(f"""\
        defmodule BotArmyPack.{pack_name.title()}.Application do
          use Application

          @impl true
          def start(_type, _args) do
            Supervisor.start_link([], strategy: :one_for_one)
          end
        end
        """))

    print(f"  ✓ {pack_name} pack: {len(pack_bots)} bots → {release_name}")

print("")
print("✓ Pack releases generated in repos/packs/")
PYEOF
