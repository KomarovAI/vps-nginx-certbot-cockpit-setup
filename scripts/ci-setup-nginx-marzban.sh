#!/bin/bash
# CI idempotent Nginx integration for Marzban panel under /dashboard
# - Adds/updates proper proxy with SPA fallback
# - Validates config and reloads Nginx only when changed
set -euo pipefail

DOMAIN_NAME="${DOMAIN_NAME:-}"
[[ -z "$DOMAIN_NAME" ]] && { echo "DOMAIN_NAME is required"; exit 1; }
CONF="/etc/nginx/sites-available/$DOMAIN_NAME"
[ -f "$CONF" ] || { echo "[WARN] $CONF not found; skipping"; exit 0; }

read -r -d '' BLOCK <<'EOB'
    # Marzban panel proxy
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
        proxy_pass http://127.0.0.1:8000/;
        try_files $uri $uri/ @marzban_spa;
    }
    location @marzban_spa {
        proxy_pass http://127.0.0.1:8000/;
    }
EOB

TMP=$(mktemp)
if grep -q "location /dashboard/" "$CONF"; then
  # Replace existing block
  awk -v repl="$BLOCK" '
    BEGIN{in=0}
    /location \/dashboard\// {print repl; in=1; next}
    in && /\}/ {in=0; next}
    !in {print}
  ' "$CONF" > "$TMP"
else
  # Insert right after server_tokens off; if present, otherwise before closing brace of 443 server
  awk -v repl="$BLOCK" '
    BEGIN{depth=0; https=0; inserted=0}
    /server\s*\{/ {depth++}
    /\}/ {if(depth>0) depth--}
    {line=$0}
    if(line ~ /listen 443/ && depth==1){https=1}
    print line
    if(https && !inserted && line ~ /server_tokens off;/){print "\n" repl; inserted=1}
    if(https && !inserted && depth==1 && line ~ /\}$/){print repl; inserted=1}
  ' "$CONF" > "$TMP"
fi

# Apply only if changed
if ! cmp -s "$CONF" "$TMP"; then
  mv "$TMP" "$CONF"
  nginx -t && systemctl reload nginx
  echo "[OK] Nginx updated and reloaded"
else
  rm -f "$TMP"
  echo "[OK] Nginx already up to date"
fi
