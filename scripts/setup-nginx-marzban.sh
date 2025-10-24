#!/bin/bash
# Idempotent Nginx integration for Marzban panel under /dashboard
# Usage: DOMAIN_NAME=example.com bash ./scripts/setup-nginx-marzban.sh
set -euo pipefail
DOMAIN="${DOMAIN_NAME:-}" 
[[ -z "$DOMAIN" ]] && { echo "DOMAIN_NAME is required"; exit 1; }
CONF="/etc/nginx/sites-available/$DOMAIN"
if [[ ! -f "$CONF" ]]; then
  echo "[WARN] $CONF not found, skipping"
  exit 0
fi
TMP=$(mktemp)
added=0
awk '
  BEGIN{in_server=0;in_https=0;depth=0}
  /server\s*\{/ {depth++; if(depth==1) in_server=1}
  /\}/ {if(depth==1) in_server=0; depth--}
  {line=$0}
  if(in_server && line ~ /listen 443/){in_https=1}
  if(in_https && line ~ /location \/dashboard\//){already=1}
  print line
  if(in_https && !already && line ~ /server_tokens off;|error_log/){
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
    already=1;
  }
' "$CONF" > "$TMP"
# Replace only if changed
if ! cmp -s "$CONF" "$TMP"; then
  mv "$TMP" "$CONF"
  nginx -t && systemctl reload nginx
  echo "[OK] /dashboard proxy added and nginx reloaded"
else
  rm -f "$TMP"
  echo "[OK] /dashboard proxy already present"
fi
