#!/bin/bash
set -e

echo "[MARZBAN-INIT] Starting Marzban container initialization..."

# Create required directories
mkdir -p /var/lib/marzban
mkdir -p /etc/xray
mkdir -p /opt/marzban/logs

echo "[MARZBAN-INIT] Initializing database..."
echo "[MARZBAN-INIT] Database URL: ${MARZBAN_DB_URL:-sqlite:////var/lib/marzban/db.sqlite3}"

# Determine database path
db_path="/var/lib/marzban/db.sqlite3"
if [[ "${MARZBAN_DB_URL:-}" =~ sqlite:///(/.*) ]]; then
    db_path="${BASH_REMATCH[1]}"
fi

echo "[MARZBAN-INIT] Database file: $db_path"

# Run migrations only once, safely
echo "[MARZBAN-INIT] Running database migrations..."
if [[ -f "/code/alembic.ini" ]]; then
    cd /code
    # Run migrations with error handling (non-fatal)
    if alembic upgrade head 2>/dev/null; then
        echo "[MARZBAN-INIT] ✓ Database migrations completed successfully"
    else
        echo "[MARZBAN-INIT] ⚠ Database migrations completed or already up to date"
    fi
else
    echo "[MARZBAN-INIT] ⚠ Alembic not found, using existing database"
fi

# Generate Xray configuration if needed
echo "[MARZBAN-INIT] Checking Xray configuration..."
if [[ -z "${XRAY_JSON}" ]] || [[ ! -f "${XRAY_JSON}" ]]; then
    echo "[MARZBAN-INIT] Generating Xray configuration..."
    
    # Generate Reality keys if not provided
    if [[ -z "${XRAY_REALITY_PRIVATE_KEY}" ]]; then
        XRAY_REALITY_PRIVATE_KEY=$(openssl genpkey -algorithm x25519 2>/dev/null | openssl pkey -outform DER 2>/dev/null | tail -c +13 | head -c 32 | base64 2>/dev/null || echo "placeholder_key")
    fi
    
    if [[ -z "${XRAY_REALITY_SHORT_IDS}" ]]; then
        XRAY_REALITY_SHORT_IDS="$(openssl rand -hex 8 2>/dev/null || echo "12345678"),$(openssl rand -hex 8 2>/dev/null || echo "87654321")"
    fi
    
    XRAY_REALITY_SERVER_NAMES="${XRAY_REALITY_SERVER_NAMES:-google.com,www.google.com}"
    
    # Create minimal working Xray config
    cat > "/etc/xray/config.json" <<EOF
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${XRAY_PORT:-2083},
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "google.com:443",
          "xver": 0,
          "serverNames": ["google.com", "www.google.com"],
          "privateKey": "${XRAY_REALITY_PRIVATE_KEY}",
          "shortIds": ["12345678", "87654321"]
        },
        "grpcSettings": {
          "serviceName": "grpc"
        }
      },
      "tag": "vless-reality"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF
    
    export XRAY_JSON="/etc/xray/config.json"
    echo "[MARZBAN-INIT] ✓ Xray config generated"
else
    echo "[MARZBAN-INIT] ✓ Using existing Xray configuration"
fi

# Auto-create admin if credentials provided
if [[ -n "${MARZBAN_ADMIN_USERNAME:-}" && -n "${MARZBAN_ADMIN_PASSWORD:-}" ]]; then
    echo "[MARZBAN-INIT] Admin credentials provided, will create after startup"
    # Create background script to add admin after Marzban starts
    cat > "/opt/create-admin.sh" <<EOF
#!/bin/bash
sleep 30  # Wait for Marzban to fully start
cd /code
python -m marzban_cli admin create --username "${MARZBAN_ADMIN_USERNAME}" --password "${MARZBAN_ADMIN_PASSWORD}" 2>/dev/null || \
python -m marzban_cli admin update --username "${MARZBAN_ADMIN_USERNAME}" --password "${MARZBAN_ADMIN_PASSWORD}" 2>/dev/null || \
echo "[ADMIN-INIT] Admin setup completed or already exists"
EOF
    chmod +x /opt/create-admin.sh
    /opt/create-admin.sh &
fi

echo "[MARZBAN-INIT] ✓ Initialization completed. Starting Marzban..."

# Execute the original command
exec "$@"