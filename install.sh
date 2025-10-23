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
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# Install Docker Compose
echo "Installing Docker Compose..."
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Verify installations
echo "Verifying Docker installation..."
docker --version
echo "Verifying Docker Compose installation..."
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
        try_files \$uri \$uri/ =404;
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

# Configure Cockpit with Let's Encrypt SSL certificate
log "Configuring Cockpit SSL with Let's Encrypt certificate..."
mkdir -p /etc/cockpit/ws-certs.d
cp /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/cockpit/ws-certs.d/${DOMAIN}.crt
cp /etc/letsencrypt/live/${DOMAIN}/privkey.pem /etc/cockpit/ws-certs.d/${DOMAIN}.key
chown root:cockpit-ws /etc/cockpit/ws-certs.d/${DOMAIN}.*
chmod 640 /etc/cockpit/ws-certs.d/${DOMAIN}.*
systemctl restart cockpit

if ! id -u "${COCKPIT_USER}" &>/dev/null; then
  useradd -m -s /bin/bash "${COCKPIT_USER}"
  usermod -aG sudo "${COCKPIT_USER}"
  if [[ -n "${COCKPIT_PASSWORD}" ]]; then
    echo "${COCKPIT_USER}:${COCKPIT_PASSWORD}" | chpasswd
    log "Cockpit password set from environment"
  else
    log "Set Cockpit password manually: passwd ${COCKPIT_USER}"
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
log "Setting up memory optimization (zram 1GB + swap 4GB)..."
MEMORY_SCRIPT="/root/setup-memory.sh"
curl -s https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/setup-memory.sh -o "$MEMORY_SCRIPT"
chmod +x "$MEMORY_SCRIPT"
log "Loading zram kernel module..."
modprobe zram 2>/dev/null || log "Warning: zram module not available"
bash "$MEMORY_SCRIPT"

log "Done. Site: https://${DOMAIN} | Cockpit: https://${DOMAIN}:9090

# Deploy Marzban VPN Panel
log "Setting up Marzban VPN panel..."
MARZBAN_DIR="/root/marzban"
mkdir -p "$MARZBAN_DIR"
cd "$MARZBAN_DIR"

# Download docker-compose and nginx config
curl -s https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/marzban/docker-compose.yml -o docker-compose.yml
curl -s https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/marzban/marzban.conf -o /etc/nginx/sites-available/marzban.conf

# Enable nginx config
ln -sf /etc/nginx/sites-available/marzban.conf /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# Start Marzban with docker compose
docker compose up -d

log "Marzban VPN panel deployed! Access it at: https://vpn.${DOMAIN_NAME}:9090""
