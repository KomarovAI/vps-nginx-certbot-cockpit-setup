#!/bin/bash
set -euo pipefail

# Enhanced logging and error handling
LOGFILE="/var/log/vps-setup.log"
exec 1> >(tee -a "$LOGFILE")
exec 2>&1

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
error() { log "ERROR: $*"; return 1; }
trap 'log "ERROR on line $LINENO"' ERR

log "=== VPS Setup Started ==="
log "Domain: ${DOMAIN_NAME:-not set}"
log "Email: ${ADMIN_EMAIL:-not set}"

# Validate required environment variables
if [[ -z "${DOMAIN_NAME:-}" ]]; then error "DOMAIN_NAME not set"; fi
if [[ -z "${ADMIN_EMAIL:-}" ]]; then error "ADMIN_EMAIL not set"; fi

DOMAIN="${DOMAIN_NAME}"
EMAIL="${ADMIN_EMAIL}"
IP="${VPS_IP:-}"
COCKPIT_USER="${COCKPIT_USER:-cockpit-admin}"
COCKPIT_PASSWORD="${COCKPIT_PASSWORD:-}"

# System update
log "Updating system packages..."
apt update && apt upgrade -y || log "Warning: apt upgrade had issues"
apt install -y curl wget ufw git snapd software-properties-common nginx dnsutils || error "Failed to install required packages"

# UFW setup
log "Configuring firewall..."
ufw --force enable
for p in ssh 22 80 443 9090; do ufw allow "$p" || true; done

# DNS precheck before Certbot
log "Checking DNS resolution for ${DOMAIN}..."
for attempt in {1..5}; do
  if dig +short A "${DOMAIN}" | grep -q "${VPS_IP}"; then
    log "DNS check passed for ${DOMAIN}"
    break
  else
    log "Attempt $attempt/5: DNS not propagated yet for ${DOMAIN}, waiting 30s..."
    sleep 30
    if [[ $attempt -eq 5 ]]; then
      error "DNS verification failed after 5 attempts"
    fi
  fi
done

# Install Docker
log "Installing Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
else
  log "Docker already installed"
fi

# Install Docker Compose
log "Installing Docker Compose..."
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

log "Verifying Docker installation..."
docker --version || error "Docker installation failed"
docker-compose --version || true

log "Starting Docker service..."
systemctl enable --now docker || error "Failed to start Docker"

# Nginx setup
log "Configuring Nginx..."
mkdir -p "/var/www/${DOMAIN}"
echo "<h1>Welcome to ${DOMAIN}</h1>" > "/var/www/${DOMAIN}/index.html"

cat > "/etc/nginx/sites-available/${DOMAIN}" <<NGINX
server {
    listen 80;
    server_name ${DOMAIN};
    root /var/www/${DOMAIN};
    index index.html;
    
    location /.well-known/acme-challenge/ {
        root /var/www/${DOMAIN};
    }
}
NGINX

ln -sf "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/${DOMAIN}"
nginx -t && systemctl reload nginx || error "Nginx configuration failed"

# Certbot with retry logic
log "Installing Certbot and obtaining SSL certificate..."
snap install core; snap refresh core
snap install --classic certbot || error "Certbot snap installation failed"
ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true

log "Attempting to obtain SSL certificate (with retries)..."
for attempt in {1..3}; do
  if certbot certonly --webroot -w "/var/www/${DOMAIN}" -d "${DOMAIN}" \
    --email "${EMAIL}" --agree-tos --no-eff-email --non-interactive; then
    log "✓ SSL certificate obtained successfully"
    break
  else
    log "Attempt $attempt/3: Certbot failed, waiting 60s before retry..."
    sleep 60
    if [[ $attempt -eq 3 ]]; then
      error "Failed to obtain SSL certificate after 3 attempts"
    fi
  fi
done

# Update Nginx for HTTPS
log "Configuring Nginx for HTTPS..."
cat > "/etc/nginx/sites-available/${DOMAIN}" <<NGINXSSL
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};
    
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    
    root /var/www/${DOMAIN};
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
NGINXSSL

nginx -t && systemctl reload nginx || error "Nginx HTTPS configuration failed"

# Cockpit setup
log "Installing Cockpit..."
apt install -y cockpit cockpit-machines cockpit-podman cockpit-networkmanager || log "Warning: Some Cockpit packages failed"
systemctl enable --now cockpit.socket || log "Warning: Cockpit socket failed to start"

# Use existing certs for Cockpit
mkdir -p /etc/cockpit/ws-certs.d
if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" && -f "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" ]]; then
  cp "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" "/etc/cockpit/ws-certs.d/${DOMAIN}.crt" || true
  cp "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" "/etc/cockpit/ws-certs.d/${DOMAIN}.key" || true
  chgrp cockpit-ws "/etc/cockpit/ws-certs.d/${DOMAIN}."* || true
  chmod 640 "/etc/cockpit/ws-certs.d/${DOMAIN}."* || true
  systemctl restart cockpit || true
  log "✓ Cockpit SSL certificates configured"
fi

# Cockpit subdomain (optional)
COCKPIT_SUBDOMAIN="cockpit.${DOMAIN}"
log "Configuring Nginx for ${COCKPIT_SUBDOMAIN} (optional)..."

certbot certonly --webroot -w "/var/www/${DOMAIN}" -d "${COCKPIT_SUBDOMAIN}" \
  --email "${EMAIL}" --agree-tos --no-eff-email --non-interactive || log "Warning: Cockpit subdomain cert failed (optional)"

if [[ -f "/etc/letsencrypt/live/${COCKPIT_SUBDOMAIN}/fullchain.pem" ]]; then
  cat > "/etc/nginx/sites-available/cockpit-${DOMAIN}" <<COCKPITNGINX
server {
    listen 443 ssl http2;
    server_name ${COCKPIT_SUBDOMAIN};
    
    ssl_certificate /etc/letsencrypt/live/${COCKPIT_SUBDOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${COCKPIT_SUBDOMAIN}/privkey.pem;
    
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    
    location / {
        proxy_pass https://127.0.0.1:9090;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
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
  nginx -t && systemctl reload nginx || log "Warning: Cockpit nginx config had issues"
  log "✓ Cockpit accessible at: https://${COCKPIT_SUBDOMAIN}"
fi

# Diagnostics script
cat > /root/check-services.sh <<'CHK'
#!/bin/bash
systemctl status nginx --no-pager -l || true
systemctl status cockpit --no-pager -l || true
certbot certificates || true
ss -tlnp | grep -E ':(80|443|9090)' || true
CHK
chmod +x /root/check-services.sh

# Memory optimization
log "Setting up memory optimization (zram + swap)..."
MEMORY_SCRIPT="/root/setup-memory.sh"
if [[ -f "$MEMORY_SCRIPT" ]]; then
  chmod +x "$MEMORY_SCRIPT"
  modprobe zram 2>/dev/null || log "Warning: zram module not available"
  bash "$MEMORY_SCRIPT" || log "Warning: Memory setup had issues (non-critical)"
else
  log "Warning: setup-memory.sh not found, skipping memory optimization"
fi

log "=== VPS Setup Completed Successfully ==="
log "Site: https://${DOMAIN}"
log "Cockpit: https://${DOMAIN}:9090"
log "Log file: ${LOGFILE}"
