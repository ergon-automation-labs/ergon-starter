#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Phase 02 — install with the workarounds for the pitfalls surfaced in phase 01.
#
# Workaround map:
#   P1  docker group membership requires a FRESH login session after
#       install.sh's `usermod -aG docker`. → run this script from a NEW
#       `vagrant ssh` session (this script refuses to run otherwise).
#   P2  install.sh exports REGISTRY=localhost:32000; the Makefile's
#       "build from source" branch still inherits it, so
#       quickstart-default.sh skips cloning and generates an image-only
#       compose file pointing at the EMPTY local registry.
#       → run with `env -u REGISTRY`.
#   P3  Dockerfile does `COPY scripts/docker-entrypoint.sh` with build
#       context ./repos, but nothing creates repos/scripts/docker-entrypoint.sh
#       (starter has it at repo root; no public bot repo carries it).
#       → stage it into repos/scripts/ before `docker compose up --build`.
#   P4  bot repos pinned/cloned at an older commit miss later fixes.
#       → step 60 fast-forwards every repos/* clone to origin before build
#         (observed 2026-09-06: bridge_lite release name fix landed after
#         the first clone).
#
# RESUMABLE: each step leaves a marker in ~/.phase02/markers/ (VM disk,
# survives reboots). Rerunning the script skips completed steps and retries
# the failed one. Docker's layer cache makes the big build cheap to retry.
#
# WATCHABLE: log tees to BOTH ~/logs/02-install-fixed.log (VM, survives
# reboot) and /vagrant/logs/02-install-fixed.log (shared folder — readable
# from the host at vagrant-test/logs/). A single-line live status lands in
# /vagrant/logs/02-status.txt.
#
# Run it detached so it survives tool timeouts:
#   vagrant ssh -c "nohup bash /vagrant/scripts/02-install-fixed.sh >/dev/null 2>&1 & echo started"
# then poll from the host:
#   cat vagrant-test/logs/02-status.txt
#   tail -20 vagrant-test/logs/02-install-fixed.log
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

LOG="$HOME/logs/02-install-fixed.log"
HOST_LOG="/vagrant/logs/02-install-fixed.log"
STATUS="/vagrant/logs/02-status.txt"
MARKERS="$HOME/.phase02/markers"
mkdir -p "$HOME/logs" /vagrant/logs "$MARKERS"
exec > >(tee -a "$LOG" "$HOST_LOG") 2>&1

hr() { echo "═══════════════════════════════════════════════════════════"; }
status() { printf '%s | %-8s | %s\n' "$(date -Is)" "$1" "$2" > "$STATUS"; }

run_step() {
  local name="$1"; shift
  if [ -f "$MARKERS/$name.done" ]; then
    echo "↷ skip $name (already done)"
    status SKIP "$name"
    return 0
  fi
  echo "▶ STEP $name  $(date -Is)"
  status RUNNING "$name"
  if "$@"; then
    touch "$MARKERS/$name.done"
    echo "✓ done $name  $(date -Is)"
    status DONE "$name"
    return 0
  fi
  echo "✗ FAILED at step $name — rerun this script to resume from here"
  status FAILED "$name"
  exit 1
}

# ── step functions ───────────────────────────────────────────────────────────

step_10_docker_check() {
  if ! docker info >/dev/null 2>&1; then
    echo "✗ docker daemon not reachable in this session."
    echo "  If this is the same session that ran phase 01, exit and start a NEW"
    echo "  'vagrant ssh' session first (P1 workaround = fresh login)."
    return 1
  fi
  echo "✓ docker reachable: $(docker --version) / $(docker compose version --short)"
}

step_20_installer() {
  # Idempotent: the installer is skipped when ~/bot-army already exists.
  cd "$HOME/bot-army" 2>/dev/null && return 0
  echo "── ~/bot-army missing — running the documented installer (expect P2/P3 death, captured) ──"
  curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/ergon-starter/main/install.sh | bash -s -- --default \
    || echo "NOTE: installer exited non-zero (captured above) — continuing with workarounds"
  cd "$HOME/bot-army" || { echo "✗ ~/bot-army still missing"; return 1; }
}

step_30_make_build() {
  cd "$HOME/bot-army" || return 1
  env -u REGISTRY make build
}

step_40_quickstart() {
  cd "$HOME/bot-army" || return 1
  env -u REGISTRY ./scripts/quickstart-default.sh
}

step_50_entrypoint_stage() {
  cd "$HOME/bot-army" || return 1
  mkdir -p repos/scripts
  cp scripts/docker-entrypoint.sh repos/scripts/docker-entrypoint.sh
  ls -la repos/scripts/
}

step_60_refresh_repos() {
  # P4: fast-forward repos/* to origin so reruns pick up fixes pushed
  # since the first clone. Non-fatal per repo (logged).
  # P6: the ROOT starter clone (~/bot-army itself) must refresh too —
  # Dockerfile/quickstart fixes land on origin, but a stale root clone
  # keeps building with the old file. Two full rebuilds (2026-09-06) were
  # burned before this was found: repos refreshed, root did not.
  cd "$HOME/bot-army" || return 1
  if git fetch origin >/dev/null 2>&1 \
     && git pull --ff-only origin >/dev/null 2>&1; then
    echo "  ↻ ROOT: $(git log --oneline -1)"
  else
    echo "  ⚠️  ROOT: ff-pull failed (local changes?) — leaving as-is"
  fi
  local rc=0
  for d in repos/*/; do
    [ -d "$d/.git" ] || continue
    if git -C "$d" fetch origin >/dev/null 2>&1 \
       && git -C "$d" pull --ff-only origin >/dev/null 2>&1; then
      echo "  ↻ $(basename "$d"): $(git -C "$d" log --oneline -1)"
    else
      echo "  ⚠️  $(basename "$d"): ff-pull failed (detached HEAD or diverged) — leaving as-is"
    fi
  done
  return 0
}

step_70_compose_up() {
  cd "$HOME/bot-army" || return 1
  echo "── build + start: 14 Elixir bots from source (the long one) ──"
  echo "start: $(date -Is)"
  DOCKER_BUILDKIT=1 COMPOSE_PARALLEL_LIMIT=3 docker compose up -d --build
  local rc=$?
  echo "compose up exit: $rc   end: $(date -Is)"
  return $rc
}

step_80_status_snapshot() {
  cd "$HOME/bot-army" || return 1
  docker compose ps
  echo "-- repos cloned --";  ls repos/ | head -25
  echo "-- compose services --"; grep -E "^  [a-z_0-9]+:" docker-compose.yml || true
  return 0
}

# ── run ──────────────────────────────────────────────────────────────────────
hr
echo "PHASE 02 — fixed flow ($(date -Is))   [resumable; markers: $MARKERS]"
hr

run_step 10-docker-check step_10_docker_check
run_step 20-installer     step_20_installer
run_step 30-make-build    step_30_make_build
run_step 40-quickstart    step_40_quickstart
run_step 50-entrypoint-stage step_50_entrypoint_stage
echo '↻ refresh-repos: always runs (staleness guard, no marker)'
status RUNNING 60-refresh-repos
step_60_refresh_repos || true
status DONE 60-refresh-repos
run_step 70-compose-up    step_70_compose_up
run_step 80-status-snapshot  step_80_status_snapshot

status PHASE02-COMPLETE "all steps done"
hr
echo "PHASE 02 DONE — logs: $LOG (+ host copy /vagrant/logs/02-install-fixed.log)"
hr
exit 0