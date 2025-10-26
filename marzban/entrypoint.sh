#!/bin/bash
set -e

echo "[MARZBAN-INIT] Starting Marzban container initialization..."

# Create required directories
mkdir -p /var/lib/marzban
mkdir -p /etc/xray
mkdir -p /opt/marzban/logs

# Set proper permissions (use root to avoid missing user issues)
chown -R root:root /var/lib/marzban
chown -R root:root /etc/xray

# Run pre-initialization scripts
echo "[MARZBAN-INIT] Running pre-initialization scripts..."
for script in /opt/init-scripts/*.sh; do
    if [ -f "$script" ]; then
        echo "[MARZBAN-INIT] Executing $(basename $script)..."
        bash "$script"
    fi
done

# Initialize database BEFORE starting the application
echo "[MARZBAN-INIT] Initializing database..."
export MARZBAN_DB_URL="${MARZBAN_DB_URL:-sqlite:////var/lib/marzban/marzban.db}"

# Extract database file path from URL
DB_FILE=$(echo "$MARZBAN_DB_URL" | sed 's|sqlite:///||')

if [ ! -f "$DB_FILE" ] || [ ! -s "$DB_FILE" ]; then
    echo "[MARZBAN-INIT] Database file missing or empty, initializing..."
    # Try Alembic first
    if command -v alembic >/dev/null 2>&1; then
        echo "[MARZBAN-INIT] Running alembic upgrade head..."
        cd /code && alembic upgrade head 2>/dev/null || {
            echo "[MARZBAN-INIT] Alembic failed, trying Python init..."
            python3 -c "
try:
    from app.database import Base, engine
    Base.metadata.create_all(bind=engine)
    print('[MARZBAN-INIT] Database tables created successfully')
except Exception as e:
    print(f'[MARZBAN-INIT] Database init failed: {e}')
    exit(1)
" || {
                echo "[MARZBAN-INIT] ERROR: Database initialization failed"
                exit 1
            }
        }
    else
        echo "[MARZBAN-INIT] Alembic not available, using Python init..."
        python3 -c "
try:
    from app.database import Base, engine
    Base.metadata.create_all(bind=engine)
    print('[MARZBAN-INIT] Database tables created successfully')
except Exception as e:
    print(f'[MARZBAN-INIT] Database init failed: {e}')
    exit(1)
"
    fi
else
    echo "[MARZBAN-INIT] Database exists, running migrations..."
    cd /code && alembic upgrade head 2>/dev/null || echo "[MARZBAN-INIT] Migration skipped or failed (non-critical)"
fi

# Generate Xray config directly (NO envsubst - avoid bash substitution issues)
if [ -z "$XRAY_JSON" ]; then
    echo "[MARZBAN-INIT] Generating Xray configuration..."
    
    # Prepare variables with defaults
    XRAY_PORT_SAFE="${XRAY_PORT:-2083}"
    XRAY_PRIVATE_KEY="${XRAY_REALITY_PRIVATE_KEY:-$(openssl rand -base64 32)}"
    
    # Prepare server names JSON array
    if [ -n "$XRAY_REALITY_SERVER_NAMES" ]; then
        FIRST_HOST=$(echo "$XRAY_REALITY_SERVER_NAMES" | cut -d',' -f1)
        XRAY_SERVER_NAMES_JSON=$(echo "$XRAY_REALITY_SERVER_NAMES" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
    else
        FIRST_HOST="google.com"
        XRAY_SERVER_NAMES_JSON='"google.com","www.google.com"'
    fi
    
    # Prepare short IDs JSON array
    if [ -n "$XRAY_REALITY_SHORT_IDS" ]; then
        XRAY_SHORT_IDS_JSON=$(echo "$XRAY_REALITY_SHORT_IDS" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')
    else
        XRAY_SHORT_IDS_JSON='"abcdef0123456789","fedcba9876543210"'
    fi
    
    # Create Xray config directly (no envsubst)
    cat > /etc/xray/config.json <<XRAYEOF
{
  "api": {
    "services": ["HandlerService", "LoggerService", "StatsService"],
    "tag": "api"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $XRAY_PORT_SAFE,
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
          "dest": "$FIRST_HOST:443",
          "xver": 0,
          "serverNames": [$XRAY_SERVER_NAMES_JSON],
          "privateKey": "$XRAY_PRIVATE_KEY",
          "shortIds": [$XRAY_SHORT_IDS_JSON]
        },
        "grpcSettings": {
          "serviceName": "grpc"
        }
      },
      "tag": "vless-reality"
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ]
}
XRAYEOF
    
    export XRAY_JSON="/etc/xray/config.json"
    echo "[MARZBAN-INIT] Xray config generated at $XRAY_JSON"
fi

# Validate Xray configuration
if [ -n "$XRAY_JSON" ] && [ -f "$XRAY_JSON" ]; then
    echo "[MARZBAN-INIT] Validating Xray configuration..."
    if xray -test -config="$XRAY_JSON"; then
        echo "[MARZBAN-INIT] Xray configuration is valid"
    else
        echo "[MARZBAN-INIT] ERROR: Xray configuration validation failed"
        echo "[MARZBAN-INIT] Generated config:"
        cat "$XRAY_JSON"
        exit 1
    fi
fi

# Set environment defaults
export MARZBAN_HOST=${MARZBAN_HOST:-localhost}
export MARZBAN_PANEL_PORT=${MARZBAN_PANEL_PORT:-8000}
export XRAY_PORT=${XRAY_PORT:-2083}

echo "[MARZBAN-INIT] Initialization completed. Starting Marzban..."

# Execute the main command
exec "$@"