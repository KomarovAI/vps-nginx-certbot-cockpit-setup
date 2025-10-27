#!/bin/bash
set -euo pipefail

# This script configures Nginx to proxy the root site to the service-moscow container
# Assumptions:
# - service-moscow is bound to 127.0.0.1:8080 (see docker-compose.yml)
# - DOMAIN_NAME is exported in the environment

DOMAIN="${DOMAIN_NAME:?DOMAIN_NAME is required}"
NGINX_DIR="/etc/nginx"
SITE_AVAILABLE="$NGINX_DIR/sites-available/$DOMAIN"
SITE_ENABLED="$NGINX_DIR/sites-enabled/$DOMAIN"
WEBROOT="/var/www/$DOMAIN"

mkdir -p "$WEBROOT"

cat > "$SITE_AVAILABLE" <<EOF
# HTTP (ACME + redirect)
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root $WEBROOT;
        allow all;
    }

    location / {
        return 301 https://$DOMAIN$request_uri;
    }
}

# HTTPS reverse proxy to service-moscow
server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;

    # Reverse proxy to Docker service (localhost binding)
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    access_log /var/log/nginx/${DOMAIN}.access.log;
    error_log /var/log/nginx/${DOMAIN}.error.log;
}
EOF

ln -sf "$SITE_AVAILABLE" "$SITE_ENABLED"

nginx -t && systemctl reload nginx

echo "[NGINX] Reverse proxy for $DOMAIN -> service-moscow (127.0.0.1:8080) configured"
