#!/bin/sh
set -e

BOT_BIN="/app/bin/${BOT_NAME}"

# Run migrations if the release has a migrate eval
if [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
  echo "Running migrations for ${BOT_NAME}..."
  $BOT_BIN eval "${BOT_MODULE}.Release.migrate()" 2>/dev/null || \
    echo "No migrations (or no Release.migrate/0 defined)"
fi

exec $BOT_BIN start
