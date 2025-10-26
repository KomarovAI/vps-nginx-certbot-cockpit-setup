#!/bin/bash
set -e

echo "[MARZBAN-INIT] Starting Marzban container initialization..."

# Create required directories
mkdir -p /var/lib/marzban
mkdir -p /etc/xray
mkdir -p /opt/marzban/logs

# Set proper permissions
chown -R marzban:marzban /var/lib/marzban
chown -R marzban:marzban /etc/xray

# Run pre-initialization scripts
echo "[MARZBAN-INIT] Running pre-initialization scripts..."
for script in /opt/init-scripts/*.sh; do
    if [ -f "$script" ]; then
        echo "[MARZBAN-INIT] Executing $(basename $script)..."
        bash "$script"
    fi
done

# Generate Xray config if template exists and XRAY_JSON is not provided
if [ -f "/opt/templates/xray_config.json.tpl" ] && [ -z "$XRAY_JSON" ]; then
    echo "[MARZBAN-INIT] Generating Xray configuration from template..."
    envsubst < /opt/templates/xray_config.json.tpl > /etc/xray/config.json
    export XRAY_JSON="/etc/xray/config.json"
    echo "[MARZBAN-INIT] Xray config generated at $XRAY_JSON"
fi

# Validate Xray configuration
if [ -n "$XRAY_JSON" ] && [ -f "$XRAY_JSON" ]; then
    echo "[MARZBAN-INIT] Validating Xray configuration..."
    if xray -test -config="$XRAY_JSON"; then
        echo "[MARZBAN-INIT] Xray configuration is valid"
    else
        echo "[MARZBAN-INIT] WARNING: Xray configuration validation failed"
    fi
fi

# Set environment defaults
export MARZBAN_HOST=${MARZBAN_HOST:-localhost}
export MARZBAN_PANEL_PORT=${MARZBAN_PANEL_PORT:-8000}
export XRAY_PORT=${XRAY_PORT:-2083}

echo "[MARZBAN-INIT] Initialization completed. Starting Marzban..."

# Execute the main command
exec "$@"