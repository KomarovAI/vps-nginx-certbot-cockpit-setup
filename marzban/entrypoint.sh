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

# Initialize database BEFORE running any scripts or starting the application
echo "[MARZBAN-INIT] Initializing database..."
export MARZBAN_DB_URL="${MARZBAN_DB_URL:-sqlite:////var/lib/marzban/marzban.db}"

# Extract database file path from URL
DB_FILE=$(echo "$MARZBAN_DB_URL" | sed 's|sqlite:///||')

echo "[MARZBAN-INIT] Database URL: $MARZBAN_DB_URL"
echo "[MARZBAN-INIT] Database file: $DB_FILE"

if [ ! -f "$DB_FILE" ] || [ ! -s "$DB_FILE" ]; then
    echo "[MARZBAN-INIT] Database file missing or empty, initializing..."
    
    # Ensure database directory exists
    mkdir -p "$(dirname "$DB_FILE")"
    
    # Check if we're in the right directory and alembic exists
    echo "[MARZBAN-INIT] Current directory: $(pwd)"
    echo "[MARZBAN-INIT] Looking for alembic and migrations..."
    find /app /code /opt -name "alembic.ini" -o -name "migrations" -type d 2>/dev/null | head -5 || true
    ls -la . 2>/dev/null || true
    
    # Try different possible locations for alembic
    ALEMBIC_SUCCESS=false
    for workdir in /app /code /opt/marzban .; do
        if [ -f "$workdir/alembic.ini" ] && [ -d "$workdir/migrations" ]; then
            echo "[MARZBAN-INIT] Found alembic config in $workdir"
            cd "$workdir"
            if alembic upgrade head 2>/dev/null; then
                echo "[MARZBAN-INIT] ✓ Alembic migration successful"
                ALEMBIC_SUCCESS=true
                break
            else
                echo "[MARZBAN-INIT] ✗ Alembic migration failed in $workdir"
            fi
        fi
    done
    
    if [ "$ALEMBIC_SUCCESS" = "false" ]; then
        echo "[MARZBAN-INIT] Alembic not available or failed, using safe SQLite init..."
        # Create minimal SQLite database structure WITHOUT importing the app
        python3 -c "
import os
import sqlite3
import pathlib

# Get DB path
db_url = os.environ.get('MARZBAN_DB_URL', 'sqlite:////var/lib/marzban/marzban.db')
db_path = db_url.replace('sqlite:///', '')

# Ensure directory exists
pathlib.Path(db_path).parent.mkdir(parents=True, exist_ok=True)

# Create basic database file
conn = sqlite3.connect(db_path)

# Create essential tables (minimal schema to prevent 'no such table' error)
# These are the basic tables that Marzban expects
conn.executescript('''
-- Users table (essential)
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username VARCHAR(32) UNIQUE NOT NULL,
    email VARCHAR(255),
    hashed_password VARCHAR(128) NOT NULL,
    is_active BOOLEAN DEFAULT 1,
    is_superuser BOOLEAN DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Admins table
CREATE TABLE IF NOT EXISTS admins (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username VARCHAR(32) UNIQUE NOT NULL,
    hashed_password VARCHAR(128) NOT NULL,
    is_sudo BOOLEAN DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- System table for versioning
CREATE TABLE IF NOT EXISTS system (
    id INTEGER PRIMARY KEY,
    version VARCHAR(32)
);

-- Insert initial version
INSERT OR IGNORE INTO system (id, version) VALUES (1, '0.1.0');
''') 

conn.commit()
conn.close()

print('[MARZBAN-INIT] ✓ Basic database structure created')
print(f'[MARZBAN-INIT] Database file: {db_path}')
print(f'[MARZBAN-INIT] Database size: {os.path.getsize(db_path)} bytes')
" || {
            echo "[MARZBAN-INIT] ✗ ERROR: Database initialization failed"
            exit 1
        }
    fi
else
    echo "[MARZBAN-INIT] Database exists, checking if migrations needed..."
    # For existing databases, try to run migrations if available
    for workdir in /app /code /opt/marzban .; do
        if [ -f "$workdir/alembic.ini" ] && [ -d "$workdir/migrations" ]; then
            echo "[MARZBAN-INIT] Running migrations from $workdir"
            cd "$workdir"
            alembic upgrade head 2>/dev/null || echo "[MARZBAN-INIT] Migration skipped (non-critical)"
            break
        fi
    done
fi

# Run pre-initialization scripts AFTER database is ready
echo "[MARZBAN-INIT] Running pre-initialization scripts..."
for script in /opt/init-scripts/*.sh; do
    if [ -f "$script" ]; then
        echo "[MARZBAN-INIT] Executing $(basename $script)..."
        bash "$script"
    fi
done

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
    if xray -test -config="$XRAY_JSON" 2>/dev/null; then
        echo "[MARZBAN-INIT] ✓ Xray configuration is valid"
    else
        echo "[MARZBAN-INIT] ⚠ Xray validation failed (non-critical)"
        # Don't exit here, let the app start anyway
    fi
fi

# Set environment defaults
export MARZBAN_HOST=${MARZBAN_HOST:-localhost}
export MARZBAN_PANEL_PORT=${MARZBAN_PANEL_PORT:-8000}
export XRAY_PORT=${XRAY_PORT:-2083}

echo "[MARZBAN-INIT] ✓ Initialization completed successfully. Starting Marzban..."
echo "[MARZBAN-INIT] Final database status:"
ls -la "$DB_FILE" 2>/dev/null || echo "Database file not found at $DB_FILE"

# Execute the main command
exec "$@"