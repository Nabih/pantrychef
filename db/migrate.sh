#!/usr/bin/env bash
# Apply pending migrations in order, recording each in schema_migrations.
set -euo pipefail

: "${DATABASE_URL:=postgres://localhost/pantry}"
export DATABASE_URL

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    text PRIMARY KEY,
    applied_at timestamptz NOT NULL DEFAULT now()
);
SQL

for file in db/migrations/*.sql; do
    version="$(basename "$file")"
    applied="$(psql "$DATABASE_URL" -tAc \
        "SELECT 1 FROM schema_migrations WHERE version = '$version'")"
    if [ "$applied" = "1" ]; then
        echo "skip  $version"
        continue
    fi

    echo "apply $version"
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -1 \
        -f "$file" \
        -c "INSERT INTO schema_migrations (version) VALUES ('$version')"
done

echo "done"
