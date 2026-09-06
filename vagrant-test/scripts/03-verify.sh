#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Phase 03 — verify the deployment actually works: does a fresh user end up
# with a functioning Bot Army? Health-checks every service, inspects bot logs,
# counts crash-loops, and prints a PASS/FAIL summary.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

LOG="$HOME/logs/03-verify.log"
mkdir -p "$HOME/logs"
exec > >(tee -a "$LOG") 2>&1

cd "$HOME/bot-army" || { echo "✗ ~/bot-army missing"; exit 3; }

PASS=0; FAIL=0
check() { # check "<name>" <command...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  ✓ $name"; PASS=$((PASS+1))
  else
    echo "  ✗ $name"; FAIL=$((FAIL+1))
  fi
}

hr() { echo "═══════════════════════════════════════════════════════════"; }

hr
echo "PHASE 03 — deployment verification ($(date -Is))"
hr

echo
echo "== wait for services to settle (90s) =="
sleep 90

echo
echo "== compose ps =="
docker compose ps

echo
echo "== infra health =="
check "NATS client port 4222 open"          bash -c 'cat < /dev/null > /dev/tcp/localhost/54222'
check "NATS monitor /healthz"               curl -fsS http://localhost:58222/healthz
check "PostgreSQL accepts connections"      docker compose exec -T postgres pg_isready -U postgres
check "Ollama API responds"                 curl -fsS http://localhost:51434/ --max-time 5
check "MCP endpoint reachable"              bash -c 'curl -s -o /dev/null -w "%{http_code}" http://localhost:39900/mcp | grep -qE "200|400|405|406"'
check "Postgres vector extension available" docker compose exec -T postgres psql -U postgres -tAc "SELECT 1 FROM pg_available_extensions WHERE name='vector'"

echo
echo "== bots: running and stable? =="
BOT_SERVICES=$(docker compose config --services | grep -E '_bot$|_server$' | grep -v '^ollama$' || true)
for svc in $BOT_SERVICES; do
  state=$(docker compose ps --format '{{.Name}} {{.State}} {{.Status}}' 2>/dev/null | awk -v s="$svc" '$1 ~ s {print $2, $3}')
  restarts=$(docker inspect --format '{{.RestartCount}}' "$(docker compose ps -q "$svc" 2>/dev/null)" 2>/dev/null || echo "?")
  printf '  %-24s state=%s restarts=%s\n' "$svc" "${state:-MISSING}" "$restarts"
  if echo "$state" | grep -q "running" && [ "${restarts:-99}" -le 2 ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "    └─ last 15 log lines:"
    docker compose logs --tail 15 "$svc" 2>&1 | sed 's/^/       /' | head -20
  fi
done

echo
echo "== LLM wiring =="
echo "-- ollama models loaded --"
curl -fsS http://localhost:51434/api/tags 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print([m['name'] for m in d.get('models',[])] or 'NONE — bots cannot answer LLM calls until a model is pulled (docker exec bot_army_ollama ollama pull llama3.1)')" 2>/dev/null || echo "  (ollama tags unreachable)"

echo
echo "== recent errors across bot logs (last 5 min) =="
for svc in $BOT_SERVICES; do
  errs=$(docker compose logs --since 5m "$svc" 2>&1 | grep -ciE "error|crash|exit" || true)
  [ "$errs" -gt 0 ] && echo "  $svc: $errs error-ish lines" || true
done

echo
echo "== resource snapshot =="
docker system df 2>/dev/null
df -h / | tail -1
free -h | head -2

echo
hr
if [ $FAIL -eq 0 ]; then
  echo "RESULT: PASS ($PASS checks) — a fresh user ends up with a working Bot Army"
else
  echo "RESULT: FAIL — $FAIL failing check(s), $PASS passing"
fi
hr
echo "PHASE 03 DONE — see $LOG"