#!/bin/bash
# Bulletproof Nginx setup for Marzban panel
set -euo pipefail

DOMAIN_NAME="${DOMAIN_NAME:-}"

if [[ -z "$DOMAIN_NAME" ]]; then
    echo "ERROR: DOMAIN_NAME not set"
    exit 1
fi

echo "[INFO] Setting up Nginx for domain: $DOMAIN_NAME"

# Create Nginx config for Marzban dashboard
cat > "/etc/nginx/sites-available/$DOMAIN_NAME-marzban" << 'NGINX_EOF'
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name DOMAIN_PLACEHOLDER;

    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Marzban dashboard
    location /dashboard/ {
        proxy_pass http://127.0.0.1:8000/dashboard/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_redirect off;
        proxy_buffering off;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Marzban API
    location /api/ {
        proxy_pass http://127.0.0.1:8000/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_redirect off;
        
        # API timeouts
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    # Docs
    location /docs {
        proxy_pass http://127.0.0.1:8000/docs;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Redoc
    location /redoc {
        proxy_pass http://127.0.0.1:8000/redoc;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Root redirect
    location = / {
        return 302 https://$server_name/dashboard/;
    }

    # Default static files (if any)
    location / {
        try_files $uri $uri/ =404;
        root /var/www/$server_name;
        index index.html index.htm;
    }
}

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name DOMAIN_PLACEHOLDER;
    return 301 https://$server_name$request_uri;
}
NGINX_EOF

# Replace placeholder with actual domain
sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN_NAME/g" "/etc/nginx/sites-available/$DOMAIN_NAME-marzban"

# Enable the site
ln -sf "/etc/nginx/sites-available/$DOMAIN_NAME-marzban" "/etc/nginx/sites-enabled/"

# Remove default site if exists
rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
echo "[INFO] Testing Nginx configuration..."
nginx -t

# Reload nginx
echo "[INFO] Reloading Nginx..."
systemctl reload nginx

echo "[SUCCESS] Nginx configured for $DOMAIN_NAME"
echo "Dashboard will be available at: https://$DOMAIN_NAME/dashboard/"