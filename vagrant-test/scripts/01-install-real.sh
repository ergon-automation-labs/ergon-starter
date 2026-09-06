#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Phase 01 — THE REAL USER FLOW, UNMODIFIED.
#
# Runs exactly what the README advertises for a headless install:
#   curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/ergon-starter/main/install.sh | bash -s -- --default --model gemma4:e4b
# (Round 3: gemma4:e4b — exercises the new --model flag; model is written to
# .env and pulled automatically after the stack comes up.)
#
# No workarounds. If it breaks, we capture where and why. Post-mortem state is
# dumped so phase 02 can pick up from the same point a real user would be in.
#
# NOTE: run this in the ORIGINAL ssh session (the one from `vagrant up`), so
# any group-membership effects of install.sh behave exactly as they would for
# a user who never re-logged-in mid-install.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail   # deliberately NOT -e: capture failures, keep going

LOG="$HOME/logs/01-install-real.log"
mkdir -p "$HOME/logs"
: > "$LOG"

hr() { echo "═══════════════════════════════════════════════════════════" | tee -a "$LOG"; }

hr
echo "PHASE 01 — pristine user flow ($(date -Is))" | tee -a "$LOG"
hr

echo "== pre-flight ==" | tee -a "$LOG"
{
  echo "whoami: $(whoami)  groups: $(id -nG)"
  command -v git >/dev/null && echo "git: $(git --version)" || echo "git: MISSING"
  if command -v docker >/dev/null; then
    docker info >/dev/null 2>&1 && echo "docker: present + daemon reachable" || echo "docker: present but daemon not reachable"
  else
    echo "docker: NOT INSTALLED (expected on a fresh VM — install.sh must install it)"
  fi
} | tee -a "$LOG"

echo | tee -a "$LOG"
echo "== running documented one-liner (--model gemma4:e4b) ==" | tee -a "$LOG"
set -o pipefail
curl -fsSL https://raw.githubusercontent.com/ergon-automation-labs/ergon-starter/main/install.sh | bash -s -- --default --model gemma4:e4b 2>&1 | tee -a "$LOG"
RC=${PIPESTATUS[1]}   # [1] = the piped bash installer; [0] is curl and always 0 on success
echo | tee -a "$LOG"
echo "PHASE 01 EXIT CODE: $RC" | tee -a "$LOG"

echo | tee -a "$LOG"
echo "== post-mortem state (what a real user would be left with) ==" | tee -a "$LOG"
{
  echo "-- docker --"
  command -v docker && docker --version || echo "docker binary: missing"
  docker info >/dev/null 2>&1 && echo "daemon: reachable in THIS session" || echo "daemon: NOT reachable in this session (group membership applied but session is stale)"
  echo "-- groups now --"
  id -nG
  echo "-- containers --"
  docker ps -a --format '{{.Names}}\t{{.Status}}' 2>&1 | head -10 || true
  echo "-- cloned repo --"
  ls -la "$HOME/bot-army" 2>/dev/null | head -15 || echo "~/bot-army does not exist"
  echo "-- generated files --"
  ls -la "$HOME/bot-army/docker-compose.yml" "$HOME/bot-army/.env" 2>/dev/null || true
  echo "-- repos cloned? --"
  ls "$HOME/bot-army/repos" 2>/dev/null | head -20 || echo "repos/ missing or empty"
} 2>&1 | tee -a "$LOG"

hr
echo "PHASE 01 DONE — see $LOG" | tee -a "$LOG"
hr