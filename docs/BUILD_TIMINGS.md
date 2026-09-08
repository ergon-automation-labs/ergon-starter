# Build Timings — What To Expect

Build times vary enormously by machine, network, and cache state. These numbers are
from our test rig so you have *some* frame of reference — yours will differ.

> **Rule of thumb:** the first build is the slow one. After caches warm
> (Docker layer cache + hex package cache + `deps/` on disk), repeat builds of the
> same combo take a fraction of the time.

## Our reference machine

| | |
|---|---|
| Host | Apple MacBook Air, **Apple M4**, 10 cores, 24 GB RAM |
| VM | Parallels VM (Ubuntu ARM64), **4 vCPU**, 11 GiB RAM, 80%+ disk usage |
| Container engine | Docker inside the VM (Compose v2, BuildKit) |
| LLM | `gemma4:e2b` via ollama, shared named volume `bot-army-combo-ollama` |

## Where the time goes (per combo, one 14-bot fleet)

| Phase | Cold-ish cache | Warm cache | Notes |
|---|---|---|---|
| `mix deps.get` (per project, 18 projects) | ~30–90 s each | seconds (no-op) | **The network-risk phase — see below** |
| `mix deps.compile` + `mix compile` (all stages) | minutes | mostly cached | Included in the docker build |
| `docker compose build` (whole fleet, all targets) | **~6 min** | **~2 min** | Measured: 366 s first combo in a batch, 114 s fourth |
| Boot + stabilization wait | ~75 s fixed + health checks | same | Harness waits 75 s, then registry/health checks |
| **Total per combo** | **~10–15 min** | **~5–8 min** | First run of a combo trends to the high end |

The harness runs combos sequentially; a full 8-combo matrix pass is therefore
**45 min – 2 h** depending on how warm the caches are.

## The network phase: `mix deps.get`

This is where builds die, not because your machine is slow, but because hex
downloads from a CDN that can have bad minutes. Things we learned the hard way:

- Hex's per-package wait is **hardcoded at 120 s** in its source
  (`Hex.SCM` / `Hex.Parallel` — no env override). One stalled tarball kills the
  whole `deps.get`.
- `HEX_HTTP_TIMEOUT=600` (set in our Dockerfiles) does *not* lift that internal
  wait; it only affects the HTTP client timeout.
- `HEX_HTTP_CONCURRENCY=1` (also set) trades parallelism for reliability on
  flaky links — sequential fetches at ~30 KB/s still complete; a single stalled
  object is what times out.
- A healthy network fetches a full library's ~30 packages in **~78 s**.

**Mitigations that work (already in the combo Dockerfiles):**
1. `RUN --mount=type=cache,target=/root/.hex mix deps.get ...` — completed
   packages bank in the BuildKit cache even if the RUN later fails, so a retry
   needs fewer downloads.
2. **Pre-warming**: run `mix deps.get` for each project in a throwaway container
   against the mounted repo dir first (`deps/` persists on disk), so the build's
   own `deps.get` becomes a seconds-long no-op. With a flaky CDN this is the
   reliable path.
3. If hex's registry API is unreachable entirely, `HEX_OFFLINE=true` turns
   `deps.get` into a pure local check — useful once `deps/` is fully populated.

## Measuring your own build

```sh
time docker compose build          # all targets
time docker compose build chore_bot   # one target
```

If your first build is dramatically slower than ours, the usual suspects are:
cold image pulls (one-time), slow hex CDN mirrors (retry or pre-warm), or
compile happening on too-few vCPUs.