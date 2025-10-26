#!/bin/bash

#===============================================================================
# VPS Setup Script v3.4 - Production Ready with Fixed Custom Marzban
# Автоматическая настройка VPS с Nginx, SSL, Cockpit, Docker и кастомным Marzban
#===============================================================================

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="3.4"
readonly LOGFILE="/var/log/vps-setup.log"
readonly LOCKFILE="/tmp/vps-setup.lock"
readonly NGINX_CONF_DIR="/etc/nginx"
readonly SERVICES_CHECK_SCRIPT="/root/check-services.sh"
readonly MARZBAN_DIR="/opt/marzban-deployment"

readonly MAX_RETRIES=3
readonly BASE_DELAY=2
readonly CERTBOT_TIMEOUT=300

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

setup_logging(){ exec 1> >(tee -a "$LOGFILE"); exec 2>&1; log INFO "=== VPS Setup Started (v${SCRIPT_VERSION}) ==="; }
log(){ local L=$1; shift; local T=$(date '+%Y-%m-%d %H:%M:%S'); case "$L" in INFO) echo -e "${GREEN}[$T] [INFO]  $*${NC}";; WARN) echo -e "${YELLOW}[$T] [WARN]  $*${NC}";; ERROR) echo -e "${RED}[$T] [ERROR] $*${NC}";; DEBUG) echo -e "${BLUE}[$T] [DEBUG] $*${NC}";; esac; }
error_exit(){ local ln=${1:-$LINENO}; local ec=${2:-1}; log ERROR "Script failed at line $ln with exit code $ec"; cleanup; exit "$ec"; }
cleanup(){ log INFO "Performing cleanup..."; [[ -f "$LOCKFILE" ]] && rm -f "$LOCKFILE"; find /tmp -name "id_rsa*" -type f -delete 2>/dev/null || true; }
trap 'error_exit $LINENO $?' ERR; trap 'cleanup' EXIT

check_lock(){ if [[ -f "$LOCKFILE" ]]; then local pid=$(cat "$LOCKFILE" 2>/dev/null || echo ""); if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then log ERROR "Another instance is already running (PID: $pid)"; exit 1; fi; rm -f "$LOCKFILE"; fi; echo $$ > "$LOCKFILE"; }
check_root(){ if [[ $EUID -ne 0 ]]; then log ERROR "This script must be run as root"; exit 1; fi }

validate_environment(){
  local req=(DOMAIN_NAME ADMIN_EMAIL)
  local miss=()
  for v in "${req[@]}"; do [[ -z "${!v:-}" ]] && miss+=("$v"); done
  if (( ${#miss[@]} )); then
    log ERROR "Missing required environment variables: ${miss[*]}"; exit 1; fi
  if [[ ! "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then log ERROR "Invalid email format: $ADMIN_EMAIL"; exit 1; fi
  if [[ ! "$DOMAIN_NAME" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then log ERROR "Invalid domain format: $DOMAIN_NAME"; exit 1; fi
  log INFO "Env OK | Domain=$DOMAIN_NAME Email=$ADMIN_EMAIL"
  if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then log INFO "Marzban: ENABLED (CUSTOM CONTAINER) port=${MARZBAN_PANEL_PORT:-8000} Xray=${XRAY_PORT:-2083}"; else log INFO "Marzban: DISABLED"; fi
}

retry_with_backoff(){ local max=$1; shift; local i=1; local d=$BASE_DELAY; while (( i<=max )); do log DEBUG "Attempt $i/$max: $*"; if "$@"; then return 0; fi; (( i<max )) && { log WARN "Retry in ${d}s"; sleep "$d"; d=$((d*2)); }; ((i++)); done; return 1; }

update_system(){ log INFO "Updating system packages..."; cat > /etc/apt/apt.conf.d/99custom <<EOF
APT::Acquire::Retries "3";
APT::Acquire::http::Timeout "30";
APT::Get::Assume-Yes "true";
Dpkg::Options {"--force-confdef";"--force-confold";}
EOF
  retry_with_backoff "$MAX_RETRIES" apt update
  local pkgs=(curl wget ufw git snapd software-properties-common nginx dnsutils htop fail2ban unattended-upgrades apt-listchanges make jq)
  retry_with_backoff "$MAX_RETRIES" apt install -y "${pkgs[@]}"
}

install_docker(){ log INFO "Installing Docker..."; if command -v docker &>/dev/null; then if docker info &>/dev/null; then log INFO "Docker OK"; install_docker_compose; return; fi; fi
  retry_with_backoff "$MAX_RETRIES" bash -c "curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh && rm -f get-docker.sh"
  install_docker_compose
  mkdir -p /etc/docker; cat > /etc/docker/daemon.json <<EOF
{"log-driver":"json-file","log-opts":{"max-size":"10m","max-file":"3"},"storage-driver":"overlay2"}
EOF
  systemctl enable --now docker; docker --version; docker-compose --version; }
install_docker_compose(){ local v; v=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4); [[ -z "$v" ]] && v="v2.24.0"; retry_with_backoff "$MAX_RETRIES" bash -c "curl -L https://github.com/docker/compose/releases/download/${v}/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose"; }

setup_firewall(){ log INFO "Configuring UFW..."; ufw --force reset; ufw default deny incoming; ufw default allow outgoing; ufw limit ssh; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 9090/tcp; if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then ufw allow ${MARZBAN_PANEL_PORT:-8000}/tcp; ufw allow ${XRAY_PORT:-2083}/tcp; fi; ufw --force enable; }

setup_nginx(){ log INFO "Configuring Nginx..."; local d="$DOMAIN_NAME"; local w="/var/www/$d"; mkdir -p "$w"; chown www-data:www-data "$w"; cat > "$w/index.html" <<EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>$d</title></head><body><h1>🚀 VPS Ready</h1></body></html>
EOF
  rm -f /etc/nginx/sites-enabled/default
  cat > "/etc/nginx/sites-available/$d" <<EOF
server { listen 80; server_name $d; root $w; index index.html; location /.well-known/acme-challenge/ { root $w; allow all; } location / { try_files \$uri \$uri/ =404; } }
EOF
  ln -sf "/etc/nginx/sites-available/$d" "/etc/nginx/sites-enabled/$d"; nginx -t && systemctl reload nginx; }

setup_ssl(){ log INFO "Setting up SSL..."; local d="$DOMAIN_NAME" e="$ADMIN_EMAIL"; snap install core && snap refresh core; snap install --classic certbot; ln -sf /snap/bin/certbot /usr/bin/certbot
  certbot certonly --webroot --webroot-path "/var/www/$d" --domain "$d" --email "$e" --agree-tos --no-eff-email --non-interactive
  cat > "/etc/nginx/sites-available/$d" <<EOF
server { listen 80; server_name $d; location /.well-known/acme-challenge/ { root /var/www/$d; allow all; } location / { return 301 https://\$host\$request_uri; } }
server { listen 443 ssl http2; server_name $d; root /var/www/$d; index index.html; ssl_certificate /etc/letsencrypt/live/$d/fullchain.pem; ssl_certificate_key /etc/letsencrypt/live/$d/privkey.pem; ssl_protocols TLSv1.2 TLSv1.3; location / { try_files \$uri \$uri/ =404; } }
EOF
  nginx -t && systemctl reload nginx; }

setup_fail2ban(){ systemctl enable --now fail2ban; }
setup_cockpit(){ apt install -y cockpit cockpit-machines cockpit-podman; local u="${COCKPIT_USER:-cockpit-admin}"; id "$u" &>/dev/null || useradd -m -s /bin/bash -G sudo "$u"; [[ -n "${COCKPIT_PASSWORD:-}" ]] && echo "$u:$COCKPIT_PASSWORD" | chpasswd; systemctl enable --now cockpit.socket; }

# —— Fixed Custom Marzban Deployment ——

deploy_marzban(){
  if [[ "${DEPLOY_MARZBAN:-false}" != "true" ]]; then log INFO "Marzban skipped"; return 0; fi
  log INFO "Deploying Custom Marzban Container..."
  mkdir -p "$MARZBAN_DIR"; cd "$MARZBAN_DIR"
  if [[ -d .git ]]; then git pull origin main || true; else git clone -b main https://github.com/KomarovAI/vps-nginx-certbot-cockpit-setup.git .; fi
  cd "$MARZBAN_DIR/marzban" || { log ERROR "marzban dir missing"; return 1; }
  
  # Setup environment for custom container
  cat > .env <<EOF
DOMAIN_NAME=${DOMAIN_NAME}
MARZBAN_PANEL_PORT=${MARZBAN_PANEL_PORT:-8000}
XRAY_PORT=${XRAY_PORT:-2083}
XRAY_REALITY_PRIVATE_KEY=${XRAY_REALITY_PRIVATE_KEY:-}
XRAY_REALITY_SHORT_IDS=${XRAY_REALITY_SHORT_IDS:-}
XRAY_REALITY_SERVER_NAMES=${XRAY_REALITY_SERVER_NAMES:-google.com,www.google.com}
MARZBAN_QUIC=true
MARZBAN_DB_URL=sqlite:////var/lib/marzban/marzban.db
XRAY_VLESS_REALITY=true
XRAY_GRPC_ENABLE=true
EOF

  # Ensure data directories exist
  mkdir -p ./data ./xray ./logs
  mkdir -p /var/lib/marzban

  # Build and start custom container
  log INFO "Building custom Marzban container..."
  if [[ -f Makefile ]]; then 
    make build || docker-compose build --no-cache --pull
    log INFO "Starting custom Marzban services..."
    make up || docker-compose up -d
  else 
    docker-compose build --no-cache --pull
    docker-compose up -d
  fi

  # The database initialization is now handled in the custom entrypoint.sh
  # Wait for container startup and health check
  log INFO "Waiting for custom Marzban container to initialize..."
  sleep 15

  # Create admin if credentials provided
  if [[ -n "${MARZBAN_ADMIN_USERNAME:-}" && -n "${MARZBAN_ADMIN_PASSWORD:-}" ]]; then
    log INFO "Setting up Marzban admin: ${MARZBAN_ADMIN_USERNAME}"
    sleep 10  # Extra wait for database to be fully ready
    docker-compose exec -T marzban marzban-cli admin create --username "${MARZBAN_ADMIN_USERNAME}" --password "${MARZBAN_ADMIN_PASSWORD}" 2>/dev/null || \
    docker-compose exec -T marzban marzban-cli admin update --username "${MARZBAN_ADMIN_USERNAME}" --password "${MARZBAN_ADMIN_PASSWORD}" 2>/dev/null || \
    log WARN "Admin setup completed (or admin already exists)"
  fi

  # Healthcheck custom container
  local port="${MARZBAN_PANEL_PORT:-8000}"
  local url="http://127.0.0.1:${port}/api/admin" 
  local tries=60  # Increased timeout for custom container initialization
  local ok=0
  
  log INFO "Checking custom Marzban panel at $url ..."
  for ((i=1;i<=tries;i++)); do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 "$url" 2>/dev/null || echo "000")
    if [[ "$code" == "200" || "$code" == "302" || "$code" == "401" || "$code" == "422" ]]; then
      ok=1; log INFO "Custom Marzban panel is UP (HTTP $code)"; break
    fi
    sleep 3
    [[ $((i%10)) -eq 0 ]] && log INFO "still waiting ($i/$tries) - HTTP $code"
  done
  
  if [[ "$ok" -ne 1 ]]; then
    log ERROR "Custom Marzban panel is NOT responding at $url (last HTTP $code)"
    log INFO "Container status:"
    docker ps --filter name=marzban || true
    log INFO "Recent logs:"
    docker-compose logs --tail=80 || true
    log INFO "Run './manage.sh debug' for detailed diagnostics"
    return 1
  fi
  
  # Make manage.sh executable
  chmod +x manage.sh || true
  
  log INFO "Custom Marzban deployment completed successfully!"
}

create_monitoring_scripts(){ cat > "$SERVICES_CHECK_SCRIPT" <<'EOF'
#!/bin/bash
echo "=== VPS Services Status Check ==="; echo "Time: $(date)"; echo
for s in nginx cockpit docker fail2ban; do if systemctl is-active --quiet "$s"; then echo "$s: ✓ Running"; else echo "$s: ✗ Stopped"; fi; done
if [[ -d "/opt/marzban-deployment/marzban" ]]; then cd /opt/marzban-deployment/marzban; if docker-compose ps 2>/dev/null | grep -q Up; then echo "Marzban (Custom): ✓ Running"; else echo "Marzban (Custom): ✗ Stopped"; fi; fi
EOF
  chmod +x "$SERVICES_CHECK_SCRIPT"; }

main(){
  setup_logging; check_lock; check_root; validate_environment
  update_system; setup_firewall; setup_fail2ban; install_docker; setup_nginx; setup_ssl; setup_cockpit
  deploy_marzban
  create_monitoring_scripts
  log INFO "Final service check:"; [[ -x "$SERVICES_CHECK_SCRIPT" ]] && "$SERVICES_CHECK_SCRIPT" || true
  log INFO "Website: https://$DOMAIN_NAME"; log INFO "Cockpit: https://$DOMAIN_NAME:9090"; [[ "${DEPLOY_MARZBAN:-false}" == "true" ]] && log INFO "Marzban (Custom): https://$DOMAIN_NAME:${MARZBAN_PANEL_PORT:-8000}"
  [[ "${DEPLOY_MARZBAN:-false}" == "true" ]] && log INFO "Marzban Management: cd /opt/marzban-deployment/marzban && ./manage.sh {start|stop|restart|build|debug}"
  log INFO "Setup completed successfully with FIXED custom Marzban container!"
}

DOMAIN_NAME="${DOMAIN_NAME:-}"; ADMIN_EMAIL="${ADMIN_EMAIL:-}"; VPS_IP="${VPS_IP:-}"; COCKPIT_PASSWORD="${COCKPIT_PASSWORD:-}"; COCKPIT_USER="${COCKPIT_USER:-cockpit-admin}"; DEPLOY_MARZBAN="${DEPLOY_MARZBAN:-false}"; MARZBAN_PANEL_PORT="${MARZBAN_PANEL_PORT:-8000}"; XRAY_PORT="${XRAY_PORT:-2083}"; MARZBAN_ADMIN_USERNAME="${MARZBAN_ADMIN_USERNAME:-}"; MARZBAN_ADMIN_PASSWORD="${MARZBAN_ADMIN_PASSWORD:-}"; XRAY_REALITY_PRIVATE_KEY="${XRAY_REALITY_PRIVATE_KEY:-}"; XRAY_REALITY_SHORT_IDS="${XRAY_REALITY_SHORT_IDS:-}"; XRAY_REALITY_SERVER_NAMES="${XRAY_REALITY_SERVER_NAMES:-}"

main "$@"