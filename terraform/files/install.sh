#!/bin/bash
set -euo pipefail

DOMAIN="${DOMAIN_NAME:-}"
EMAIL="${ADMIN_EMAIL:-}"
IP="${VPS_IP:-}"
COCKPIT_USER="${COCKPIT_USER:-cockpit-admin}"
COCKPIT_PASSWORD="${COCKPIT_PASSWORD:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log(){ echo -e "${GREEN}[$(date '+%F %T')] $*${NC}"; }
err(){ echo -e "${RED}[ERROR] $*${NC}" >&2; }

if [[ $EUID -ne 0 ]]; then err "Run as root"; exit 1; fi
if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then err "DOMAIN_NAME and/or ADMIN_EMAIL not set"; exit 1; fi

log "Domain: ${DOMAIN} | Email: ${EMAIL} | IP: ${IP:-N/A}"

apt update && apt upgrade -y
apt install -y curl wget ufw git snapd software-properties-common nginx

ufw --force enable
for p in ssh 22 80 443 9090; do ufw allow "$p" || true; done

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Install Docker Compose
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

docker --version
docker-compose --version
apt install -y linux-modules-extra-$(uname -r) 2>/dev/null || echo "Warning: Extra modules package not available"
mkdir -p "/var/www/${DOMAIN}"
chown -R www-data:www-data "/var/www/${DOMAIN}"

cat > "/etc/nginx/sites-available/${DOMAIN}" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    root /var/www/${DOMAIN};
    index index.html index.htm;

    access_log /var/log/nginx/${DOMAIN}.access.log;
    error_log /var/log/nginx/${DOMAIN}.error.log;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ /.well-known/acme-challenge {
        allow all;
        root /var/www/${DOMAIN};
    }
}
NGINX

ln -sfn "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/${DOMAIN}"
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

if [[ ! -f "/var/www/${DOMAIN}/index.html" ]]; then
cat > "/var/www/${DOMAIN}/index.html" <<HTML
<!doctype html><html><head><meta charset="utf-8"><title>${DOMAIN}</title></head>
<body style="font-family:Arial;text-align:center;margin-top:80px">
<h1>✅ Сервер настроен</h1><h2>${DOMAIN}</h2>
<p>Nginx, SSL и Cockpit установлены</p>
<p><a href="https://${DOMAIN}:9090">Cockpit</a></p>
</body></html>
HTML
fi

snap install core; snap refresh core
apt remove -y certbot || true
snap install --classic certbot
ln -sfn /snap/bin/certbot /usr/bin/certbot

certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" --email "${EMAIL}" --agree-tos --no-eff-email --redirect
(crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet") | crontab -

# Add HSTS and security headers to Nginx
log "Adding HSTS and security headers..."
sed -i '/ssl_dhparam/a\    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;\n    add_header X-Frame-Options DENY always;\n    add_header X-Content-Type-Options nosniff always;' /etc/nginx/sites-available/${DOMAIN}
nginx -t && systemctl reload nginx

apt install -y cockpit cockpit-machines cockpit-podman cockpit-networkmanager
systemctl enable --now cockpit.socket

# Configure Cockpit SSL with Let's Encrypt certificate
mkdir -p /etc/cockpit/ws-certs.d
cp /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/cockpit/ws-certs.d/${DOMAIN}.crt
cp /etc/letsencrypt/live/${DOMAIN}/privkey.pem /etc/cockpit/ws-certs.d/${DOMAIN}.key
chown root:cockpit-ws /etc/cockpit/ws-certs.d/${DOMAIN}.*
chmod 640 /etc/cockpit/ws-certs.d/${DOMAIN}.*
systemctl restart cockpit

# Configure Cockpit.conf with IdleTimeout=0
mkdir -p /etc/cockpit
cat > /etc/cockpit/cockpit.conf <<'COCKPITCONF'
[Session]
IdleTimeout=0
COCKPITCONF

systemctl restart cockpit

# Nginx server block for cockpit subdomain
COCKPIT_SUBDOMAIN="cockpit.${DOMAIN}"
cat > "/etc/nginx/sites-available/cockpit-${DOMAIN}" <<COCKPITNGINX
server {
  listen 443 ssl http2;
  server_name ${COCKPIT_SUBDOMAIN};

  ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
  
  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
  add_header X-Frame-Options DENY always;
  add_header X-Content-Type-Options nosniff always;

  location / {
    proxy_pass https://127.0.0.1:9090;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_buffering off;
    gzip off;

    proxy_read_timeout 12h;
    proxy_send_timeout 12h;
    proxy_connect_timeout 60s;
    keepalive_timeout 12h 12h;
  }
}
COCKPITNGINX

ln -sf "/etc/nginx/sites-available/cockpit-${DOMAIN}" "/etc/nginx/sites-enabled/cockpit-${DOMAIN}"
certbot --nginx -d "${COCKPIT_SUBDOMAIN}" --email "${EMAIL}" --agree-tos --no-eff-email --redirect --non-interactive || true

nginx -t && systemctl reload nginx

if ! id -u "${COCKPIT_USER}" &>/dev/null; then
  useradd -m -s /bin/bash "${COCKPIT_USER}"
  usermod -aG sudo "${COCKPIT_USER}"
  if [[ -n "${COCKPIT_PASSWORD}" ]]; then
    echo "${COCKPIT_USER}:${COCKPIT_PASSWORD}" | chpasswd
  fi
fi

cat > /root/check-services.sh <<'CHK'
#!/bin/bash
systemctl status nginx --no-pager -l || true
systemctl status cockpit --no-pager -l || true
certbot certificates || true
ss -tlnp | grep -E ':(80|443|9090)' || true
CHK
chmod +x /root/check-services.sh

# Memory optimization: zram 1GB + swap 4GB
MEMORY_SCRIPT="/root/setup-memory.sh"
curl -s https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/setup-memory.sh -o "$MEMORY_SCRIPT"
chmod +x "$MEMORY_SCRIPT"
modprobe zram 2>/dev/null || true
bash "$MEMORY_SCRIPT"

log "🎉 VPS setup completed! (Marzban теперь раскатывает только через Terraform)"
