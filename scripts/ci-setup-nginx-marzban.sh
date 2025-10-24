#!/bin/bash
# CI idempotent Nginx integration for Marzban panel under /dashboard
# - Adds/updates proper proxy configuration
# - Validates config and reloads Nginx only when changed
# - Supports API endpoints and static files
set -euo pipefail

DOMAIN_NAME="${DOMAIN_NAME:-}"
[[ -z "$DOMAIN_NAME" ]] && { echo "DOMAIN_NAME is required"; exit 1; }
CONF="/etc/nginx/sites-available/$DOMAIN_NAME"
[ -f "$CONF" ] || { echo "[WARN] $CONF not found; skipping"; exit 0; }

# Complete Marzban nginx configuration block
read -r -d '' MARZBAN_BLOCK <<'EOB'
    # Marzban panel proxy configuration
    location /dashboard {
        return 301 /dashboard/;
    }
    
    location /dashboard/ {
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300;
        proxy_send_timeout 300;
        proxy_connect_timeout 10;
        proxy_pass http://127.0.0.1:8000/;
    }
    
    # Marzban API endpoints
    location /api/ {
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://127.0.0.1:8000/api/;
    }
    
    # Marzban WebSocket support
    location /ws/ {
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://127.0.0.1:8000/ws/;
    }
    
    # Marzban static files
    location /statics/ {
        proxy_pass http://127.0.0.1:8000/statics/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        expires 1d;
        add_header Cache-Control "public, immutable";
    }
EOB

echo "[INFO] Processing nginx config for $DOMAIN_NAME"

# Create temporary file
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# Check if Marzban config already exists
if grep -q "# Marzban panel proxy" "$CONF" || grep -q "location /dashboard/" "$CONF"; then
    echo "[INFO] Marzban config found, updating..."
    # Remove existing Marzban block and add new one
    awk -v repl="$MARZBAN_BLOCK" '
        BEGIN{skip=0; depth=0; server_depth=0; https_server=0; inserted=0}
        /server\s*\{/ {server_depth++; depth++}
        /\}/ {depth--; if(server_depth>0 && depth<server_depth) server_depth=0}
        /listen 443/ && server_depth==1 {https_server=1}
        
        # Skip existing Marzban configuration
        /# Marzban panel proxy/ || /location \/dashboard/ || /location \/api\// || /location \/ws\// || /location \/statics\// {
            if(/location/) {
                skip=1; brace_depth=0
                next
            } else {
                skip=1; next
            }
        }
        skip && /\{/ {brace_depth++}
        skip && /\}/ {
            brace_depth--
            if(brace_depth <= 0) {skip=0; brace_depth=0}
            next
        }
        skip {next}
        
        # Insert new config after server_tokens or before closing brace
        {print}
        if(https_server && !inserted && !skip) {
            if(/server_tokens off;/) {
                print "\n" repl
                inserted=1
            } else if(/\}$/ && server_depth==1 && depth==0) {
                # Insert before server closing brace if not inserted yet
                print repl
                inserted=1
            }
        }
    ' "$CONF" > "$TMP"
else
    echo "[INFO] Adding new Marzban config..."
    # Add new Marzban block
    awk -v repl="$MARZBAN_BLOCK" '
        BEGIN{depth=0; server_depth=0; https_server=0; inserted=0}
        /server\s*\{/ {server_depth++; depth++}
        /\}/ {depth--; if(server_depth>0 && depth<server_depth) server_depth=0}
        /listen 443/ && server_depth==1 {https_server=1}
        
        {print}
        if(https_server && !inserted) {
            if(/server_tokens off;/) {
                print "\n" repl
                inserted=1
            } else if(/\}$/ && server_depth==1 && depth==0) {
                # Insert before closing brace if server_tokens not found
                print repl
                inserted=1
            }
        }
    ' "$CONF" > "$TMP"
fi

# Apply changes only if different
if ! cmp -s "$CONF" "$TMP"; then
    echo "[INFO] Config changed, updating..."
    cp "$TMP" "$CONF"
    
    # Test and reload nginx
    if nginx -t; then
        systemctl reload nginx
        echo "[SUCCESS] Nginx updated and reloaded"
        
        # Verify dashboard is accessible
        sleep 2
        if command -v curl >/dev/null; then
            HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' "https://$DOMAIN_NAME/dashboard/" || echo "000")
            case "$HTTP_CODE" in
                200|302|401) echo "[SUCCESS] Dashboard accessible (HTTP $HTTP_CODE)" ;;
                *) echo "[WARN] Dashboard returned HTTP $HTTP_CODE" ;;
            esac
        fi
    else
        echo "[ERROR] Nginx config test failed"
        exit 1
    fi
else
    echo "[OK] Nginx config already up to date"
fi

echo "[INFO] Marzban dashboard should be available at: https://$DOMAIN_NAME/dashboard/"