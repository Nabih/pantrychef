#!/usr/bin/env bash
# Load generated COPY files into an empty/existing Postgres and refresh stats.
# Generate the files first with: python3 Tools/build_postgres.py --files
set -euo pipefail

: "${DATABASE_URL:?set DATABASE_URL, e.g. postgres://pantry:pass@127.0.0.1:5432/pantry}"

cd "$(dirname "$0")/.."

for table in categories ingredients recipes recipe_ingredients; do
    if [ ! -f "build/$table.csv" ]; then
        echo "missing build/$table.csv — run Tools/build_postgres.py --files" >&2
        exit 1
    fi
done

bash db/migrate.sh

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q \
    -c "TRUNCATE recipe_ingredients, recipes, ingredients, categories CASCADE"

for table in categories ingredients recipes recipe_ingredients; do
    echo "loading $table"
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q \
        -c "\copy $table FROM '$PWD/build/$table.csv' WITH (FORMAT csv)"
done

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -c "VACUUM (ANALYZE)"
echo "loaded"
