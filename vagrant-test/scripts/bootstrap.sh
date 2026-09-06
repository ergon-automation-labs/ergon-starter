#!/usr/bin/env bash
# Bootstrap: bare prerequisites only. Docker is intentionally NOT installed
# here — install.sh owns that step and we are testing it.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq \
  git curl make python3 ca-certificates gnupg lsb-release

# python3 comes with pip-free minimal env on 24.04; quickstart-default.sh
# uses `python3 -c` only, so no extra pip packages are needed.

mkdir -p /home/vagrant/logs
chown -R vagrant:vagrant /home/vagrant/logs

echo "✓ bootstrap done: $(git --version) / $(python3 --version) / $(make --version | head -1)"
echo "  (docker deliberately not installed — phase 01 tests install.sh's own docker path)"