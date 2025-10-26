#!/bin/bash

# Dependencies check script
echo "[DEPS-CHECK] Checking Marzban dependencies..."

# Check if xray is available
if ! command -v xray &> /dev/null; then
    echo "[DEPS-CHECK] ERROR: xray command not found"
    exit 1
fi

# Check xray version
XRAY_VERSION=$(xray version 2>/dev/null | head -1 || echo "unknown")
echo "[DEPS-CHECK] Xray version: $XRAY_VERSION"

# Check required tools
for tool in curl jq envsubst; do
    if ! command -v $tool &> /dev/null; then
        echo "[DEPS-CHECK] ERROR: $tool not found"
        exit 1
    else
        echo "[DEPS-CHECK] ✓ $tool is available"
    fi
done

# Check environment variables
echo "[DEPS-CHECK] Checking environment configuration..."

# Required variables
REQUIRED_VARS=("DOMAIN_NAME")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "[DEPS-CHECK] WARNING: $var is not set"
    else
        echo "[DEPS-CHECK] ✓ $var is configured"
    fi
done

# Optional but recommended variables
OPTIONAL_VARS=("XRAY_REALITY_PRIVATE_KEY" "XRAY_REALITY_SERVER_NAMES" "XRAY_PORT")
for var in "${OPTIONAL_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "[DEPS-CHECK] INFO: $var not set (will use default/generated)"
    else
        echo "[DEPS-CHECK] ✓ $var is configured"
    fi
done

# Check database directory
if [ ! -d "/var/lib/marzban" ]; then
    echo "[DEPS-CHECK] Creating database directory..."
    mkdir -p /var/lib/marzban
fi

# Check xray config directory
if [ ! -d "/etc/xray" ]; then
    echo "[DEPS-CHECK] Creating Xray config directory..."
    mkdir -p /etc/xray
fi

echo "[DEPS-CHECK] Dependencies check completed"