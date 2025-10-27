#!/bin/bash
set -e

echo "[MARZBAN-INIT] Starting Marzban container initialization..."

# Unified XRAY config path for consistency
XRAY_CONFIG_PATH="/var/lib/marzban/xray_config.json"

# Create required directories
echo "[MARZBAN-INIT] Creating required directories..."
mkdir -p /var/lib/marzban
mkdir -p /etc/xray
mkdir -p /opt/marzban/logs

# Set proper permissions
echo "[MARZBAN-INIT] Setting permissions..."
if id marzban >/dev/null 2>&1; then
    chown -R marzban:marzban /var/lib/marzban
    chown -R marzban:marzban /etc/xray
else
    echo "[MARZBAN-INIT] WARNING: marzban user not found, using root permissions"
fi

# Run pre-initialization scripts in order
echo "[MARZBAN-INIT] Running pre-initialization scripts..."
for script in /opt/init-scripts/*.sh; do
    if [ -f "$script" ]; then
        echo "[MARZBAN-INIT] Executing $(basename $script)..."
        if bash "$script"; then
            echo "[MARZBAN-INIT] ✅ $(basename $script) completed successfully"
        else
            echo "[MARZBAN-INIT] ⚠️  $(basename $script) completed with warnings"
        fi
    fi
done

# Generate or use existing Xray config
if [ -f "$XRAY_CONFIG_PATH" ]; then
    echo "[MARZBAN-INIT] Using existing Xray config at $XRAY_CONFIG_PATH"
    export XRAY_JSON="$XRAY_CONFIG_PATH"
elif [ -f "/opt/templates/xray_config.json.tpl" ]; then
    echo "[MARZBAN-INIT] Generating Xray configuration from template..."
    if envsubst < /opt/templates/xray_config.json.tpl > "$XRAY_CONFIG_PATH"; then
        export XRAY_JSON="$XRAY_CONFIG_PATH"
        echo "[MARZBAN-INIT] ✅ Xray config generated at $XRAY_JSON"
    else
        echo "[MARZBAN-INIT] ❌ Failed to generate Xray config from template"
    fi
else
    echo "[MARZBAN-INIT] No Xray config template found, using default Marzban configuration"
fi

# Validate Xray configuration if available
if [ -n "$XRAY_JSON" ] && [ -f "$XRAY_JSON" ]; then
    echo "[MARZBAN-INIT] Validating Xray configuration..."
    if command -v xray >/dev/null 2>&1; then
        if xray -test -config="$XRAY_JSON" >/dev/null 2>&1; then
            echo "[MARZBAN-INIT] ✅ Xray configuration is valid"
        else
            echo "[MARZBAN-INIT] ⚠️  Xray configuration validation failed, but continuing..."
        fi
    else
        echo "[MARZBAN-INIT] ⚠️  Xray binary not found, skipping validation"
    fi
fi

# Set environment defaults
echo "[MARZBAN-INIT] Setting environment defaults..."
export MARZBAN_HOST=${MARZBAN_HOST:-localhost}
export MARZBAN_PANEL_PORT=${MARZBAN_PANEL_PORT:-8000}
export XRAY_PORT=${XRAY_PORT:-2083}
export MARZBAN_DB_URL=${MARZBAN_DB_URL:-sqlite:////var/lib/marzban/marzban.db}

# Show final configuration summary
echo "[MARZBAN-INIT] 📋 Configuration summary:"
echo "  Host: $MARZBAN_HOST"
echo "  Panel Port: $MARZBAN_PANEL_PORT"
echo "  Xray Port: $XRAY_PORT"
echo "  Database: $MARZBAN_DB_URL"
echo "  Xray Config: ${XRAY_JSON:-'Default (built-in)'}"

# Check if Reality keys are configured
if [ -n "$XRAY_REALITY_PRIVATE_KEY" ] && [ -n "$XRAY_REALITY_PUBLIC_KEY" ]; then
    echo "  Reality Keys: ✅ Configured"
else
    echo "  Reality Keys: ⚠️  Will be auto-generated"
fi

echo "[MARZBAN-INIT] 🚀 Initialization completed. Starting Marzban..."
echo "[MARZBAN-INIT] " 
echo "[MARZBAN-INIT] Access panel at: https://${MARZBAN_HOST}:${MARZBAN_PANEL_PORT}"
echo "[MARZBAN-INIT] "

# Execute the main command
exec "$@"