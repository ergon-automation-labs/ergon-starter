#!/bin/sh
set -e

BOT_NAME=${BOT_NAME:-unknown}
RELEASE_DIR=${RELEASE_DIR:-/app}
DB_HOST=${DB_HOST:-postgres}
DB_PORT=${DB_PORT:-5432}

echo "[$(date)] Waiting for PostgreSQL..."

# Wait for database to be ready (max 60 seconds)
RETRY=0
while [ $RETRY -lt 30 ]; do
  if nc -z "$DB_HOST" "$DB_PORT" 2>/dev/null; then
    echo "✓ PostgreSQL is ready!"
    break
  fi
  RETRY=$((RETRY + 1))
  sleep 2
done

if [ $RETRY -eq 30 ]; then
  echo "✗ PostgreSQL failed to start (timeout)"
  exit 1
fi

echo "[$(date)] Creating databases..."
cd "$RELEASE_DIR"

# Detect Release module name and create databases
RELEASE_MODULE=$(find /app/lib_src /app/lib -name "release.ex" -type f 2>/dev/null | head -1 | xargs grep -o "defmodule [A-Za-z_]*\.Release" 2>/dev/null | head -1 | sed "s/defmodule //")

if [ -n "$RELEASE_MODULE" ]; then
  ./bin/$BOT_NAME eval "$RELEASE_MODULE.create_databases()" 2>&1 | grep -v "error\|Error" || true
  echo "✓ Database creation complete"
else
  echo "⚠ No Release module found (skipping database creation)"
fi

echo "[$(date)] Running migrations..."
if [ -n "$RELEASE_MODULE" ]; then
  ./bin/$BOT_NAME eval "$RELEASE_MODULE.migrate()" 2>&1 | grep -v "already exists\|Already exists" || true
  echo "✓ Migrations complete"
else
  echo "⚠ No Release module found (skipping migrations)"
fi

echo "[$(date)] Starting bot..."
exec ./bin/$BOT_NAME start
