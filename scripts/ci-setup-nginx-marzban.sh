#!/bin/bash
# Idempotent Marzban panel exposure via Nginx, to be called from CI after Terraform
# Safe to run multiple times; only makes changes when missing
set -euo pipefail

DOMAIN_NAME="${DOMAIN_NAME:-}"
[[ -z "$DOMAIN_NAME" ]] && { echo "DOMAIN_NAME is required"; exit 1; }
CONF="/etc/nginx/sites-available/$DOMAIN_NAME"
if [[ ! -f "$CONF" ]]; then
  echo "[WARN] $CONF not found; skipping nginx integration"
  exit 0
fi

# Add /dashboard reverse-proxy if not present
if ! grep -q "location /dashboard/" "$CONF"; then
  awk '
    BEGIN{https=0; depth=0}
    /server\s*\{/ {depth++}
    /\}/ {depth--}
    {print}
    /listen 443/ && depth==1 {https=1}
    https && /server_tokens off;|error_log/ {
      print "\n    # Marzban panel proxy";
      print "    location /dashboard/ {";
      print "        proxy_pass http://127.0.0.1:8000/;";
      print "        proxy_set_header Host $host;";
      print "        proxy_set_header X-Forwarded-Proto $scheme;";
      print "        proxy_set_header X-Real-IP $remote_addr;";
      print "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;";
      print "        proxy_http_version 1.1;";
      print "        proxy_set_header Upgrade $http_upgrade;";
      print "        proxy_set_header Connection \"upgrade\";";
      print "        proxy_read_timeout 300;";
      print "        proxy_send_timeout 300;";
      print "    }";
      https=0
    }
  ' "$CONF" > /tmp/nginx.conf.new
  mv /tmp/nginx.conf.new "$CONF"
  nginx -t && systemctl reload nginx
  echo "[OK] Added /dashboard proxy and reloaded nginx"
else
  echo "[OK] /dashboard proxy already configured"
fi
