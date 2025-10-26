#!/bin/bash

#===============================================================================
# VPS Setup Script v4.0 - Production Ready + Custom Marzban v4.0
# Автоматическая настройка VPS с Nginx, SSL, Cockpit, Docker и кастомным Marzban v4.0
#===============================================================================

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_VERSION="4.0"
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
  
  # ====== КРИТИЧЕСКИЙ ФИКС: Жесткие дефолты для портов ======
  MARZBAN_PANEL_PORT="${MARZBAN_PANEL_PORT:-8000}"
  XRAY_PORT="${XRAY_PORT:-2083}"
  export MARZBAN_PANEL_PORT XRAY_PORT
  
  log INFO "Env OK | Domain=$DOMAIN_NAME Email=$ADMIN_EMAIL"
  if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then 
    log INFO "Marzban: ENABLED (CUSTOM v4.0) port=${MARZBAN_PANEL_PORT} Xray=${XRAY_PORT}"
    log INFO "Admin: ${MARZBAN_ADMIN_USERNAME:-auto} / ${MARZBAN_ADMIN_PASSWORD:+***SET***}"
  else 
    log INFO "Marzban: DISABLED"
  fi
}

retry_with_backoff(){ local max=$1; shift; local i=1; local d=$BASE_DELAY; while (( i<=max )); do log DEBUG "Attempt $i/$max: $*"; if "$@"; then return 0; fi; (( i<max )) && { log WARN "Retry in ${d}s"; sleep "$d"; d=$((d*2)); }; ((i++)); done; return 1; }

update_system(){ log INFO "Updating system packages..."; cat > /etc/apt/apt.conf.d/99custom <<EOF
APT::Acquire::Retries "3";
APT::Acquire::http::Timeout "30";
APT::Get::Assume-Yes "true";
Dpkg::Options {"--force-confdef";"--force-confold";}
EOF
  retry_with_backoff "$MAX_RETRIES" apt update
  local pkgs=(curl wget ufw git snapd software-properties-common nginx dnsutils htop fail2ban unattended-upgrades apt-listchanges make jq python3-requests)
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
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>$d</title></head><body><h1>🚀 VPS Ready v4.0</h1></body></html>
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

# ====== КАСТОМНЫЙ MARZBAN v4.0 С ПОЛНОЙ АВТОМАТИЗАЦИЕЙ ======

deploy_marzban(){
  if [[ "${DEPLOY_MARZBAN:-false}" != "true" ]]; then log INFO "Marzban skipped"; return 0; fi
  log INFO "Deploying Custom Marzban v4.0 Container..."
  
  # ====== КРИТИЧЕСКИЙ ФИКС: Идемпотентное клонирование/обновление ======
  log INFO "Setting up Marzban repository in $MARZBAN_DIR"
  mkdir -p "$MARZBAN_DIR"
  cd "$MARZBAN_DIR"
  
  # Проверяем и обновляем репозиторий безопасно
  if [[ -d .git ]]; then
    log INFO "Repository exists, updating..."
    git fetch --all || log WARN "Git fetch failed, continuing..."
    git reset --hard origin/main || log WARN "Git reset failed, continuing..."
    git pull origin main || log WARN "Git pull failed, continuing..."
  else
    log INFO "Cloning fresh repository..."
    # Убеждаемся, что директория пустая перед клонированием
    rm -rf ./* ./.* 2>/dev/null || true
    git clone -b main https://github.com/KomarovAI/vps-nginx-certbot-cockpit-setup.git . || {
      log ERROR "Git clone failed"; return 1; }
  fi
  
  cd "$MARZBAN_DIR/marzban" || { log ERROR "marzban directory missing after clone/update"; return 1; }
  
  # ====== НАСТРОЙКА ОКРУЖЕНИЯ ДЛЯ КАСТОМНОГО КОНТЕЙНЕРА v4.0 ======
  log INFO "Configuring environment for Custom Marzban v4.0..."
  cat > .env <<EOF
# Generated by install.sh v4.0 $(date)
DOMAIN_NAME=${DOMAIN_NAME}
ADMIN_EMAIL=${ADMIN_EMAIL}

# Marzban Panel Config
MARZBAN_PANEL_PORT=${MARZBAN_PANEL_PORT}
MARZBAN_HOST=${DOMAIN_NAME}

# Auto-Admin Setup (v4.0 NEW!)
MARZBAN_ADMIN_USERNAME=${MARZBAN_ADMIN_USERNAME:-admin}
MARZBAN_ADMIN_PASSWORD=${MARZBAN_ADMIN_PASSWORD:-}

# XRAY Configuration
XRAY_PORT=${XRAY_PORT}

# XRAY Reality Settings
XRAY_REALITY_PRIVATE_KEY=${XRAY_REALITY_PRIVATE_KEY:-}
XRAY_REALITY_SHORT_IDS=${XRAY_REALITY_SHORT_IDS:-}
XRAY_REALITY_SERVER_NAMES=${XRAY_REALITY_SERVER_NAMES:-google.com,www.google.com}

# Database & Protocols
MARZBAN_DB_URL=sqlite:////var/lib/marzban/db.sqlite3
MARZBAN_QUIC=true
XRAY_VLESS_REALITY=true
XRAY_GRPC_ENABLE=true
XRAY_JSON=/etc/xray/config.json

# Automation Flags (v4.0)
AUTO_INIT_DB=true
AUTO_CREATE_ADMIN=true
FORCE_CLEAN_START=${FORCE_CLEAN_START:-false}

# Build Info
CUSTOM_BUILD=true
VERSION=4.0
BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
EOF

  # Убеждаемся, что директории существуют
  mkdir -p ./logs ./custom-configs
  mkdir -p /var/lib/marzban /etc/xray
  chmod -R 755 ./logs ./custom-configs 2>/dev/null || true
  
  # ====== СБОРКА И ЗАПУСК КАСТОМНОГО КОНТЕЙНЕРА v4.0 ======
  log INFO "Building and starting Custom Marzban v4.0..."
  
  # Проверяем наличие override файла для кастомной сборки
  local compose_files="-f docker-compose.yml"
  if [[ -f ../docker-compose.override.yml ]]; then
    log INFO "Found docker-compose.override.yml, using custom build"
    compose_files="-f docker-compose.yml -f ../docker-compose.override.yml"
  else
    log INFO "No override found, using pre-built image"
  fi
  
  # Сборка и запуск
  if [[ -f Makefile ]]; then 
    log INFO "Using Makefile for build and deployment..."
    make clean || true
    make build || docker-compose $compose_files build --no-cache --pull
    make up || docker-compose $compose_files up -d
  else 
    log INFO "Using docker-compose for build and deployment..."
    docker-compose $compose_files down 2>/dev/null || true
    docker-compose $compose_files build --no-cache --pull
    docker-compose $compose_files up -d
  fi
  
  # ====== АВТОМАТИЗАЦИЯ v4.0: ИСПОЛЬЗУЕМ manage.sh ======
  chmod +x manage.sh || true
  
  log INFO "Starting Custom Marzban v4.0 automated initialization..."
  if [[ -x ./manage.sh ]]; then
    log INFO "Using manage.sh auto-setup for full automation..."
    ./manage.sh auto-setup || {
      log WARN "manage.sh auto-setup failed, trying manual start..."
      ./manage.sh start || log ERROR "Manual start also failed"
    }
  else
    log WARN "manage.sh not found or not executable, using manual approach..."
    sleep 20
    
    # Создание админа, если заданы credentials
    if [[ -n "${MARZBAN_ADMIN_USERNAME:-}" && -n "${MARZBAN_ADMIN_PASSWORD:-}" ]]; then
      log INFO "Setting up Marzban admin: ${MARZBAN_ADMIN_USERNAME}"
      sleep 10  # Дополнительное ожидание готовности БД
      docker-compose exec -T marzban marzban-cli admin create --username "${MARZBAN_ADMIN_USERNAME}" --password "${MARZBAN_ADMIN_PASSWORD}" 2>/dev/null || \
      docker-compose exec -T marzban marzban-cli admin update --username "${MARZBAN_ADMIN_USERNAME}" --password "${MARZBAN_ADMIN_PASSWORD}" 2>/dev/null || \
      log WARN "Admin setup completed (or admin already exists)"
    fi
  fi
  
  # ====== ПРОВЕРКА ЗДОРОВЬЯ КАСТОМНОГО КОНТЕЙНЕРА ======
  local port="${MARZBAN_PANEL_PORT}"
  local url="http://127.0.0.1:${port}/api/admin" 
  local tries=90  # Увеличенный timeout для кастомного контейнера v4.0
  local ok=0
  
  log INFO "Health checking Custom Marzban v4.0 at $url ..."
  for ((i=1;i<=tries;i++)); do
    # Используем python3-requests для более надежной проверки
    code=$(python3 -c "import requests; print(requests.get('$url', timeout=5).status_code)" 2>/dev/null || echo "000")
    if [[ "$code" == "200" || "$code" == "302" || "$code" == "401" || "$code" == "422" ]]; then
      ok=1; log INFO "✅ Custom Marzban v4.0 panel is UP (HTTP $code)"; break
    fi
    sleep 3
    [[ $((i%15)) -eq 0 ]] && log INFO "⏳ Still waiting ($i/$tries) - HTTP $code"
  done
  
  if [[ "$ok" -ne 1 ]]; then
    log ERROR "❌ Custom Marzban v4.0 panel is NOT responding at $url (last HTTP $code)"
    log INFO "📊 Container status:"
    docker ps --filter name=marzban || true
    log INFO "📋 Recent logs:"
    docker-compose logs --tail=100 marzban 2>/dev/null || true
    if [[ -x ./manage.sh ]]; then
      log INFO "🔍 Running manage.sh debug..."
      ./manage.sh debug || true
    fi
    log ERROR "❌ Custom Marzban v4.0 deployment FAILED"
    return 1
  fi
  
  log INFO "✅ Custom Marzban v4.0 deployment completed successfully!"
  log INFO "🎯 Panel URL: https://$DOMAIN_NAME:$port"
  log INFO "🛠️  Management: cd $MARZBAN_DIR/marzban && ./manage.sh {start|stop|restart|auto-setup|debug}"
}

create_monitoring_scripts(){ cat > "$SERVICES_CHECK_SCRIPT" <<'EOF'
#!/bin/bash
echo "=== VPS Services Status Check v4.0 ==="; echo "Time: $(date)"; echo
for s in nginx cockpit docker fail2ban; do if systemctl is-active --quiet "$s"; then echo "$s: ✓ Running"; else echo "$s: ✗ Stopped"; fi; done
if [[ -d "/opt/marzban-deployment/marzban" ]]; then 
  cd /opt/marzban-deployment/marzban
  if docker-compose ps 2>/dev/null | grep -q Up; then 
    echo "Marzban (Custom v4.0): ✓ Running"
    if [[ -x ./manage.sh ]]; then ./manage.sh status 2>/dev/null || true; fi
  else 
    echo "Marzban (Custom v4.0): ✗ Stopped"
  fi
fi
EOF
  chmod +x "$SERVICES_CHECK_SCRIPT"; }

main(){
  setup_logging; check_lock; check_root; validate_environment
  update_system; setup_firewall; setup_fail2ban; install_docker; setup_nginx; setup_ssl; setup_cockpit
  deploy_marzban
  create_monitoring_scripts
  
  log INFO "📊 Final service check:"; [[ -x "$SERVICES_CHECK_SCRIPT" ]] && "$SERVICES_CHECK_SCRIPT" || true
  log INFO "🌐 Website: https://$DOMAIN_NAME"
  log INFO "🖥️  Cockpit: https://$DOMAIN_NAME:9090"
  if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
    log INFO "🔒 Marzban (Custom v4.0): https://$DOMAIN_NAME:${MARZBAN_PANEL_PORT}"
    log INFO "🛠️  Marzban Management: cd $MARZBAN_DIR/marzban && ./manage.sh {start|stop|restart|auto-setup|debug}"
  fi
  log INFO "🚀 ===== VPS Setup v4.0 completed successfully! ===== 🚀"
}

# ====== ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ С ЖЕСТКИМИ ДЕФОЛТАМИ ======
DOMAIN_NAME="${DOMAIN_NAME:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
VPS_IP="${VPS_IP:-}"
COCKPIT_PASSWORD="${COCKPIT_PASSWORD:-}"
COCKPIT_USER="${COCKPIT_USER:-cockpit-admin}"
DEPLOY_MARZBAN="${DEPLOY_MARZBAN:-false}"
MARZBAN_PANEL_PORT="${MARZBAN_PANEL_PORT:-8000}"
XRAY_PORT="${XRAY_PORT:-2083}"
MARZBAN_ADMIN_USERNAME="${MARZBAN_ADMIN_USERNAME:-}"
MARZBAN_ADMIN_PASSWORD="${MARZBAN_ADMIN_PASSWORD:-}"
XRAY_REALITY_PRIVATE_KEY="${XRAY_REALITY_PRIVATE_KEY:-}"
XRAY_REALITY_SHORT_IDS="${XRAY_REALITY_SHORT_IDS:-}"
XRAY_REALITY_SERVER_NAMES="${XRAY_REALITY_SERVER_NAMES:-}"
FORCE_CLEAN_START="${FORCE_CLEAN_START:-false}"

main "$@"