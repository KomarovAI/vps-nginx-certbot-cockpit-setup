#!/bin/bash
set -euo pipefail
DOMAIN="${DOMAIN_NAME:-}" 
if [[ -z "$DOMAIN" ]]; then echo "DOMAIN_NAME is required"; exit 1; fi
CONF="/etc/nginx/sites-available/$DOMAIN"
if [[ ! -f "$CONF" ]]; then echo "Nginx conf $CONF not found"; exit 0; fi
# insert /dashboard/ location into HTTPS server
awk '
  BEGIN{in_https=0}
  /server\s*\{/ {depth++;}
  /\}/ {depth--;}
  /listen 443/ && depth==1 {in_https=1}
  in_https && /server_tokens off;|error_log/ && !done {
    print;
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
    done=1; next
  }
  {print}
' "$CONF" > /tmp/nginx.conf.new
mv /tmp/nginx.conf.new "$CONF"
nginx -t && systemctl reload nginx
