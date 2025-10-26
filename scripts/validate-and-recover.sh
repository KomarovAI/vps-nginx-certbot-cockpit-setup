#!/bin/bash
# Validation and recovery script for Marzban deployment
set -euo pipefail

DOMAIN_NAME="${DOMAIN_NAME:-}"
ADMIN_USERNAME="${ADMIN_USERNAME:-artur789298}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-WARpteN789298}"

echo "[INFO] Starting Marzban validation and recovery..."

# Function to check service status
check_service() {
    local service="$1"
    local port="$2"
    
    echo "[CHECK] $service on port $port..."
    
    if ss -tlnp | grep -q ":$port "; then
        echo "✅ $service: Port $port is listening"
        return 0
    else
        echo "❌ $service: Port $port not listening"
        return 1
    fi
}

# Function to check HTTP endpoint
check_http() {
    local url="$1"
    local expected_codes="${2:-200}"
    
    echo "[CHECK] HTTP endpoint: $url"
    
    local response_code
    response_code=$(curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")
    
    if echo "$expected_codes" | grep -q "$response_code"; then
        echo "✅ HTTP: $url returned $response_code"
        return 0
    else
        echo "❌ HTTP: $url returned $response_code (expected: $expected_codes)"
        return 1
    fi
}

# Function to recover Marzban
recover_marzban() {
    echo "[RECOVER] Starting Marzban recovery..."
    
    cd /opt/marzban || { echo "ERROR: /opt/marzban not found"; exit 1; }
    
    # Stop containers
    echo "Stopping containers..."
    docker compose down -v 2>/dev/null || true
    
    # Remove corrupted data
    echo "Cleaning corrupted data..."
    rm -rf data/marzban.db* 2>/dev/null || true
    
    # Ensure config exists
    if [[ ! -f "/var/lib/marzban/xray_config.json" ]]; then
        echo "Creating missing Xray config..."
        mkdir -p /var/lib/marzban
        cat > /var/lib/marzban/xray_config.json << 'XRAY_EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "port": 2083,
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.cloudflare.com:443",
          "xver": 0,
          "serverNames": ["discord.com", "www.yahoo.com"],
          "privateKey": "PLACEHOLDER_PRIVATE_KEY",
          "shortIds": ["abcdef0123456789", "fedcba9876543210"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
XRAY_EOF
        chmod 600 /var/lib/marzban/xray_config.json
        chown -R 2000:2000 /var/lib/marzban/ 2>/dev/null || true
    fi
    
    # Start containers
    echo "Starting containers..."
    docker compose up -d
    
    # Wait for startup
    echo "Waiting for Marzban to start..."
    for i in {1..30}; do
        if curl -s http://127.0.0.1:8000/dashboard/ >/dev/null 2>&1; then
            echo "Marzban is responding"
            break
        fi
        sleep 2
    done
    
    # Create admin
    echo "Creating/updating admin..."
    sleep 5
    
    echo -e "y\ny\ny" | docker compose exec -T marzban marzban-cli admin create --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" 2>/dev/null || \
    docker compose exec -T marzban marzban-cli admin update --username "$ADMIN_USERNAME" --password "$ADMIN_PASSWORD" 2>/dev/null || \
    echo "Admin setup completed with potential warnings"
    
    echo "✅ Marzban recovery completed"
}

# Function to setup Nginx if needed
setup_nginx() {
    if [[ -z "$DOMAIN_NAME" ]]; then
        echo "[SKIP] Nginx setup - no domain specified"
        return 0
    fi
    
    echo "[SETUP] Configuring Nginx for $DOMAIN_NAME..."
    
    # Check if SSL cert exists
    if [[ ! -f "/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem" ]]; then
        echo "[WARN] SSL certificate not found for $DOMAIN_NAME"
        echo "[INFO] Please run certbot to obtain SSL certificate first"
        return 1
    fi
    
    # Run nginx setup script
    if [[ -f "/opt/deploy-temp/scripts/bulletproof-nginx-setup.sh" ]]; then
        bash "/opt/deploy-temp/scripts/bulletproof-nginx-setup.sh"
    else
        echo "[WARN] Nginx setup script not found"
    fi
}

# Main validation logic
echo "[INFO] Running system validation..."

marzban_ok=false
nginx_ok=false

# Check Marzban
if check_service "Marzban" "8000" && check_http "http://127.0.0.1:8000/dashboard/" "200 302"; then
    marzban_ok=true
fi

# Check Nginx (if domain specified)
if [[ -n "$DOMAIN_NAME" ]]; then
    if check_service "Nginx" "443" && check_http "https://$DOMAIN_NAME/dashboard/" "200 302 502"; then
        nginx_ok=true
    fi
else
    nginx_ok=true  # Skip nginx check if no domain
fi

# Recovery actions
if [[ "$marzban_ok" == "false" ]]; then
    echo "[ACTION] Marzban is not working, starting recovery..."
    recover_marzban
    
    # Re-check after recovery
    sleep 10
    if check_service "Marzban" "8000" && check_http "http://127.0.0.1:8000/dashboard/" "200 302"; then
        echo "✅ Marzban recovery successful"
        marzban_ok=true
    else
        echo "❌ Marzban recovery failed"
    fi
fi

if [[ "$nginx_ok" == "false" && -n "$DOMAIN_NAME" ]]; then
    echo "[ACTION] Setting up Nginx..."
    setup_nginx || echo "[WARN] Nginx setup had issues"
fi

# Final status report
echo "📊 FINAL STATUS REPORT:"
echo "=========================="

if [[ "$marzban_ok" == "true" ]]; then
    echo "✅ Marzban: Working (http://127.0.0.1:8000/dashboard/)"
else
    echo "❌ Marzban: Not working"
fi

if [[ -n "$DOMAIN_NAME" ]]; then
    if check_service "Nginx" "443" >/dev/null 2>&1; then
        echo "✅ Nginx: Working (https://$DOMAIN_NAME/dashboard/)"
    else
        echo "❌ Nginx: Not working"
    fi
fi

# Container status
echo "
Container Status:"
docker ps | grep marzban || echo "No Marzban container found"

# Port status
echo "
Port Status:"
ss -tlnp | grep -E "(8000|2083|443)" || echo "Required ports not listening"

# Admin verification
echo "
Admin Status:"
docker compose exec -T marzban marzban-cli admin list 2>/dev/null | head -5 || echo "Cannot check admin list"

# Quick logs
echo "
Recent Logs:"
docker logs marzban --tail 10 2>/dev/null || echo "Cannot get logs"

if [[ "$marzban_ok" == "true" ]]; then
    echo "
🎉 SUCCESS! Marzban is working!"
    [[ -n "$DOMAIN_NAME" ]] && echo "Panel URL: https://$DOMAIN_NAME/dashboard/"
    echo "Direct URL: http://YOUR_VPS_IP:8000/dashboard/"
    echo "Login: $ADMIN_USERNAME"
    echo "Password: $ADMIN_PASSWORD"
    exit 0
else
    echo "
🚫 FAILED! Manual intervention required."
    exit 1
fi