#!/usr/bin/env bash
# Create (if needed) and seed the API test database.
set -euo pipefail

# Homebrew Postgres is not always on PATH for non-interactive shells.
for candidate in /opt/homebrew/opt/postgresql@17/bin /usr/local/opt/postgresql@17/bin; do
    if [ -d "$candidate" ]; then PATH="$candidate:$PATH"; fi
done
export PATH

: "${TEST_DATABASE_URL:=postgres://localhost/pantry_test}"
export TEST_DATABASE_URL

db_name="${TEST_DATABASE_URL##*/}"
db_name="${db_name%%\?*}"

createdb "$db_name" 2>/dev/null || true

cd "$(dirname "$0")/.."
DATABASE_URL="$TEST_DATABASE_URL" bash db/migrate.sh >/dev/null

psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -q -f db/fixtures.sql

echo "test database ready: $TEST_DATABASE_URL"
