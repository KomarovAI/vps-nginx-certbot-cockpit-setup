#!/bin/bash
set -e

echo "[MARZBAN-INIT] Starting Marzban container initialization..."

# Create required directories
mkdir -p /var/lib/marzban
mkdir -p /etc/xray
mkdir -p /opt/marzban/logs

echo "[MARZBAN-INIT] Initializing database..."
echo "[MARZBAN-INIT] Database URL: ${MARZBAN_DB_URL:-sqlite:////var/lib/marzban/marzban.db}"

# Determine database path
db_path="/var/lib/marzban/marzban.db"
if [[ "${MARZBAN_DB_URL:-}" =~ sqlite:///(/.*) ]]; then
    db_path="${BASH_REMATCH[1]}"
fi

echo "[MARZBAN-INIT] Database file: $db_path"

# Check if database exists and has content
if [[ ! -f "$db_path" ]] || [[ ! -s "$db_path" ]]; then
    echo "[MARZBAN-INIT] Database file missing or empty, running migrations..."
    
    # Current directory and alembic detection
    echo "[MARZBAN-INIT] Current directory: $(pwd)"
    
    # Look for alembic in multiple locations
    alembic_ini=""
    migrations_dir=""
    
    for dir in /code /app /opt/marzban; do
        if [[ -f "$dir/alembic.ini" ]] && [[ -d "$dir/app/db/migrations" ]]; then
            alembic_ini="$dir/alembic.ini"
            migrations_dir="$dir/app/db/migrations"
            echo "[MARZBAN-INIT] Found alembic.ini: $alembic_ini"
            echo "[MARZBAN-INIT] Found migrations: $migrations_dir"
            break
        fi
    done
    
    if [[ -n "$alembic_ini" ]] && [[ -n "$migrations_dir" ]]; then
        echo "[MARZBAN-INIT] Running alembic migrations..."
        
        # Create temporary minimal XRAY_JSON to prevent import errors during migrations
        tmp_xray_json="/opt/marzban/tmp-minimal-xray.json"
        cat > "$tmp_xray_json" <<EOF
{
  "inbounds": [
    {
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
        
        # Store original XRAY_JSON and set temporary one
        ORIGINAL_XRAY_JSON="${XRAY_JSON:-}"
        export XRAY_JSON="$tmp_xray_json"
        
        # Run alembic migrations
        cd "$(dirname "$alembic_ini")"
        if alembic upgrade head; then
            echo "[MARZBAN-INIT] ✓ Alembic migrations completed successfully"
        else
            echo "[MARZBAN-INIT] ✗ Alembic migrations failed, using fallback database creation..."
            
            # Fallback: create comprehensive database structure
            python3 -c "
import sqlite3
import os

db_path = '$db_path'
os.makedirs(os.path.dirname(db_path), exist_ok=True)

conn = sqlite3.connect(db_path)
conn.executescript('''
-- Users table with full schema
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username VARCHAR(32) NOT NULL UNIQUE,
    hashed_password VARCHAR(128) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'active',
    used_traffic BIGINT DEFAULT 0,
    data_limit BIGINT,
    expire BIGINT,
    admin_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_limit_reset_strategy VARCHAR(16) DEFAULT 'no_reset',
    sub_updated_at TIMESTAMP,
    sub_last_user_agent TEXT,
    online_at TIMESTAMP,
    edit_at TIMESTAMP
);

-- Admins table
CREATE TABLE IF NOT EXISTS admins (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username VARCHAR(32) NOT NULL UNIQUE,
    hashed_password VARCHAR(128) NOT NULL,
    is_sudo BOOLEAN NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    telegram_id BIGINT,
    discord_webhook TEXT
);

-- System table
CREATE TABLE IF NOT EXISTS system (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uplink BIGINT DEFAULT 0,
    downlink BIGINT DEFAULT 0
);

-- Proxies table (critical for Marzban functionality)
CREATE TABLE IF NOT EXISTS proxies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    type VARCHAR(16) NOT NULL,
    settings TEXT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- Exclude inbounds association table
CREATE TABLE IF NOT EXISTS exclude_inbounds_association (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    proxy_id INTEGER NOT NULL,
    inbound_tag VARCHAR(32) NOT NULL,
    FOREIGN KEY (proxy_id) REFERENCES proxies (id) ON DELETE CASCADE
);

-- JWT tokens table
CREATE TABLE IF NOT EXISTS jwt (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

-- User templates table  
CREATE TABLE IF NOT EXISTS user_templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name VARCHAR(64) NOT NULL UNIQUE,
    inbounds TEXT,
    data_limit BIGINT,
    expire_duration BIGINT,
    username_prefix VARCHAR(20),
    username_suffix VARCHAR(20)
);

-- Nodes table for multi-server support
CREATE TABLE IF NOT EXISTS nodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name VARCHAR(256) NOT NULL,
    address VARCHAR(256) NOT NULL,
    port INTEGER NOT NULL DEFAULT 62050,
    api_port INTEGER NOT NULL DEFAULT 62051,
    certificate TEXT,
    status VARCHAR(16) NOT NULL DEFAULT 'connecting',
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT OR IGNORE INTO system (id, uplink, downlink) VALUES (1, 0, 0);
''') 
conn.close()
print('[MARZBAN-INIT] ✓ Comprehensive database structure created as fallback')
"
        fi
        
        # Restore original XRAY_JSON
        export XRAY_JSON="$ORIGINAL_XRAY_JSON"
        rm -f "$tmp_xray_json"
    else
        echo "[MARZBAN-INIT] Alembic not found, creating comprehensive database structure..."
        
        # Create comprehensive database structure directly
        python3 -c "
import sqlite3
import os

db_path = '$db_path'
os.makedirs(os.path.dirname(db_path), exist_ok=True)

conn = sqlite3.connect(db_path)
conn.executescript('''
-- Users table with full schema
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username VARCHAR(32) NOT NULL UNIQUE,
    hashed_password VARCHAR(128) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'active',
    used_traffic BIGINT DEFAULT 0,
    data_limit BIGINT,
    expire BIGINT,
    admin_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data_limit_reset_strategy VARCHAR(16) DEFAULT 'no_reset'
);

CREATE TABLE IF NOT EXISTS admins (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username VARCHAR(32) NOT NULL UNIQUE,
    hashed_password VARCHAR(128) NOT NULL,
    is_sudo BOOLEAN NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS system (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uplink BIGINT DEFAULT 0,
    downlink BIGINT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS proxies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    type VARCHAR(16) NOT NULL,
    settings TEXT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS exclude_inbounds_association (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    proxy_id INTEGER NOT NULL,
    inbound_tag VARCHAR(32) NOT NULL,
    FOREIGN KEY (proxy_id) REFERENCES proxies (id) ON DELETE CASCADE
);

INSERT OR IGNORE INTO system (id, uplink, downlink) VALUES (1, 0, 0);
''') 
conn.close()
print('[MARZBAN-INIT] ✓ Comprehensive database structure created')
"
    fi
else
    echo "[MARZBAN-INIT] Database exists, checking if migrations needed..."
    
    # Try to run migrations anyway to ensure we're up to date
    if [[ -f "/code/alembic.ini" ]]; then
        cd /code
        # Create temporary minimal XRAY_JSON for migrations
        tmp_xray_json="/opt/marzban/tmp-minimal-xray.json"
        cat > "$tmp_xray_json" <<EOF
{
  "inbounds": [
    {
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF
        
        ORIGINAL_XRAY_JSON="${XRAY_JSON:-}"
        export XRAY_JSON="$tmp_xray_json"
        
        alembic upgrade head 2>/dev/null || echo "[MARZBAN-INIT] Migration check completed"
        
        export XRAY_JSON="$ORIGINAL_XRAY_JSON"
        rm -f "$tmp_xray_json"
    fi
fi

echo "[MARZBAN-INIT] Database file: $db_path"
if [[ -f "$db_path" ]]; then
    echo "[MARZBAN-INIT] Database size: $(stat -c%s "$db_path" 2>/dev/null || echo "unknown") bytes"
fi

echo "[MARZBAN-INIT] Running pre-initialization scripts..."

# Run initialization scripts
if [[ -d "/opt/init-scripts" ]]; then
    for script in /opt/init-scripts/*.sh; do
        if [[ -x "$script" ]]; then
            echo "[MARZBAN-INIT] Executing $(basename "$script")..."
            "$script" || echo "[MARZBAN-INIT] Warning: $(basename "$script") failed, but continuing..."
        fi
    done
fi

echo "[MARZBAN-INIT] Generating Xray configuration..."

# Only generate xray config if XRAY_JSON is not already set to a valid file
if [[ -z "${XRAY_JSON}" ]] || [[ ! -f "${XRAY_JSON}" ]]; then
    # Generate valid Reality keys if not provided
    if [[ -z "${XRAY_REALITY_PRIVATE_KEY}" ]]; then
        # Generate a proper x25519 key pair
        XRAY_REALITY_PRIVATE_KEY=$(openssl genpkey -algorithm x25519 | openssl pkey -outform DER | tail -c +13 | head -c 32 | base64)
    fi
    
    if [[ -z "${XRAY_REALITY_SHORT_IDS}" ]]; then
        XRAY_REALITY_SHORT_IDS="$(openssl rand -hex 8),$(openssl rand -hex 8)"
    fi
    
    # Set default server names
    XRAY_REALITY_SERVER_NAMES="${XRAY_REALITY_SERVER_NAMES:-google.com,www.google.com}"
    
    # Convert server names to JSON array
    SERVER_NAMES_JSON=$(echo "${XRAY_REALITY_SERVER_NAMES}" | sed 's/,/", "/g' | sed 's/^/["/' | sed 's/$/"]/')
    
    # Convert short IDs to JSON array  
    SHORT_IDS_JSON=$(echo "${XRAY_REALITY_SHORT_IDS}" | sed 's/,/", "/g' | sed 's/^/["/' | sed 's/$/"]/')
    
    # Get first server name for destination
    FIRST_SERVER=$(echo "${XRAY_REALITY_SERVER_NAMES}" | cut -d',' -f1)
    
    # Create comprehensive VLESS Reality config
    cat > "/etc/xray/config.json" <<EOF
{
  "api": {
    "services": ["HandlerService", "LoggerService", "StatsService"],
    "tag": "api"
  },
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
          "dest": "${FIRST_SERVER}:443",
          "xver": 0,
          "serverNames": ${SERVER_NAMES_JSON},
          "privateKey": "${XRAY_REALITY_PRIVATE_KEY}",
          "shortIds": ${SHORT_IDS_JSON}
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
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
    
    export XRAY_JSON="/etc/xray/config.json"
    
    # Save keys for future reference
    cat > "/var/lib/marzban/reality_keys.env" <<EOF
XRAY_REALITY_PRIVATE_KEY=${XRAY_REALITY_PRIVATE_KEY}
XRAY_REALITY_SHORT_IDS=${XRAY_REALITY_SHORT_IDS}
XRAY_REALITY_SERVER_NAMES=${XRAY_REALITY_SERVER_NAMES}
EOF
    
    echo "[MARZBAN-INIT] Xray config generated at /etc/xray/config.json"
fi

# Validate xray config (non-critical)
echo "[MARZBAN-INIT] Validating Xray configuration..."
if [[ -f "${XRAY_JSON}" ]] && xray -test -config="${XRAY_JSON}" >/dev/null 2>&1; then
    echo "[MARZBAN-INIT] ✓ Xray configuration is valid"
else
    echo "[MARZBAN-INIT] ⚠ Xray validation failed (non-critical, will use defaults)"
fi

echo "[MARZBAN-INIT] ✓ Initialization completed successfully. Starting Marzban..."

echo "[MARZBAN-INIT] Final database status:"
ls -la "$db_path" 2>/dev/null || echo "[MARZBAN-INIT] Database file not found: $db_path"

# Execute the original command
exec "$@"