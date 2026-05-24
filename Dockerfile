# Shared multi-stage Dockerfile for Bot Army bots.
#
# Build context must be the repos/ directory (parent of all bot repos)
# so that path deps like `{:bot_army_core, path: "../bot_army_core"}`
# resolve correctly.
#
# docker-compose.yml sets context: ./repos/ and passes BOT_REPO + BOT_NAME.

# --- Build stage ---
FROM elixir:1.17.3-otp-27-alpine AS build

ARG BOT_NAME
ARG BOT_REPO
ARG MIX_ENV=prod

RUN apk add --no-cache git build-base

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /repos

COPY . .

WORKDIR /repos/${BOT_REPO}

RUN mix deps.get --only ${MIX_ENV}
RUN mix deps.compile
RUN mix compile
RUN mix release ${BOT_NAME}

# --- Runtime stage ---
FROM alpine:3.20 AS runtime

ARG BOT_NAME
ARG BOT_REPO

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

COPY --from=build /repos/${BOT_REPO}/_build/prod/rel/${BOT_NAME} ./

ENV BOT_NAME=${BOT_NAME}

CMD /app/bin/${BOT_NAME} start
