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

# Try to delete existing admin (ignore errors)
echo "[INFO] Removing existing admin if present..."
docker compose exec -T marzban marzban-cli admin delete "$ADMIN_USERNAME" 2>/dev/null || true

# Create new admin with automatic responses
echo "[INFO] Creating admin user: $ADMIN_USERNAME"
docker compose exec -T marzban bash -c "
echo 'y

' | marzban-cli admin create --username '$ADMIN_USERNAME' --password '$ADMIN_PASSWORD'
"

# Verify admin was created
echo "[INFO] Verifying admin creation..."
if docker compose exec -T marzban marzban-cli admin list | grep -q "$ADMIN_USERNAME"; then
    echo "[SUCCESS] Marzban admin '$ADMIN_USERNAME' created successfully"
else
    echo "[ERROR] Failed to create admin '$ADMIN_USERNAME'"
    echo "[DEBUG] Current admins:"
    docker compose exec -T marzban marzban-cli admin list
    exit 1
fi