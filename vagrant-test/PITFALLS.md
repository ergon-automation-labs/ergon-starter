# Pitfalls — Bot Army Starter headless install (`curl … | bash -s -- --default`)

Findings from the Vagrant-based fresh-user reproduction
(`vagrant-test/`, Ubuntu 24.04 ARM64, Docker Engine installed by install.sh itself).

## P1 — CONFIRMED (live): Docker install succeeds, then everything after it fails
**Where:** `install.sh` Linux branch → registry setup step
**Severity:** install-blocking on a fresh Linux machine

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

## P2 — CODE-AUDIT (high confidence, phase 02 confirms): REGISTRY env leak breaks the from-source build
**Where:** `install.sh` → Makefile `quickstart-default` → `scripts/quickstart-default.sh`
**Severity:** install-blocking for the documented `--default` path

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

## P3 — CODE-AUDIT: Dockerfile COPY of an entrypoint that isn't in the build context
**Where:** `Dockerfile` runtime stage: `COPY scripts/docker-entrypoint.sh /app/entrypoint.sh`
**Severity:** build-blocking for every bot (once P2 is fixed and source builds start)

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
