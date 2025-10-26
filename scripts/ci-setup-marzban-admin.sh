#!/bin/bash
# CI script to ensure Marzban admin exists with correct credentials from secrets
set -euo pipefail

ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

if [[ -z "$ADMIN_PASSWORD" ]]; then
    echo "[ERROR] ADMIN_PASSWORD not set"
    exit 1
fi

echo "[INFO] Setting up Marzban admin: $ADMIN_USERNAME"

cd /opt/marzban

# Wait for Marzban to be ready
echo "[INFO] Waiting for Marzban to initialize..."
for i in {1..30}; do
    if docker compose exec -T marzban python -c "from app.db import get_db; next(get_db())" 2>/dev/null; then
        echo "[INFO] Marzban database ready"
        break
    fi
    echo "[INFO] Waiting for database... ($i/30)"
    sleep 2
done

# Check if admin exists
if docker compose exec -T marzban marzban-cli admin list | grep -q "$ADMIN_USERNAME"; then
    echo "[INFO] Admin exists. Updating password..."
    docker compose exec -T marzban bash -c "echo 'y\n' | marzban-cli admin update --username '$ADMIN_USERNAME' --password '$ADMIN_PASSWORD'"
else
    echo "[INFO] Creating admin user: $ADMIN_USERNAME"
    docker compose exec -T marzban bash -c "echo 'y\n\n' | marzban-cli admin create --username '$ADMIN_USERNAME' --password '$ADMIN_PASSWORD'"
fi

# Verify admin was created
echo "[INFO] Verifying admin creation..."
if docker compose exec -T marzban marzban-cli admin list | grep -q "$ADMIN_USERNAME"; then
    echo "[SUCCESS] Marzban admin '$ADMIN_USERNAME' present and password set"
else
    echo "[ERROR] Failed to create/update admin '$ADMIN_USERNAME'"
    docker compose exec -T marzban marzban-cli admin list
    exit 1
fi
