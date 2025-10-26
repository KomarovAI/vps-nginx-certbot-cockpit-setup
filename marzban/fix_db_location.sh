#!/bin/bash
set -e

echo "=== Fixing Database Location ==="

# Move the database from /code/var/lib/marzban/db.sqlite3 to /var/lib/marzban/db.sqlite3
docker-compose run --rm --no-deps marzban bash -c "
  if [ -f /code/var/lib/marzban/db.sqlite3 ]; then
    echo 'Found database at /code/var/lib/marzban/db.sqlite3'
    mkdir -p /var/lib/marzban
    cp /code/var/lib/marzban/db.sqlite3 /var/lib/marzban/db.sqlite3
    echo 'Database copied to /var/lib/marzban/db.sqlite3'
    ls -lh /var/lib/marzban/db.sqlite3
  else
    echo 'Error: Database not found at /code/var/lib/marzban/db.sqlite3'
    exit 1
  fi
"

echo "=== Database location fixed! ==="
