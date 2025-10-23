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

apt install -y cockpit cockpit-machines cockpit-podman cockpit-networkmanager
systemctl enable --now cockpit.socket

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

log "Done. Site: https://${DOMAIN} | Cockpit: https://${DOMAIN}:9090"
