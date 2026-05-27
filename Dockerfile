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

# Fetch and compile library deps
WORKDIR /repos/bot_army_library_core
RUN mix deps.get --only ${MIX_ENV} && mix deps.compile
WORKDIR /repos/bot_army_library_runtime
RUN mix deps.get --only ${MIX_ENV} && mix deps.compile
WORKDIR /repos/bot_army_library_learning
RUN mix deps.get --only ${MIX_ENV} && mix deps.compile

# Copy full library source and compile
COPY bot_army_library_core/ bot_army_library_core/
COPY bot_army_library_runtime/ bot_army_library_runtime/
COPY bot_army_library_learning/ bot_army_library_learning/

WORKDIR /repos/bot_army_library_core
RUN mix compile
WORKDIR /repos/bot_army_library_runtime
RUN mix compile
WORKDIR /repos/bot_army_library_learning
RUN mix compile

# =============================================
# Phase 2: Bot-specific build (extends base)
# =============================================
FROM base AS build

ARG BOT_NAME
ARG BOT_REPO
ARG MIX_ENV=prod

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
ELIXIRSCRIPT
elixir /tmp/fix_deps.exs
BUILDfix

RUN mix deps.get --only ${MIX_ENV} && mix deps.compile

# Copy bot source and compile
COPY ${BOT_REPO}/ ${BOT_REPO}/
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

# Copy entrypoint script that handles database creation and migrations
COPY scripts/docker-entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENV BOT_NAME=${BOT_NAME}
ENV DB_HOST=${DB_HOST:-postgres}
ENV DB_PORT=${DB_PORT:-5432}

ENTRYPOINT ["/app/entrypoint.sh"]