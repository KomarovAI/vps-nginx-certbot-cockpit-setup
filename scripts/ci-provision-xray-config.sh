#!/bin/bash
# CI script to provision Xray VLESS REALITY config from repository template
set -euo pipefail

echo "[INFO] Provisioning Xray VLESS REALITY config from template..."

# Required variables - fail if not set
XRAY_REALITY_PRIVATE_KEY="${XRAY_REALITY_PRIVATE_KEY:-}"
XRAY_REALITY_SHORT_IDS="${XRAY_REALITY_SHORT_IDS:-}"
XRAY_REALITY_SERVER_NAMES="${XRAY_REALITY_SERVER_NAMES:-}"
XRAY_PORT="${XRAY_PORT:-2083}"

if [[ -z "$XRAY_REALITY_PRIVATE_KEY" ]]; then
    echo "[ERROR] XRAY_REALITY_PRIVATE_KEY is not set"
    exit 1
fi

if [[ -z "$XRAY_REALITY_SHORT_IDS" ]]; then
    echo "[ERROR] XRAY_REALITY_SHORT_IDS is not set"
    exit 1
fi

if [[ -z "$XRAY_REALITY_SERVER_NAMES" ]]; then
    echo "[ERROR] XRAY_REALITY_SERVER_NAMES is not set"
    exit 1
fi

# Convert comma-separated values to proper JSON arrays (without extra brackets)
SHORT_IDS_JSON=$(echo "$XRAY_REALITY_SHORT_IDS" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
SERVER_NAMES_JSON=$(echo "$XRAY_REALITY_SERVER_NAMES" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')

echo "[INFO] Rendering Xray config template..."
echo "[INFO] - Private Key: ${XRAY_REALITY_PRIVATE_KEY:0:8}..."
echo "[INFO] - Short IDs JSON: [$SHORT_IDS_JSON]"
echo "[INFO] - Server Names JSON: [$SERVER_NAMES_JSON]"
echo "[INFO] - Port: $XRAY_PORT"

# Create target directory
sudo mkdir -p /var/lib/marzban

# Render template to final config
sudo cp /tmp/xray_config.json.tpl /var/lib/marzban/xray_config.json
sudo sed -i "s/{{XRAY_REALITY_PRIVATE_KEY}}/$XRAY_REALITY_PRIVATE_KEY/g" /var/lib/marzban/xray_config.json
sudo sed -i "s/{{XRAY_REALITY_SHORT_IDS_JSON}}/$SHORT_IDS_JSON/g" /var/lib/marzban/xray_config.json
sudo sed -i "s/{{XRAY_REALITY_SERVER_NAMES_JSON}}/$SERVER_NAMES_JSON/g" /var/lib/marzban/xray_config.json
sudo sed -i "s/{{XRAY_PORT}}/$XRAY_PORT/g" /var/lib/marzban/xray_config.json

# Set proper permissions
sudo chmod 600 /var/lib/marzban/xray_config.json
sudo chown 2000:2000 /var/lib/marzban/xray_config.json

echo "[INFO] Xray config provisioned at /var/lib/marzban/xray_config.json"

# Validate JSON syntax
echo "[INFO] Validating JSON syntax..."
if ! sudo python3 -m json.tool /var/lib/marzban/xray_config.json >/dev/null 2>&1; then
    echo "[ERROR] Generated Xray config has invalid JSON syntax:"
    sudo cat /var/lib/marzban/xray_config.json
    exit 1
fi

echo "[SUCCESS] Xray VLESS REALITY config provisioned and validated"
echo "[INFO] Config preview:"
sudo head -20 /var/lib/marzban/xray_config.json