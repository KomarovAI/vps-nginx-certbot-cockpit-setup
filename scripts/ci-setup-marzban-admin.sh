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

# Wait for Marzban API to be ready
echo "[INFO] Waiting for Marzban API to initialize..."
for i in {1..60}; do
    if curl -sSf http://127.0.0.1:8000/api/health >/dev/null 2>&1; then
        echo "[INFO] Marzban API ready"
        break
    fi
    echo "[INFO] Waiting for API... ($i/60)"
    sleep 2
done

# Kill any existing marzban-cli processes to avoid stdin conflicts
docker compose exec -T marzban pkill -f marzban-cli || true
sleep 1

# Check if admin exists
ADMIN_EXISTS=false
if docker compose exec -T marzban marzban-cli admin list 2>/dev/null | grep -q "$ADMIN_USERNAME"; then
    ADMIN_EXISTS=true
    echo "[INFO] Admin '$ADMIN_USERNAME' exists. Updating password..."
else
    echo "[INFO] Creating new admin: $ADMIN_USERNAME"
fi

# Setup admin with proper input handling
if [ "$ADMIN_EXISTS" = true ]; then
    # Update existing admin
    {
        printf "y\n"
        sleep 1
        printf "\n"
        sleep 1
        printf "\n"
    } | docker compose exec -T marzban env FORCE_COLOR=0 LC_ALL=C marzban-cli admin update --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" || {
        echo "[WARN] Update failed, trying alternative method..."
        echo -e "y\n\n" | docker compose exec -T marzban marzban-cli admin update --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" || true
    }
else
    # Create new admin
    {
        printf "y\n"
        sleep 1
        printf "\n"
        sleep 1
        printf "\n"
    } | docker compose exec -T marzban env FORCE_COLOR=0 LC_ALL=C marzban-cli admin create --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" || {
        echo "[WARN] Create failed, trying alternative method..."
        echo -e "y\n\n" | docker compose exec -T marzban marzban-cli admin create --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" || true
    }
fi

# Wait a moment for changes to persist
sleep 3

# Verify admin was created/updated
echo "[INFO] Verifying admin setup..."
if docker compose exec -T marzban marzban-cli admin list | grep -q "$ADMIN_USERNAME"; then
    echo "[SUCCESS] Marzban admin '$ADMIN_USERNAME' is present"
    echo "[INFO] Current admins:"
    docker compose exec -T marzban marzban-cli admin list
else
    echo "[ERROR] Admin '$ADMIN_USERNAME' not found after setup"
    echo "[DEBUG] Current admins:"
    docker compose exec -T marzban marzban-cli admin list
    echo "[DEBUG] Marzban logs (last 50 lines):"
    docker logs marzban --tail 50
    exit 1
fi