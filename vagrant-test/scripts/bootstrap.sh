#!/usr/bin/env bash
# Bootstrap: bare prerequisites only. Docker is intentionally NOT installed
# here — install.sh owns that step and we are testing it.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq \
  git curl make python3 ca-certificates gnupg lsb-release \
  lvm2

# ── P11 (2026-09-06, gemma4:e4b round): Ubuntu autoinstall allocates only ~half
# of the PV to the root LV. A 9.6 GB model pull + docker images blow past 30 GB
# fast. Grow the root LV to use all free VG space (online ext4 resize is safe).
ROOT_LV="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
if [ -n "$ROOT_LV" ] && command -v lvs >/dev/null 2>&1 && lvs --noheadings "$ROOT_LV" >/dev/null 2>&1; then
  VG="$(lvs --noheadings --no-suffix -o vg_name "$ROOT_LV" | tr -d ' ')"
  FREE_GB="$(vgs --noheadings --no-suffix --units g -o vg_free "$VG" 2>/dev/null | awk '{print int($1)}')"
  if [ "${FREE_GB:-0}" -gt 1 ]; then
    lvextend -l +100%FREE "$ROOT_LV" && resize2fs "$ROOT_LV" \
      || echo "  ⚠ LV grow failed (non-fatal) — root fs stays at $(df -h / | awk 'NR==2{print $2}')"
    echo "✓ root LV extended by ~${FREE_GB}G — now $(df -h / | awk 'NR==2{print $2}')"
  else
    echo "✓ root LV already using all VG space (free: ${FREE_GB:-0}G)"
  fi
else
  echo "  (root is not on LVM — skipping LV grow)"
fi

# python3 comes with pip-free minimal env on 24.04; quickstart-default.sh
# uses `python3 -c` only, so no extra pip packages are needed.

mkdir -p /home/vagrant/logs
chown -R vagrant:vagrant /home/vagrant/logs

echo "✓ bootstrap done: $(git --version) / $(python3 --version) / $(make --version | head -1)"
echo "  (docker deliberately not installed — phase 01 tests install.sh's own docker path)"