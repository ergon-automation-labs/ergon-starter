# Pitfalls — Bot Army Starter headless install (`curl … | bash -s -- --default`)

Findings from the Vagrant-based fresh-user reproduction
(`vagrant-test/`, Ubuntu 24.04 ARM64, Docker Engine installed by install.sh itself).

## P1 — FIXED (commit 1e76d30): Docker install succeeds, then everything after it fails
**Where:** `install.sh` Linux branch → registry setup step
**Severity:** was install-blocking on a fresh Linux machine — fixed via `sg docker` re-exec in install.sh

`install.sh` installs Docker Engine via `get.docker.com` and runs
`sudo usermod -aG docker "$USER"`, but group membership only applies to **new**
login sessions. The very next docker command in the same script:

```
  → Creating registry container...
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

…kills the install (`set -euo pipefail` → exit). Post-mortem in the VM:

- Docker Engine 29.8.0 installed ✓, daemon running ✓
- `docker info` in-session: `permission denied` ✗ (`id -nG` lacks `docker`)
- `~/bot-army` **never cloned** — the user ends with docker installed and nothing else
- `docker compose version` passed because it doesn't need the daemon — misleading "✓"

A real user *might* guess "re-login and re-run", but nothing tells them to.
**Fix options:** after install, re-exec the remainder under `sg docker -c`, or
`exec sudo -u "$USER" -i bash ...`-style fresh-session hop, or simply detect
stale membership and print "re-login and re-run this command".

## P2 — FIXED (commit 1e76d30): REGISTRY env leak breaks the from-source build
**Where:** `install.sh` → Makefile `quickstart-default` → `scripts/quickstart-default.sh`
**Severity:** was install-blocking for the documented `--default` path — fixed with `env -u REGISTRY`

`install.sh` exports `REGISTRY=localhost:32000` before calling
`make quickstart-default`. The Makefile checks whether the registry actually
has `gtd_bot:latest`; empty registry → takes the "build from source" branch:

```make
else \
    ./scripts/quickstart-default.sh; \   # ← inherits the exported REGISTRY!
    DOCKER_BUILDKIT=1 ... docker compose up -d --build; \
fi
```

But `quickstart-default.sh` branches on `REGISTRY="${REGISTRY:-}"` too: with the
env var set it **skips cloning all repos** and generates an image-only
compose file (`image: localhost:32000/<bot>:latest`). The empty local registry
has no images → `docker compose up -d --build` fails on pull ("manifest
unknown") and **never builds from source**.

Note: running `make quickstart-default` from a manual clone does NOT hit this
(the Makefile's `REGISTRY ?=` is not exported) — only the curl-pipe path breaks.

**Fix:** `env -u REGISTRY ./scripts/quickstart-default.sh` in the Makefile's
else-branch (or `unset REGISTRY` in the script).

## P3 — FIXED (commit 1e76d30): Dockerfile COPY of an entrypoint that isn't in the build context
**Where:** `Dockerfile` runtime stage: `COPY scripts/docker-entrypoint.sh /app/entrypoint.sh`
**Severity:** was build-blocking for every bot — quickstart now stages entrypoint into repos/

Compose sets `build.context: ./repos`, so the COPY resolves to
`repos/scripts/docker-entrypoint.sh`. Nothing creates that path:
- `quickstart-default.sh` only writes `repos/.dockerignore`
- the wizard (`bot-army init`) doesn't stage it either
- none of the public bot repos carry `scripts/docker-entrypoint.sh` (verified
  via GitHub API for ergon-llm / ergon-gtd / ergon-general: all 404)
- the starter repo *does* have `scripts/docker-entrypoint.sh` — but at repo
  root, outside the build context

**Fix (one line):** after cloning, stage it:
`mkdir -p repos/scripts && cp scripts/docker-entrypoint.sh repos/scripts/`
— or change the COPY to `COPY ${BOT_REPO}/scripts/docker-entrypoint.sh` and
ship the entrypoint in each bot repo (as docs/DATABASE_MIGRATIONS.md already
instructs), or copy it in quickstart-default.sh right after the clone loop.

## P4 — Cosmetic/robustness notes
- `ergon-library-learning` in `catalog/bots.json` was renamed on GitHub to
  `ergon-library_learning` — clones still work via GitHub's rename redirect,
  but any non-following client (API checks, pinning tools) breaks.
- `install.sh` never checks free disk space; a from-source build of 14 Elixir
  bots + Ollama needs roughly 15–25 GB. A warning would save users from
  disk-full failures mid-build.
- Exit-code propagation when piped: failures inside `install.sh` are reported
  correctly on the terminal, but `curl | bash` pipelines always mask the
  installer's status unless pipefail is used.

## Status legend
- **CONFIRMED** — reproduced live in the test VM
- **CODE-AUDIT** — found by reading the install path; verification pending in phase 02
## P4 — STALENESS: repos/* clones don't track upstream fixes
**Where:** `quickstart-default.sh` clone step (runs once, ever)
**Severity:** silent drift on every re-run after a fix is published

First `quickstart-default.sh` clones each bot repo at whatever origin/main
was at that moment. Re-running the fixed flow reuses the existing clones —
nothing fast-forwards them — so any bot-side fix published after the first
attempt is invisible to every subsequent build attempt. Observed live
2026-09-06: bridge_lite's release-name fix (`bridge_lite_bot`, v0.1.5)
landed minutes after the clone; the phase-02 rerun built the OLD code and
failed with `Unknown release :bridge_lite_bot. The available releases are:
[:bridge_lite]`.

**Fix:** phase 02 gained step 60 (`refresh-repos`): `git -C repos/<bot>
pull --ff-only origin` for every clone before the compose build, logged
per repo.

## Phase-02 tooling notes (2026-09-06)
- 02-install-fixed.sh is now **resumable**: numbered steps, completion
  markers in `~/.phase02/markers/` (VM disk, survives reboots), reruns
  skip done steps and retry the failed one. Docker layer cache makes the
  long build cheap to retry.
- It is now **watchable**: log tees to `/vagrant/logs/02-install-fixed.log`
  (host-readable at `vagrant-test/logs/`), single-line live status in
  `vagrant-test/logs/02-status.txt`.
- Launch it detached so it survives tool/ssh timeouts:
  `vagrant ssh -c "nohup bash /vagrant/scripts/02-install-fixed.sh >/dev/null 2>&1 & echo started"`

## Registry policy — local-build default, registry is the explicit distribution option (2026-09-06, Abby-approved)

**Decision: the from-source flow does NOT require the registry.** `REGISTRY`
stays unset by default; compose builds images locally and runs them from
the local docker cache. The registry (which `install.sh` already
provisions: a `registry:2` container on `localhost:32000`, with
`scripts/registry-push.sh` to upload) is the explicit option for
build-once/pull-everywhere flows — host→VM distribution, CI-built
images, or mirroring air's k8s + registry pattern.

**Why not registry-by-default:** `install.sh` starts the registry but
nothing ever pushes to it — `registry-push.sh` is a separate manual step
no install path calls. A fresh user therefore gets an EMPTY registry,
and the `Makefile:120` auto-detect (`registry reachable AND has
gtd_bot → pull; else build locally`) is bypassed because `install.sh`
exports `REGISTRY` into the environment, making `quickstart-default.sh`
trust the env var over the auto-detect. Net effect pre-fix: pull from
an empty registry → every container crash-loops. That was P2.

**If the registry path is wanted for real**, the missing piece is not
provisioning — it's wiring `registry-push.sh` after `make build` so the
registry is populated whenever it's up. Until then: unset `REGISTRY`,
build locally. The Makefile's auto-detect already makes a populated
registry "just work" when present.

## P6 — ROOT starter clone never refreshed; rebuilds silently used old Dockerfile

**Symptom:** pushed Dockerfile fixes (4e89b29 WORKDIR fix, b47b906
restructure) never took effect in the VM — two full rebuilds (~45 min
each) produced identical 0-beam images because the VM's `~/bot-army`
root clone sat at 6a73b87 (pre-fix) while the 13 repos/* clones updated
correctly. Every "fix didn't work" signal was a mirage.

**Root cause:** step 60 (refresh-repos) iterated `repos/*/` only. The
root starter clone — which OWNS the Dockerfile, quickstart script, and
compose file — was never pulled.

**Fix:** step 60 now ff-pulls the root clone first (logged, non-fatal).
**Lesson:** any "refresh the tree" step must cover the tree's ROOT too,
not just its submodules. When a fix produces byte-identical behavior,
verify the FILE CONTENT actually changed in the build context before
re-deriving the root cause (`rg '<new marker line>' ~/bot-army/Dockerfile`).

## P5 — GHOST CACHE: docker base image can serve a beams-less library build
**Where:** `Dockerfile` base stage (`mix compile` of the three library repos)
**Severity:** fleet-wide crash-loop, with *green* build output

Symptom: every bot container crashes at boot with
`function BotArmyLibraryRuntime.Application.start/2 is undefined (module
not available)`, while `compose up --build` exits 0. Inside the release
image, `lib/bot_army_library_runtime-<v>/ebin/` contains ONLY
`bot_army_library_runtime.app` — zero `.beam` files.

Root cause: BuildKit served stale base-stage layers from earlier,
partially-broken builds (pre-disk-reset experiments). The library
directories in the base image contained only mix.exs/mix.lock/deps/_build
— no `lib/` source at all — so `mix compile` silently "compiled" nothing
and emitted app metadata only. Every release then packaged a runtime
without modules.

**RETRACTED 2026-09-06:** the "stale layers / ghost cache" theory above
was WRONG. A `--no-cache` full rebuild reproduced the 0-beam output
deterministically. The real mechanism (see the Dockerfile fix commits
4e89b29 + b47b906): the base stage ran `mix deps.compile` BEFORE the
full-source COPY; libraries path-dep their siblings, so each sibling was
"compiled" with no source present, recording a ZERO-SOURCE compile
manifest; the later `mix compile` trusted that manifest ("up to date")
and emitted .app metadata with zero beams — every build, forever, with
green output. Fix: copy full source FIRST, then deps.get + deps.compile
+ mix compile per library in one layer. (The WORKDIR nesting found along
the way — full-source COPYs executing after `WORKDIR
.../bot_army_library_learning` with relative destinations, burying all
three libraries' source inside the learning dir — was a second real bug,
fixed by the `WORKDIR /repos` reset in 4e89b29.)

Diagnosis path (keep this):
1. `docker run --rm --entrypoint sh <bot-image> -c "ls /app/lib/bot_army_library_runtime-*/ebin | head"`
   → app file only = packaging is broken, not the bot code.
2. `docker build -f Dockerfile --target base -t probe repos/` then count
   beams per library dir → 0 everywhere = base-stage cache ghost.
3. Context sanity: `COPY <repo>/ /probe/` in a scratch Dockerfile with the
   real context — proves `.dockerignore` is innocent.

Fix: bump the Dockerfile's `ARG CACHE_BUST` (its documented purpose), and
clear the phase-02 step-70 marker so the resumable script actually
re-runs the build (a completed run leaves the marker even when the
resulting images are broken — markers track *steps*, not *health*; phase
03 is the health gate).

## P7 — Release boots an idle skeleton when `mod:` is missing from the app spec (elixir-tools mcp)

**Symptom**: container "Up" forever, beam alive, but the app never starts — no log file, port never listens, `which_applications` shows only kernel/stdlib/elixir. The 03-verify "MCP endpoint reachable" check returned 000. **Up ≠ working** for a release whose app can't start.

**Root causes (two stacked, both in ergon-elixir-tools-mcp_server)**:
1. The repo was historically an escript/CLI tool, so it had **no `mod:`** — and the one place that matters is `def application`, whose return **overrides** the project application config. Putting `mod:` in the `project` block (v0.3.2) did nothing; the `.app` still shipped without `mod` (v0.3.3 fixed it in `application/0`). Without `mod:`, `mix release` loads the app's modules but never calls `Application.start/2`.
2. With `mod:` added, the app finally started — and then **every non-OPTIONS HTTP request returned an empty-body 500**: the HttpHandler pipeline was `plug(:cors); plug(:dispatch)` with **no `plug(:match)`**. Modern Plug's `:dispatch` does a strict `map_get(:plug_route, conn.private)` — a key only the `:match` plug populates (written against an old Plug where dispatch matched implicitly). Fixed by adding `plug(:match)` first (v0.3.6).

**Diagnostics that actually worked**:
- In-process exception capture through the router: `bin/<rel> eval "(Plug.Test.conn(:get, \"/mcp\") |> Mod.call([])) |> Map.take([:status])"` wrapped in `try/rescue` with `Exception.format(:error, e, __STACKTRACE__)` — gave the exact `router.ex:256` frame when Bandit was silently eating it.
- Do NOT trust `rpc`/bare `eval` expressions returning values through nested `vagrant ssh` quoting — output vanishes silently and reads as "no result". Wrap in `IO.inspect`/`IO.puts` and verify quoting per hop.
- `docker logs` shows nothing when the app crashes *before* logging config lands; entrypoint-only output ("Starting bot...") with a healthy BEAM = boot started no application.

**Related**: the fleet `elixir_tools_mcp_bot` crash-looped (`application_terminated, ..., shutdown`) once the app actually started — StdioHandler exits `:normal` on container stdin EOF, which still counts toward max_restarts under the default `:permanent` policy. Fixed with `Supervisor.child_spec({StdioHandler, []}, restart: :transient)` (v0.3.5). No compose changes needed.

**Phantom supervision children (synapse-lite)**: boot crashes naming modules that exist only in the private full-synapse repo (`RunRetentionScheduler`, `GoalStore`) — remove the children; check nested module paths (`BotArmySynapse.NATS.Consumer` lives in `nats/consumer.ex`) before deleting siblings. v0.1.2/v0.1.3.

**Result**: phase 03 **PASS (18/18)** — 2026-09-06.

## P8 — LIVE (found in fresh-user reproduction): every DB-using bot loops on "database does not exist" — and liveness gates don't see it

**Date:** 2026-09-06, immediately after the pristine one-liner install passed phase 03.
**Status:** FIXED in starter repo — commits `15288e7` + `3cabb9c`.

**Symptom**: phase 03 verify **PASS (18/18)** — all 16 containers Up, 0 restarts — yet bot logs
telemetry showed thousands of errors: gtd/llm/dispatcher/skills/synapse looping on
`Postgrex ... FATAL 3D000 (invalid_catalog_name) database "ergon_gtd" does not exist` (and their
own DB names), job_scheduler dialing `localhost:30003`, para_bot spamming `[NATS] Failed to
publish message`. `psql \l` showed **only the `postgres` database** — no bot DB anywhere. The
army looked perfectly healthy and was completely non-functional.

**Root causes (four, stacked)**:
1. **No bot can create its own DB.** The entrypoint creates databases via a Release module
   (`Release.create_databases()`), but: (a) public bot repos implement only `Release.migrate()`
   (shared `BotArmyLibraryRuntime.Ecto.MigrationRunner`) — `create_databases()` exists nowhere;
   (b) `mix release` images contain compiled beams only, so the entrypoint's
   `find /app/lib -name release.ex` found nothing and detection "skipped" silently. DB creation
   was a fiction on every fresh install.
2. **The old monorepo's init SQL is broken too** (`CREATE DATABASE cannot be executed from a
   function`): `DO $$ ... $$` blocks are transactional and CREATE DATABASE can't run in a
   transaction. The lifted pattern failed live on first use. Correct tool: psql `\gexec`
   (executes each SELECT's returned row as a standalone statement, no transaction). The old
   fleet evidently got its DBs through some other path (salt/manual).
3. **Bots carry old-monorepo defaults**: job_scheduler's ConfigLoader defaults to
   `localhost:30003` and ignores the generic `DATABASE_HOST` — needs
   `BOT_ARMY_JOB_DB_HOST/PORT/NAME`. Several DB names carry dev suffixes
   (`bot_army_skills_dev`, `ergon_synapse_dev`) that are the bots' real config defaults —
   match them verbatim rather than "fixing" the names.
4. **catalog/bots.json said `needs_db: false` for every bot**, so generated compose never had
   DB bots wait for postgres health.

**Fixes (all in the starter repo, commits 15288e7 + 3cabb9c)**:
- `scripts/postgres-init.sql` — creates each bot's config-default DB via `\gexec` (idempotent),
  staged by quickstart-default.sh into `postgres-init/` and mounted into the postgres service
  (`/docker-entrypoint-initdb.d`). Runs on first pgdata volume initialization only.
- Generated compose sets `BOT_ARMY_JOB_DB_HOST: postgres / PORT: 5432 / NAME: ergon_job_scheduler`
  for job_scheduler (the one bot that ignores generic DATABASE_*).
- Dockerfile runtime stage now copies the bot's `lib/` source to `/app/lib_src`; entrypoint
  searches `/app/lib_src` first — Release.migrate() actually runs instead of being skipped.
- catalog needs_db corrected → DB bots depend_on postgres service_healthy.
- `make pull-model` for the default Ollama model (LLM calls fail until a model is pulled).

**VM-side recovery (existing pgdata volume predates the fix — initdb.d only runs on FIRST init)**:
`docker compose rm -f postgres && docker volume rm bot-army_pgdata && docker compose up -d postgres`
— safe here because the volume held no data worth keeping. (Note: `compose stop` is NOT enough —
the stopped container still pins the volume; remove it.)

**Lesson — liveness ≠ function**: the 18-check verify gate proves scheduling/network/restarts,
not data-plane health. Log-telemetry sweep (error counts per container) is the missing check;
`database "..." does not exist` in any bot log should fail the gate. A future phase-04 could
add: per-container error-rate scan + DB-name-existence check + `which_applications` spot check.

**Diagnosis path (keep this)**:
1. `for b in gtd_bot llm_bot para_bot dispatcher_bot skills_bot job_scheduler_bot synapse_bot
   general_bot bridge_lite_bot graphify_cache_bot; do echo -n "$b: "; docker logs
   bot-army-$b-1 2>&1 | grep -aoE 'database "[a-z_0-9]+" does not exist' | tail -1; done`
   → per-bot attempted DB name (ground truth from the live errors, not the configs).
2. Each bot's real DB env names live in its own config/runtime.exs (grep `System.get_env` /
   `ConfigLoader.get`) — they are NOT uniform; job_scheduler uses `BOT_ARMY_JOB_*`, skills/synapse
   use prefix-cascades ending in `DATABASE_*`.
3. Postgres init failures appear in `docker logs bot-army-postgres-1` as plain psql errors —
   check there FIRST when DBs are missing after a volume re-init.

**Also**: do not run two `vagrant ssh` commands concurrently — the second dies with a machine
lock error. Serialize VM calls (or accept the retry).

## P9 — LIVE (found during P8 validation): 6 of 12 bots never connect to NATS — release config is baked at build time

**Date:** 2026-09-06, while validating the P8 fix (post-rebuild log sweep).
**Status:** FIXED in starter repo — final mechanism `501d3e3` + `b03307e` (take-1 `a15d3db` was
disproven by experiment and superseded).

**Fix evolution (worth keeping — it's the lesson)**:
- take 1 (`a15d3db`): ENV NATS_HOST/NATS_PORT in the Dockerfile build stage — NO-OP. Terms from
  deps' config.exs do NOT reach the release's sys.config; the connection code reads
  Application env at runtime, which stayed at the library default.
- take 2 (`501d3e3`): append a boot-time overlay to every bot's config/runtime.exs during the
  bot image build (the exact mechanism the six connected bots carry themselves). Immediately
  broke para/general/graphify_cache: they ship NO config/runtime.exs, and the created file
  lacked `import Config` → `undefined function config_env/0` at release boot → crash loop.
  Also learned: bare `>> config/runtime.exs` fails when the repo has no config/ dir
  (graphify_cache, para) → `mkdir -p config` first (`e646a47`).
- take 3 (`b03307e`): seed `import Config` when creating the file; drop the config_env()
  :test guard (releases never evaluate runtime.exs under :test — the guard was redundant and
  was the only reason the import was needed). Both variants parse-checked locally with
  `Code.string_to_quoted!` against real bot content BEFORE the rebuild.

**Symptom**: para/dispatcher/general/job_scheduler/elixir_tools_mcp/graphify_cache loop
`[NATS] Connection failed, retrying` + `[NATS] Failed to publish message` forever; the other 6
bots publish normally. `docker logs bot-army-nats-1` shows zero client connections from the
failing bots. `nc -zv nats 4222` inside a failing bot container SUCCEEDS — the network is fine,
the bot dials the wrong target.

**Root cause — exact split**: bots whose `config/runtime.exs` re-applies
`config :bot_army_library_runtime, :nats` at boot connect (12/12 correlation: gtd, llm, synapse,
skills, bridge_lite, surface_mcp ✓ / para, dispatcher, general, job_scheduler,
elixir_tools_mcp, graphify_cache ✗ — the ✗ set has NO runtime NATS block). Bots without the
block use the application env **baked at build time**: Mix evaluates deps' config.exs during
`mix compile`, and the library's config.exs falls back to `NATS_HOST=localhost /
NATS_PORT=4223` (the dev broker) when the build has no NATS env — which is exactly the Docker
build's situation. `nc` proves the shape: `nats:4222` reachable, `localhost:4223` refused.
The plist-built fleet never saw this because its builds ran with prod env present.

**Fix**: the Dockerfile bot build stage appends a boot-time NATS overlay to every bot's
config/runtime.exs (seeded with `import Config` when absent) — reads NATS_HOST/NATS_PORT at
release boot with the container env. Bots with runtime blocks still re-apply with identical
values from .env, so both paths agree; Config.Reader's deep merge preserves the bots' own
ping_interval/max_reconnect keys.

**Lesson**: release-time config baking means BUILD-TIME env is part of the artifact. Any
dep config that calls System.get_env is a landmine for Docker builds: either set the value in
the Dockerfile (if the deployment topology is fixed, which it is for a starter) or require the
bot's runtime.exs to re-apply it. Bots are inconsistent about which they do — the starter
must be defensive.

**Diagnosis path (keep this)**:
1. Fleet-level ground truth: `curl -s http://localhost:58222/connz` (NATS monitor) →
   `num_connections` — must be ≥ number of bot services. The nats server does NOT log client
   connects by default; the monitor API is the only cheap fleet-wide connectivity probe.
2. `docker exec <bot> nc -zv nats 4222` vs `nc -zv localhost 4223` — distinguishes network
   failure from wrong-target defaults.
3. Correlate failing bots with `grep -c 'config :bot_army_library_runtime, :nats'
   <repo>/config/runtime.exs` — 0 = relies on defaults (and pre-fix, on baked dev values).
