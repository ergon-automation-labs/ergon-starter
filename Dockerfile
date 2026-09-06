# Shared multi-stage Dockerfile for Bot Army bots.
#
# Two-phase build:
#   1. Base image — compiles shared libraries (bot_army_library_*) once
#   2. Bot stage — extends base, compiles only bot-specific code
#
# Build context must be the repos/ directory (parent of all bot repos)
# so that path deps resolve correctly.
#
# docker-compose.yml sets context: ./repos/ and passes BOT_REPO + BOT_NAME.

# Cache-bust arg: change this value to force a full rebuild (e.g. after Dockerfile changes)
ARG CACHE_BUST=1

# =============================================
# Phase 1: Base image with shared libraries
# =============================================
FROM elixir:1.17.3-otp-27-alpine AS base

ARG CACHE_BUST
ARG MIX_ENV=prod
ENV MIX_ENV=${MIX_ENV}

RUN apk add --no-cache git build-base && echo "cache_bust=${CACHE_BUST}"
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /repos

# Copy only library mix.exs + mix.lock first (layer cache: deps only re-fetched when mix.exs changes)
COPY bot_army_library_core/mix.exs bot_army_library_core/mix.lock* bot_army_library_core/
COPY bot_army_library_runtime/mix.exs bot_army_library_runtime/mix.lock* bot_army_library_runtime/
COPY bot_army_library_learning/mix.exs bot_army_library_learning/mix.lock* bot_army_library_learning/

# Copy full library source FIRST, then fetch+compile deps in one step.
#
# (The previous split — mix.exs-only COPY → deps.compile → source COPY →
# mix compile — poisoned every library's compile manifest: path-dep
# siblings were "compiled" before their source existed, recording zero
# sources; the later `mix compile` then reported up-to-date and emitted
# .app metadata with ZERO beams. Every bot release inherited that and
# crashed at boot with "BotArmyLibraryRuntime.Application is not
# available". Root cause found 2026-09-06 in vagrant-test.)
COPY bot_army_library_core/ bot_army_library_core/
COPY bot_army_library_runtime/ bot_army_library_runtime/
COPY bot_army_library_learning/ bot_army_library_learning/

WORKDIR /repos/bot_army_library_core
RUN mix deps.get --only ${MIX_ENV} && mix deps.compile && mix compile
WORKDIR /repos/bot_army_library_runtime
RUN mix deps.get --only ${MIX_ENV} && mix deps.compile && mix compile
WORKDIR /repos/bot_army_library_learning
RUN mix deps.get --only ${MIX_ENV} && mix deps.compile && mix compile

# =============================================
# Phase 2: Bot-specific build (extends base)
# =============================================
FROM base AS build

ARG BOT_NAME
ARG BOT_REPO
ARG MIX_ENV=prod

# P9: NATS config for the library is boot-time-reapplied by bots whose
# runtime.exs contains a `config :bot_army_library_runtime, :nats` block —
# but bots WITHOUT that block use the library's dev default (localhost:4223)
# and never connect inside Docker (nats:4222 reachable, localhost:4223
# refused). Build-time ENV here did NOT fix it (deps' config.exs terms don't
# reach the release's sys.config — proven by experiment, a15d3db). The
# mechanism that demonstrably works is a boot-time overlay, appended below
# after the full-source COPY so it applies to every bot regardless of its
# own runtime.exs content. Values match the runtime .env (NATS_HOST=nats,
# NATS_PORT=4222) so both paths agree.
ENV NATS_HOST=nats
ENV NATS_PORT=4222

WORKDIR /repos

# Copy bot mix.exs first for dep caching
COPY ${BOT_REPO}/mix.exs ${BOT_REPO}/mix.lock* ${BOT_REPO}/

WORKDIR /repos/${BOT_REPO}

# Replace library git deps with path deps to avoid divergence.
# Public bot repos declare libraries as git deps, but libraries reference
# each other as path deps — Mix can't reconcile the mismatch.
# In Docker, all repos are siblings under /repos/, so path deps resolve correctly.
RUN <<BUILDfix
cat > /tmp/fix_deps.exs << 'ELIXIRSCRIPT'
{:ok, c} = File.read("mix.exs")
# All known dep names (old + current) → bot_army_library_* path dep
c = Enum.reduce(~w(bot_army_core bot_army_library_core bot_army_runtime bot_army_library_runtime bot_army_learning bot_army_library_learning), c, fn dep, acc ->
  suffix = dep |> String.replace_prefix("bot_army_library_", "") |> String.replace_prefix("bot_army_", "")
  lib = "bot_army_library_" <> suffix
  replacement = "{:" <> lib <> ", path: \"../" <> lib <> "\"}"
  re_bracket = Regex.compile!("\\{:" <> dep <> ",\\s*\\[.*?\\]\\}", "s")
  re_bare = Regex.compile!("\\{:" <> dep <> ",\\s*[^}]+\\}", "s")
  case Regex.replace(re_bracket, acc, replacement) do
    ^acc -> Regex.replace(re_bare, acc, replacement)
    result -> result
  end
end)
File.write!("mix.exs", c)

# Stale public mirrors (e.g. ergon-skills-base) predate the library
# rename bot_army_runtime → bot_army_library_runtime, so their code
# references BotArmyRuntime.* / BotArmyCore.* / BotArmyLearning.*
# modules that no longer exist. Rewrite the module namespace to match
# the path deps above. Runs as a no-op for current repos (no old refs).
# NOTE: the first invocation (deps-caching layer) has no lib/ yet —
# wildcard finds nothing; the re-invocation after the full-source COPY
# does the actual rewrite.
paths = Path.wildcard("lib/**/*.{ex,exs}") ++ Path.wildcard("config/*.{ex,exs}")
Enum.each(paths, fn path ->
  src = File.read!(path)
  patched =
    src
    |> String.replace("BotArmyRuntime.", "BotArmyLibraryRuntime.")
    |> String.replace("BotArmyCore.", "BotArmyLibraryCore.")
    |> String.replace("BotArmyLearning.", "BotArmyLibraryLearning.")
  if patched != src, do: File.write!(path, patched)
end)
ELIXIRSCRIPT
elixir /tmp/fix_deps.exs
BUILDfix

RUN mix deps.get --only ${MIX_ENV} && mix deps.compile

# Copy bot source and compile.
# WORKDIR /repos is load-bearing (same trap as the base stage): the deps
# steps above leave WORKDIR at /repos/${BOT_REPO}, so a relative COPY
# nests the bot's source inside itself — mix compiles nothing and the
# release ships without its own Application module
# (e.g. "BotArmyGtd.Application.start/2 is undefined").
WORKDIR /repos
COPY ${BOT_REPO}/ ${BOT_REPO}/

# The full-source COPY clobbers the BUILDfix-patched mix.exs with the
# repo's git-dep version. Re-apply the patch — deps/ symlinks and
# mix.lock already match this form — then compile.
WORKDIR /repos/${BOT_REPO}
RUN elixir /tmp/fix_deps.exs

# P9: append the NATS boot-time overlay to the bot's runtime.exs (created
# if absent). Evaluated at RELEASE BOOT with the container's env — the same
# mechanism the six working bots use in their own runtime.exs. Appended LAST
# so it wins the config merge; Config.Reader deep-merges keyword lists, so
# bots that also set ping_interval/max_reconnect_attempts keep those keys.
# Guarded against :test so hermetic test runs inside the image are untouched.
RUN printf '%s\n' \
    '' \
    '# ── Starter overlay (P9): NATS servers from env, evaluated at boot ──' \
    'if config_env() != :test do' \
    '  nats_host = System.get_env("NATS_HOST", "nats")' \
    '  nats_port = String.to_integer(System.get_env("NATS_PORT", "4222"))' \
    '  config :bot_army_library_runtime, :nats,' \
    '    servers: [{nats_host, nats_port}]' \
    'end' \
    >> config/runtime.exs

RUN mix compile
RUN mix release ${BOT_NAME}

# =============================================
# Runtime stage
# =============================================
FROM alpine:3.22 AS runtime

ARG BOT_NAME
ARG BOT_REPO

RUN apk add --no-cache libstdc++ openssl ncurses-libs netcat-openbsd

WORKDIR /app

COPY --from=build /repos/${BOT_REPO}/_build/prod/rel/${BOT_NAME} ./

# P8: ship the bot's lib SOURCE (mix releases contain compiled beams only).
# The entrypoint greps release.ex to find the Release module and run
# migrations via the shared MigrationRunner — without this copy the search
# finds nothing and migrations are silently skipped ("No Release module
# found") on every bot, every fresh install.
COPY --from=build /repos/${BOT_REPO}/lib /app/lib_src

# Copy entrypoint script that handles database creation and migrations
COPY scripts/docker-entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV BOT_NAME=${BOT_NAME}
ENV DB_HOST=${DB_HOST:-postgres}
ENV DB_PORT=${DB_PORT:-5432}

ENTRYPOINT ["/app/entrypoint.sh"]