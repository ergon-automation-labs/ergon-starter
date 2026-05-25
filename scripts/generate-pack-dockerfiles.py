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

def generate_dockerfile(pack, channel="stable", registry="ergon-automation-labs"):
    """Generate Dockerfile content for a pack."""

    # Stage 1: Copy bot binaries from individual images
    stages = []
    for i, bot in enumerate(pack['bots']):
        repo = bot['repo']
        binary = bot['binary']
        stages.append(f"FROM {registry}/{repo}:{channel} as {binary}")

    stages_str = "\n".join(stages)

    # Stage 2: Combine into final image
    copy_commands = []
    for bot in pack['bots']:
        binary = bot['binary']
        copy_commands.append(f"COPY --from={binary} /app/bin/{binary} /usr/local/bin/")

    copy_str = "\n".join(copy_commands)

    # Build startup script (start all bots in background)
    start_commands = []
    for bot in pack['bots']:
        binary = bot['binary']
        start_commands.append(f"{binary} start &")

    start_script = "\n".join(start_commands)

    dockerfile = dedent(f"""
        # Auto-generated Dockerfile for {pack['name']} pack
        # Generated from config/packs-docker.toml
        # Do not edit manually; regenerate with: ./scripts/generate-pack-dockerfiles.py

        ARG CHANNEL={channel}
        ARG REGISTRY={registry}

        # Stage 1: Import bot binaries from individual images
        {stages_str}

        # Stage 2: Assemble final image
        FROM erlang:26-alpine

        # Copy bot binaries from stages
        {copy_str}

        # Install runtime dependencies
        RUN apk add --no-cache \\
            bash \\
            curl \\
            ca-certificates

        # Health check
        HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \\
            CMD curl -f http://localhost:8888/health || exit 1

        # Start all bots
        CMD ["sh", "-c", "{start_script}\\ntail -f /dev/null"]
    """).strip()

    return dockerfile

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
    registry = settings.get('registry', 'ergon-automation-labs')

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
