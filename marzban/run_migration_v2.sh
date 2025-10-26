#!/bin/bash
set -e

echo "=== Starting Database Migration (V2) ==="
echo "Ensuring /var/lib/marzban directory exists..."

# Ensure the directory exists on the host
mkdir -p /var/lib/marzban

echo "Running migration inside container with proper path..."

# Run migration with proper environment
docker-compose run --rm --no-deps \
  -v "$(pwd)/migrate_db.py:/opt/migrate_db.py:ro" \
  marzban \
  bash -c "
    cd /code && \
    export MARZBAN_DB_URL='sqlite:////var/lib/marzban/db.sqlite3' && \
    echo 'Database URL: \$MARZBAN_DB_URL' && \
    python3 /opt/migrate_db.py
  "

echo "=== Migration completed ==="
echo "Verifying database file..."
ls -lh /var/lib/marzban/db.sqlite3

echo "Checking database tables..."
sqlite3 /var/lib/marzban/db.sqlite3 ".tables"

echo "=== Database migration successful! ==="
