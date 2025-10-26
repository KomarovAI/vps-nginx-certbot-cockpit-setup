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
for i in {1..90}; do
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/dashboard/ 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "304" || "$HTTP_CODE" == "302" ]]; then
        echo "[INFO] Marzban dashboard ready (HTTP $HTTP_CODE)"
        break
    fi
    echo "[INFO] Waiting for dashboard... ($i/90) HTTP: $HTTP_CODE"
    sleep 2
done

# Additional wait for database initialization
echo "[INFO] Additional wait for database..."
sleep 5

# Check if admin exists using full admin list output
echo "[INFO] Checking existing admins..."
ADMIN_LIST_OUTPUT=$(docker compose exec -T marzban marzban-cli admin list 2>/dev/null || echo "")
echo "[DEBUG] Admin list output:"
echo "$ADMIN_LIST_OUTPUT"

ADMIN_EXISTS=false
if echo "$ADMIN_LIST_OUTPUT" | grep -q "$ADMIN_USERNAME"; then
    ADMIN_EXISTS=true
    echo "[INFO] Admin '$ADMIN_USERNAME' exists. Will update password..."
else
    echo "[INFO] Admin '$ADMIN_USERNAME' not found. Will create..."
fi

# Setup admin with multiple fallback methods
echo "[INFO] Setting up admin (method 1: structured input)..."
if [ "$ADMIN_EXISTS" = true ]; then
    # Try update with structured input
    {
        printf "y\n"
        sleep 1
        printf "\n"
        sleep 1
        printf "\n"
    } | timeout 30 docker compose exec -T marzban env FORCE_COLOR=0 LC_ALL=C marzban-cli admin update --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" 2>/dev/null || {
        echo "[WARN] Method 1 failed, trying method 2 (echo)..."
        echo -e "y\n\n\n" | timeout 30 docker compose exec -T marzban marzban-cli admin update --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" 2>/dev/null || {
            echo "[WARN] Method 2 failed, trying method 3 (yes utility)..."
            yes | head -3 | timeout 15 docker compose exec -T marzban marzban-cli admin update --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" 2>/dev/null || true
        }
    }
else
    # Try create with structured input
    {
        printf "y\n"
        sleep 1
        printf "\n"
        sleep 1
        printf "\n"
    } | timeout 30 docker compose exec -T marzban env FORCE_COLOR=0 LC_ALL=C marzban-cli admin create --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" 2>/dev/null || {
        echo "[WARN] Method 1 failed, trying method 2 (echo)..."
        echo -e "y\n\n\n" | timeout 30 docker compose exec -T marzban marzban-cli admin create --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" 2>/dev/null || {
            echo "[WARN] Method 2 failed, trying method 3 (yes utility)..."
            yes | head -3 | timeout 15 docker compose exec -T marzban marzban-cli admin create --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" 2>/dev/null || true
        }
    }
fi

# Wait for changes to persist
echo "[INFO] Waiting for changes to persist..."
sleep 5

# Final verification
echo "[INFO] Final verification..."
FINAL_ADMIN_LIST=$(docker compose exec -T marzban marzban-cli admin list 2>/dev/null || echo "ERROR: Could not get admin list")
echo "[DEBUG] Final admin list:"
echo "$FINAL_ADMIN_LIST"

if echo "$FINAL_ADMIN_LIST" | grep -q "$ADMIN_USERNAME"; then
    echo "[SUCCESS] Marzban admin '$ADMIN_USERNAME' is confirmed present"
else
    echo "[ERROR] Admin '$ADMIN_USERNAME' still not found after all attempts"
    echo "[DEBUG] Marzban container logs (last 100 lines):"
    docker logs marzban --tail 100 2>/dev/null || echo "Could not get container logs"
    exit 1
fi