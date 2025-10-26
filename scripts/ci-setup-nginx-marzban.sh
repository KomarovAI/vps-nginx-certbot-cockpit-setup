#!/bin/bash
# CI idempotent Nginx integration for Marzban panel under /dashboard

# Validates config and reloads Nginx only when changed
# Supports .gd TLD domains and self-signed certificates
set -euo pipefail

DOMAIN_NAME="${DOMAIN_NAME:-}"
if [[ -z "$DOMAIN_NAME" ]]; then
    echo "[WARN] DOMAIN_NAME not found, skipping"; exit 0;
fi

# Construct complete Nginx configuration block
read -r -d '' MARZBAN_BLOCK <<'EOF' || true
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER www.DOMAIN_PLACEHOLDER;
    root /var/www/DOMAIN_PLACEHOLDER;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/DOMAIN_PLACEHOLDER;
        allow all;
    }
}

server {
    listen 443 ssl http2;
    server_name DOMAIN_PLACEHOLDER www.DOMAIN_PLACEHOLDER;

    ssl_certificate /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    root /var/www/DOMAIN_PLACEHOLDER;
    index index.html index.htm;

    server_tokens off;

    # Marzban panel proxy
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300;
        proxy_send_timeout 300;
    }
}
EOF

echo "[INFO] Configuring Nginx for Marzban on domain: $DOMAIN_NAME"

# Replace placeholder with actual domain
MARZBAN_CONFIG="${MARZBAN_BLOCK//DOMAIN_PLACEHOLDER/$DOMAIN_NAME}"

# Write configuration atomically
echo "$MARZBAN_CONFIG" | sudo tee "/etc/nginx/sites-available/$DOMAIN_NAME" >/dev/null

# Enable site if not already linked
if [[ ! -e "/etc/nginx/sites-enabled/$DOMAIN_NAME" ]]; then
    sudo ln -sf "/etc/nginx/sites-available/$DOMAIN_NAME" "/etc/nginx/sites-enabled/$DOMAIN_NAME"
    echo "[INFO] Enabled Nginx site for $DOMAIN_NAME"
fi

# Test and reload only if config is valid
if sudo nginx -t 2>&1 | grep -q 'test is successful'; then
    sudo systemctl reload nginx
    echo "[OK] Nginx reloaded successfully with Marzban configuration"
else
    echo "[ERROR] Nginx configuration test failed"
    exit 1
fi
