#!/bin/bash
set -e

echo "=== Starting Database Migration ==="
echo "Mounting migrate_db.py and running migrations..."

# Run migration inside the container
docker-compose run --rm --no-deps \
  -v "$(pwd)/migrate_db.py:/opt/migrate_db.py:ro" \
  -e MARZBAN_DB_URL=sqlite:////var/lib/marzban/db.sqlite3 \
  marzban \
  python3 /opt/migrate_db.py

echo "=== Migration completed ==="
echo "Checking database tables..."

# Check if database was created
docker-compose run --rm --no-deps \
  marzban \
  sqlite3 /var/lib/marzban/db.sqlite3 ".tables"

echo "=== Database migration successful! ==="
