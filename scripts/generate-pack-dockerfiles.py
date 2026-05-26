#!/usr/bin/env python3
"""
Generate Dockerfiles for each pack from packs-docker.toml config.
Reads pack definitions and creates multi-stage builds that pull individual bot images.

Usage:
  ./scripts/generate-pack-dockerfiles.py [--channel stable|latest|nightly] [--output-dir .]
"""

import sys
import argparse
import tomllib
from pathlib import Path
from textwrap import dedent

def load_config(config_path):
    """Load TOML config file."""
    with open(config_path, 'rb') as f:
        return tomllib.load(f)

def generate_dockerfile(pack, channel="stable", registry="localhost:32000"):
    """Generate Dockerfile content for a pack."""

    # Separate required vs optional bots
    required_bots = [b for b in pack['bots'] if not b.get('optional', False)]
    optional_bots = [b for b in pack['bots'] if b.get('optional', False)]

    # Stage 1: Copy bot releases from individual images
    stages = []
    for bot in required_bots:
        binary = bot['binary']
        stages.append(f"FROM {registry}/{binary}:{channel} AS {binary}")

    stages_str = "\n".join(stages)

    # Stage 2: Copy commands
    copy_commands = []
    for bot in required_bots:
        binary = bot['binary']
        copy_commands.append(f"COPY --from={binary} /app/ /opt/bot_army/{binary}/")

    copy_str = "\n".join(copy_commands)

    # Startup script
    start_commands = []
    for bot in required_bots:
        binary = bot['binary']
        start_commands.append(f"/opt/bot_army/{binary}/bin/{binary} start &")

    start_script = "\n".join(start_commands)

    # Optional bots note
    optional_note = ""
    if optional_bots:
        names = ", ".join(b['binary'] for b in optional_bots)
        optional_note = f"\n# Optional bots (not included — add individual images separately): {names}\n"

    lines = [
        f"# Auto-generated Dockerfile for {pack['name']} pack",
        f"# Generated from config/packs-docker.toml",
        f"# Do not edit manually; regenerate with: ./scripts/generate-pack-dockerfiles.py",
        f"",
        f"ARG CHANNEL={channel}",
        f"ARG REGISTRY={registry}",
        f"",
        f"# Stage 1: Import bot releases from individual images (libraries already bundled in each release)",
    ]
    for stage in stages:
        lines.append(stage)

    lines.extend([
        f"",
        f"# Stage 2: Assemble final image",
        f"FROM erlang:27-alpine",
        f"",
        f"# Install runtime dependencies",
        f"RUN apk add --no-cache \\",
        f"    bash \\",
        f"    openssl \\",
        f"    ncurses-libs \\",
        f"    libstdc++",
        f"",
        f"# Copy bot releases from stages",
    ])
    for copy in copy_commands:
        lines.append(copy)

    if optional_note:
        lines.append(optional_note.strip())

    lines.extend([
        f"",
        f"# Health check",
        f"HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \\",
        f"    CMD curl -f http://localhost:8888/health || exit 1",
        f"",
        f"# Start all bots",
        f'CMD ["sh", "-c", "{start_script}\\ntail -f /dev/null"]',
    ])

    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description="Generate Dockerfiles for bot packs")
    parser.add_argument("--channel", default="stable", choices=["stable", "latest", "nightly"],
                        help="Release channel (default: stable)")
    parser.add_argument("--output-dir", default=".", help="Output directory for Dockerfiles")
    parser.add_argument("--config", default="config/packs-docker.toml", help="Config file path")

    args = parser.parse_args()

    config_path = Path(args.config)
    if not config_path.exists():
        print(f"Error: {config_path} not found", file=sys.stderr)
        sys.exit(1)

    try:
        config = load_config(config_path)
    except Exception as e:
        print(f"Error reading config: {e}", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    packs = config.get('packs', [])
    settings = config.get('settings', {})
    registry = settings.get('registry', 'localhost:32000')

    if not packs:
        print("No packs defined in config", file=sys.stderr)
        sys.exit(1)

    print(f"Generating Dockerfiles for {len(packs)} packs (channel: {args.channel})...")
    print()

    for pack in packs:
        pack_name = pack['name']
        output_file = output_dir / f"Dockerfile.{pack_name}"

        try:
            dockerfile = generate_dockerfile(pack, args.channel, registry)
            output_file.write_text(dockerfile)

            bot_count = len(pack['bots'])
            print(f"✓ {output_file.name:30} ({bot_count} bots)")
        except Exception as e:
            print(f"✗ {output_file.name:30} Error: {e}", file=sys.stderr)
            sys.exit(1)

    print()
    print(f"✓ Generated {len(packs)} Dockerfiles in {output_dir}")
    print()
    print("Next steps:")
    print(f"  make build-pack PACK=core CHANNEL={args.channel}")
    print(f"  docker build -f Dockerfile.core --build-arg CHANNEL={args.channel} -t ergon-automation-labs/bot-army-core:{args.channel} .")

if __name__ == "__main__":
    main()
