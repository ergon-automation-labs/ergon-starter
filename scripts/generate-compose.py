#!/usr/bin/env python3
"""
Generate docker-compose.yml from selected packs and channel.
Creates a compose file with:
  - Infra services (nats, postgres)
  - Selected pack services
  - Profiles for optional packs

Usage:
  ./scripts/generate-compose.py --packs core,social_media --channel stable [--output docker-compose.yml]
  make generate-compose PACKS=core,social_media CHANNEL=stable
"""

import sys
import argparse
import tomllib
import json
from pathlib import Path
from textwrap import dedent

def load_config(config_path):
    """Load TOML config file."""
    with open(config_path, 'rb') as f:
        return tomllib.load(f)

def generate_compose(selected_packs, channel="stable", registry="ergon-automation-labs", ports=None):
    """Generate docker-compose.yml content.

    Args:
        selected_packs: List of pack names
        channel: Release channel (stable/latest/nightly)
        registry: Docker registry
        ports: Dict of custom ports {nats_client: 4222, nats_monitoring: 8222, postgres: 5432}
    """

    # Default ports (override with custom ports dict)
    default_ports = {
        "nats_client": 4222,
        "nats_monitoring": 8222,
        "postgres": 5432,
    }
    if ports:
        default_ports.update(ports)

    # Load pack config
    config_path = Path("config/packs-docker.toml")
    if not config_path.exists():
        raise FileNotFoundError(f"{config_path} not found")

    config = load_config(config_path)
    all_packs = {p['name']: p for p in config.get('packs', [])}

    # Validate selected packs
    for pack_name in selected_packs:
        if pack_name not in all_packs:
            raise ValueError(f"Pack '{pack_name}' not found in config")

    # Start compose structure
    compose = {
        "version": "3.9",
        "services": {},
    }

    # Infrastructure services (always required)
    compose["services"]["nats"] = {
        "image": "nats:latest",
        "ports": [f"{default_ports['nats_client']}:4222", f"{default_ports['nats_monitoring']}:8222"],
        "command": "nats-server -m 8222",
        "healthcheck": {
            "test": ["CMD", "wget", "--spider", "-q", "http://localhost:8222/varz"],
            "interval": "30s",
            "timeout": "5s",
            "retries": 3,
        },
        "networks": ["bot-army"],
    }

    compose["services"]["postgres"] = {
        "image": "postgres:15-alpine",
        "environment": {
            "POSTGRES_USER": "postgres",
            "POSTGRES_PASSWORD": "postgres",
            "POSTGRES_DB": "bot_army_dev",
        },
        "ports": [f"{default_ports['postgres']}:5432"],
        "volumes": ["postgres_data:/var/lib/postgresql/data"],
        "healthcheck": {
            "test": ["CMD-SHELL", "pg_isready -U postgres"],
            "interval": "10s",
            "timeout": "5s",
            "retries": 5,
        },
        "networks": ["bot-army"],
    }

    # Pack services
    for pack_name in sorted(selected_packs):
        pack = all_packs[pack_name]
        is_core = pack_name == "core"
        profile = [] if is_core else [pack_name]

        service = {
            "image": f"{registry}/bot-army-{pack_name}:{channel}",
            "depends_on": {
                "nats": {"condition": "service_healthy"},
                "postgres": {"condition": "service_healthy"},
            },
            "environment": {
                "NATS_SERVERS": "nats://nats:4222",
                "DATABASE_URL": f"postgres://postgres:postgres@postgres:5432/bot_army_dev",
                "MIX_ENV": "prod",
            },
            "networks": ["bot-army"],
        }

        # Add profile if optional
        if profile:
            service["profiles"] = profile

        # Add healthcheck
        service["healthcheck"] = {
            "test": ["CMD", "curl", "-f", "http://localhost:8888/health"],
            "interval": "30s",
            "timeout": "10s",
            "retries": 3,
            "start_period": "10s",
        }

        compose["services"][f"pack-{pack_name}"] = service

    # Networks and volumes
    compose["networks"] = {
        "bot-army": {
            "driver": "bridge",
        }
    }

    compose["volumes"] = {
        "postgres_data": {
            "driver": "local",
        }
    }

    return compose

def compose_to_yaml(compose):
    """Convert dict to docker-compose YAML format (simple writer, no external deps)."""
    lines = ["version: '3.9'", ""]

    lines.append("services:")
    for service_name, service_config in compose["services"].items():
        lines.append(f"  {service_name}:")
        for key, value in service_config.items():
            if isinstance(value, dict):
                lines.append(f"    {key}:")
                for k, v in value.items():
                    if isinstance(v, (list, dict)):
                        lines.append(f"      {k}: {json.dumps(v)}")
                    else:
                        lines.append(f"      {k}: {v}")
            elif isinstance(value, list):
                lines.append(f"    {key}:")
                for item in value:
                    lines.append(f"      - {item}")
            else:
                lines.append(f"    {key}: {value}")
        lines.append("")

    if "networks" in compose:
        lines.append("networks:")
        for net_name, net_config in compose["networks"].items():
            lines.append(f"  {net_name}:")
            for key, value in net_config.items():
                lines.append(f"    {key}: {value}")
        lines.append("")

    if "volumes" in compose:
        lines.append("volumes:")
        for vol_name, vol_config in compose["volumes"].items():
            lines.append(f"  {vol_name}:")
            for key, value in vol_config.items():
                lines.append(f"    {key}: {value}")

    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description="Generate docker-compose.yml from packs")
    parser.add_argument("--packs", required=True,
                        help="Comma-separated list of packs (core,social_media,learning_deepdive,areas,research)")
    parser.add_argument("--channel", default="stable", choices=["stable", "latest", "nightly"],
                        help="Release channel (default: stable)")
    parser.add_argument("--output", default="docker-compose.yml",
                        help="Output file (default: docker-compose.yml)")
    parser.add_argument("--registry", default="ergon-automation-labs",
                        help="Docker registry (default: ergon-automation-labs)")
    parser.add_argument("--nats-client-port", type=int, default=4222,
                        help="NATS client port (default: 4222)")
    parser.add_argument("--nats-monitor-port", type=int, default=8222,
                        help="NATS monitoring port (default: 8222)")
    parser.add_argument("--postgres-port", type=int, default=5432,
                        help="PostgreSQL port (default: 5432)")

    args = parser.parse_args()

    selected_packs = [p.strip() for p in args.packs.split(",")]

    # Build ports dict from args
    ports = {
        "nats_client": args.nats_client_port,
        "nats_monitoring": args.nats_monitor_port,
        "postgres": args.postgres_port,
    }

    try:
        compose = generate_compose(selected_packs, args.channel, args.registry, ports)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    # Convert to YAML
    output = compose_to_yaml(compose)

    output_path = Path(args.output)
    output_path.write_text(output)

    print(f"✓ Generated {output_path}")
    print()
    print(f"Compose includes:")
    print(f"  - Core services: nats, postgres")
    print(f"  - Packs: {', '.join(selected_packs)}")
    print(f"  - Channel: {args.channel}")
    print()
    print(f"Next steps:")
    print(f"  docker compose up                    # Run core pack")
    print(f"  docker compose --profile social_media up  # Add social_media pack")
    print(f"  docker compose logs -f pack-core     # Follow logs")

if __name__ == "__main__":
    main()
