#!/bin/bash
# Clean the database directory
rm -rf /var/lib/marzban/*
# Run database migration inside Docker container
docker run --rm -v /var/lib/marzban:/var/lib/marzban -v $(pwd):/app komarovai/marzban-custom:v4.0 bash -c "cd /app && python3 migrate_db.py"
# Check tables
sqlite3 /var/lib/marzban/db.sqlite3 ".tables"
