#!/bin/bash

#===============================================================================
# VPS Setup Script v3.1 - Production Ready with Marzban
# Автоматическая настройка VPS с Nginx, SSL, Cockpit, Docker и Marzban
# Обновленная версия с поддержкой кастомного контейнера Marzban
#===============================================================================

set -euo pipefail
IFS=$'\n\t'

# Константы и конфигурация
readonly SCRIPT_VERSION="3.1"
readonly LOGFILE="/var/log/vps-setup.log"
readonly LOCKFILE="/tmp/vps-setup.lock"
readonly NGINX_CONF_DIR="/etc/nginx"
readonly SSL_CHALLENGE_DIR="/var/www"
readonly SERVICES_CHECK_SCRIPT="/root/check-services.sh"
readonly BACKUP_DIR="/root/config-backup"
readonly MARZBAN_DIR="/opt/marzban-deployment"

# Настройки retry и таймаутов
readonly MAX_RETRIES=3
readonly BASE_DELAY=2
readonly CERTBOT_TIMEOUT=300

# Цвета для логов (только если TTY)
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly NC=''
fi

#===============================================================================
# Функции логирования и обработки ошибок
#===============================================================================

# Настройка логирования
setup_logging() {
    exec 1> >(tee -a "$LOGFILE")
    exec 2>&1
    log "INFO" "=== VPS Setup Started (v${SCRIPT_VERSION}) ==="
}

# Унифицированное логирование
log() {
    local level="$1"
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        "INFO")  echo -e "${GREEN}[${timestamp}] [INFO]  $*${NC}" ;;
        "WARN")  echo -e "${YELLOW}[${timestamp}] [WARN]  $*${NC}" ;;
        "ERROR") echo -e "${RED}[${timestamp}] [ERROR] $*${NC}" ;;
        "DEBUG") echo -e "${BLUE}[${timestamp}] [DEBUG] $*${NC}" ;;
    esac
}

# Обработка ошибок с контекстом
error_exit() {
    local line_no=${1:-$LINENO}
    local exit_code=${2:-1}
    log "ERROR" "Script failed at line $line_no with exit code $exit_code"
    cleanup
    exit "$exit_code"
}

# Функция очистки
cleanup() {
    log "INFO" "Performing cleanup..."
    [[ -f "$LOCKFILE" ]] && rm -f "$LOCKFILE"
    # Очистка временных SSH ключей если есть
    find /tmp -name "id_rsa*" -type f -delete 2>/dev/null || true
}

# Trap для обработки ошибок
trap 'error_exit $LINENO $?' ERR
trap 'cleanup' EXIT

#===============================================================================
# Проверки и валидация
#===============================================================================

# Проверка lock файла для предотвращения одновременного запуска
check_lock() {
    if [[ -f "$LOCKFILE" ]]; then
        local pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log "ERROR" "Another instance is already running (PID: $pid)"
            exit 1
        fi
        rm -f "$LOCKFILE"
    fi
    echo $$ > "$LOCKFILE"
}

# Проверка root привилегий
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
}

# Валидация переменных окружения
validate_environment() {
    local required_vars=(
        "DOMAIN_NAME"
        "ADMIN_EMAIL"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log "ERROR" "Missing required environment variables: ${missing_vars[*]}"
        log "INFO" "Required variables:"
        log "INFO" "  DOMAIN_NAME         - Your domain name"
        log "INFO" "  ADMIN_EMAIL         - Admin email for SSL"
        log "INFO" "Optional variables:"
        log "INFO" "  COCKPIT_PASSWORD    - Cockpit admin password"
        log "INFO" "  VPS_IP              - VPS IP for logging"
        log "INFO" "  DEPLOY_MARZBAN      - Deploy Marzban (true/false)"
        log "INFO" "  MARZBAN_PANEL_PORT  - Marzban panel port (default: 8000)"
        log "INFO" "  XRAY_PORT           - Xray VLESS port (default: 2083)"
        exit 1
    fi
    
    # Валидация email
    if [[ ! "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log "ERROR" "Invalid email format: $ADMIN_EMAIL"
        exit 1
    fi
    
    # Валидация домена
    if [[ ! "$DOMAIN_NAME" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        log "ERROR" "Invalid domain format: $DOMAIN_NAME"
        exit 1
    fi
    
    log "INFO" "Environment validation passed"
    log "INFO" "Domain: $DOMAIN_NAME"
    log "INFO" "Email: $ADMIN_EMAIL"
    log "INFO" "VPS IP: ${VPS_IP:-auto-detect}"
    
    if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
        log "INFO" "Marzban deployment: ENABLED"
        log "INFO" "Marzban panel port: ${MARZBAN_PANEL_PORT:-8000}"
        log "INFO" "Xray port: ${XRAY_PORT:-2083}"
    else
        log "INFO" "Marzban deployment: DISABLED"
    fi
}

# Проверка системных требований
check_prerequisites() {
    log "INFO" "Checking system prerequisites..."
    
    # Проверка Ubuntu версии
    if [[ ! -f /etc/lsb-release ]] || ! grep -q "Ubuntu" /etc/lsb-release; then
        log "WARN" "This script is optimized for Ubuntu, proceed with caution"
    fi
    
    # Проверка свободного места (минимум 3GB для Marzban)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local min_space=$((3 * 1024 * 1024)) # 3GB в KB
    
    if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
        min_space=$((4 * 1024 * 1024)) # 4GB для Marzban
    fi
    
    if [[ $available_space -lt $min_space ]]; then
        log "ERROR" "Insufficient disk space. Required: $((min_space/1024/1024))GB, Available: $(($available_space/1024/1024))GB"
        exit 1
    fi
    
    # Проверка памяти (минимум 1GB для Marzban)
    local available_memory=$(free | awk 'NR==2 {print $7}')
    local min_memory=$((512 * 1024)) # 512MB в KB
    
    if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
        min_memory=$((1024 * 1024)) # 1GB для Marzban
    fi
    
    if [[ $available_memory -lt $min_memory ]]; then
        log "WARN" "Low available memory: $(($available_memory/1024))MB, consider adding swap"
        if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
            setup_swap
        fi
    fi
    
    log "INFO" "Prerequisites check completed"
}

# Настройка swap файла
setup_swap() {
    log "INFO" "Setting up swap file for better performance..."
    
    # Проверка существующего swap
    if swapon --show | grep -q '/swapfile'; then
        log "INFO" "Swap file already exists"
        return 0
    fi
    
    # Создание swap файла 2GB
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    # Добавление в fstab для автоматического монтирования
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    
    # Настройка swappiness
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
    sysctl vm.swappiness=10
    
    log "INFO" "Swap file configured successfully"
}

#===============================================================================
# Функции установки (базовые компоненты)
#===============================================================================

# Retry функция с экспоненциальным backoff
retry_with_backoff() {
    local max_attempts="$1"
    shift
    local attempt=1
    local delay="$BASE_DELAY"
    
    while [[ $attempt -le $max_attempts ]]; do
        log "DEBUG" "Attempt $attempt/$max_attempts: $*"
        
        if "$@"; then
            log "DEBUG" "Command succeeded on attempt $attempt"
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log "WARN" "Command failed, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))
        fi
        
        ((attempt++))
    done
    
    log "ERROR" "Command failed after $max_attempts attempts: $*"
    return 1
}

# Обновление системы
update_system() {
    log "INFO" "Updating system packages..."
    
    # Настройка apt для ускорения
    cat > /etc/apt/apt.conf.d/99custom <<EOF
APT::Acquire::Retries "3";
APT::Acquire::http::Timeout "30";
APT::Get::Assume-Yes "true";
Dpkg::Options {
    "--force-confdef";
    "--force-confold";
}
EOF
    
    # Обновление с retry
    retry_with_backoff "$MAX_RETRIES" apt update
    
    # Установка базовых пакетов
    local base_packages=(
        "curl" "wget" "ufw" "git" "snapd" 
        "software-properties-common" "nginx" 
        "dnsutils" "htop" "fail2ban"
        "unattended-upgrades" "apt-listchanges"
        "make" "jq"  # Для Marzban Makefile
    )
    
    retry_with_backoff "$MAX_RETRIES" apt install -y "${base_packages[@]}"
    
    log "INFO" "System packages updated successfully"
}

# Установка Docker
install_docker() {
    log "INFO" "Installing Docker..."
    
    # Проверка существующей установки
    if command -v docker &>/dev/null; then
        local current_version=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        log "INFO" "Docker already installed (version: $current_version)"
        
        # Проверка работоспособности
        if docker info &>/dev/null; then
            log "INFO" "Docker is working correctly"
            install_docker_compose
            return 0
        else
            log "WARN" "Docker installation appears corrupted, reinstalling..."
        fi
    fi
    
    # Установка Docker через официальный скрипт
    retry_with_backoff "$MAX_RETRIES" bash -c "
        curl -fsSL https://get.docker.com -o get-docker.sh &&
        sh get-docker.sh &&
        rm -f get-docker.sh
    "
    
    # Установка Docker Compose
    install_docker_compose
    
    # Настройка Docker daemon
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2"
}
EOF
    
    # Запуск Docker
    systemctl enable --now docker
    
    # Проверка установки
    docker --version || error_exit $LINENO 1
    docker-compose --version || error_exit $LINENO 1
    
    log "INFO" "Docker installed successfully"
}

install_docker_compose() {
    log "INFO" "Installing Docker Compose..."
    
    # Получение последней версии
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
    
    if [[ -z "$latest_version" ]]; then
        log "WARN" "Could not get latest Docker Compose version, using fallback"
        latest_version="v2.24.0"
    fi
    
    # Скачивание и установка
    local compose_url="https://github.com/docker/compose/releases/download/${latest_version}/docker-compose-$(uname -s)-$(uname -m)"
    
    retry_with_backoff "$MAX_RETRIES" bash -c "
        curl -L '$compose_url' -o /usr/local/bin/docker-compose &&
        chmod +x /usr/local/bin/docker-compose
    "
    
    log "INFO" "Docker Compose installed: $latest_version"
}

# Конфигурация UFW с портами для Marzban
setup_firewall() {
    log "INFO" "Configuring UFW firewall..."
    
    # Сброс UFW к дефолтным настройкам
    ufw --force reset
    
    # Базовые политики
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH с ограничениями
    ufw limit ssh comment "SSH with rate limiting"
    
    # HTTP/HTTPS
    ufw allow 80/tcp comment "HTTP"
    ufw allow 443/tcp comment "HTTPS"
    
    # Cockpit (можно ограничить по IP в production)
    ufw allow 9090/tcp comment "Cockpit Web Interface"
    
    # Marzban порты если включен
    if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
        local marzban_port="${MARZBAN_PANEL_PORT:-8000}"
        local xray_port="${XRAY_PORT:-2083}"
        
        ufw allow "$marzban_port"/tcp comment "Marzban Panel"
        ufw allow "$xray_port"/tcp comment "Xray VLESS"
        
        log "INFO" "Opened Marzban ports: $marzban_port, $xray_port"
    fi
    
    # Включение UFW
    ufw --force enable
    
    log "INFO" "UFW firewall configured successfully"
}

# Минимальный deploy_marzban - заглушка для обратной совместимости
deploy_marzban() {
    if [[ "${DEPLOY_MARZBAN:-false}" != "true" ]]; then
        log "INFO" "Marzban deployment skipped (DEPLOY_MARZBAN not set to true)"
        return 0
    fi
    
    log "INFO" "Starting Marzban deployment..."
    
    local repo_url="https://github.com/KomarovAI/vps-nginx-certbot-cockpit-setup.git"
    
    # Создание директории для развертывания
    mkdir -p "$MARZBAN_DIR"
    cd "$MARZBAN_DIR"
    
    # Клонирование репозитория с main ветки
    if [[ -d ".git" ]]; then
        log "INFO" "Project already cloned, updating..."
        git pull origin main
    else
        retry_with_backoff "$MAX_RETRIES" git clone -b main "$repo_url" .
    fi
    
    log "INFO" "Project cloned successfully to $MARZBAN_DIR"
    
    # Переход в директорию Marzban
    if [[ -d "marzban" ]]; then
        cd "$MARZBAN_DIR/marzban"
        
        # Настройка environment файла
        cp .env.example .env 2>/dev/null || true
        
        # Настройка переменных
        cat > .env <<EOF
# Marzban Custom Container Configuration

# Domain configuration
DOMAIN_NAME=${DOMAIN_NAME}

# Marzban panel configuration
MARZBAN_PANEL_PORT=${MARZBAN_PANEL_PORT:-8000}

# Xray configuration
XRAY_PORT=${XRAY_PORT:-2083}

# Reality configuration (auto-generated if not provided)
XRAY_REALITY_SERVER_NAMES=google.com,www.google.com

# Additional Marzban settings
MARZBAN_QUIC=true
MARZBAN_DB_URL=sqlite:////var/lib/marzban/marzban.db

# Protocol settings
XRAY_VLESS_REALITY=true
XRAY_GRPC_ENABLE=true
EOF
        
        # Использование Makefile если есть
        if [[ -f "Makefile" ]]; then
            make build && make up
            log "INFO" "Marzban started using Makefile"
        else
            # Fallback к docker-compose
            if [[ -f "docker-compose.yml" ]]; then
                docker-compose up -d
                log "INFO" "Marzban started using docker-compose"
            fi
        fi
        
        # Создание скрипта управления
        cat > /root/marzban-manage.sh <<'EOFSCRIPT'
#!/bin/bash

MARZBAN_DIR="/opt/marzban-deployment/marzban"

cd "$MARZBAN_DIR" || { echo "Error: Cannot access Marzban directory"; exit 1; }

case "$1" in
    "start")
        echo "Starting Marzban..."
        [[ -f "Makefile" ]] && make up || docker-compose up -d
        ;;
    "stop")
        echo "Stopping Marzban..."
        [[ -f "Makefile" ]] && make down || docker-compose down
        ;;
    "restart")
        echo "Restarting Marzban..."
        [[ -f "Makefile" ]] && make restart || (docker-compose down && docker-compose up -d)
        ;;
    "logs")
        echo "Showing Marzban logs..."
        [[ -f "Makefile" ]] && make logs || docker-compose logs -f
        ;;
    "status"|"health")
        echo "Checking Marzban health..."
        docker-compose ps
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|status}"
        exit 1
        ;;
esac
EOFSCRIPT
        
        chmod +x /root/marzban-manage.sh
        log "INFO" "Marzban management script created: /root/marzban-manage.sh"
        
        log "INFO" "Marzban deployment completed successfully"
    else
        log "WARN" "Marzban directory not found in repository"
    fi
}

# Остальные базовые функции (сокращено для бревити)
setup_nginx() {
    log "INFO" "Configuring Nginx..."
    local domain="$DOMAIN_NAME"
    local webroot="/var/www/$domain"
    
    mkdir -p "$webroot"
    chown www-data:www-data "$webroot"
    
    # Базовая страница
    cat > "$webroot/index.html" <<EOF
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Добро пожаловать на $domain</title></head>
<body><h1>🚀 VPS Server Ready</h1><p>Сервер $domain успешно настроен!</p></body></html>
EOF
    
    rm -f "/etc/nginx/sites-enabled/default"
    
    # HTTP конфигурация
    cat > "/etc/nginx/sites-available/$domain" <<EOF
server {
    listen 80;
    server_name $domain;
    root $webroot;
    index index.html;
    
    location /.well-known/acme-challenge/ {
        root $webroot;
        allow all;
    }
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    
    ln -sf "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
    nginx -t && systemctl reload nginx
    log "INFO" "Nginx configured successfully"
}

setup_ssl() {
    log "INFO" "Setting up SSL certificates..."
    local domain="$DOMAIN_NAME"
    local email="$ADMIN_EMAIL"
    
    # Установка Certbot
    snap install core && snap refresh core
    snap install --classic certbot
    ln -sf /snap/bin/certbot /usr/bin/certbot
    
    # Получение сертификата
    certbot certonly --webroot --webroot-path "/var/www/$domain" --domain "$domain" --email "$email" --agree-tos --no-eff-email --non-interactive
    
    # HTTPS конфигурация
    cat > "/etc/nginx/sites-available/$domain" <<EOF
server {
    listen 80;
    server_name $domain;
    location /.well-known/acme-challenge/ { root /var/www/$domain; allow all; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl http2;
    server_name $domain;
    root /var/www/$domain;
    index index.html;
    
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    location / { try_files \$uri \$uri/ =404; }
}
EOF
    
    nginx -t && systemctl reload nginx
    log "INFO" "SSL configured successfully"
}

setup_fail2ban() {
    log "INFO" "Configuring fail2ban..."
    systemctl enable --now fail2ban
    log "INFO" "fail2ban configured"
}

setup_cockpit() {
    log "INFO" "Installing Cockpit..."
    apt install -y cockpit cockpit-machines cockpit-podman
    
    local cockpit_user="${COCKPIT_USER:-cockpit-admin}"
    if ! id "$cockpit_user" &>/dev/null; then
        useradd -m -s /bin/bash -G sudo "$cockpit_user"
        log "INFO" "User $cockpit_user created"
    fi
    
    if [[ -n "${COCKPIT_PASSWORD:-}" ]]; then
        echo "$cockpit_user:$COCKPIT_PASSWORD" | chpasswd
        log "INFO" "Password set for $cockpit_user"
    fi
    
    systemctl enable --now cockpit.socket
    log "INFO" "Cockpit configured successfully"
}

create_monitoring_scripts() {
    log "INFO" "Creating monitoring scripts..."
    
    cat > "$SERVICES_CHECK_SCRIPT" <<'EOF'
#!/bin/bash
echo "=== VPS Services Status Check ==="
echo "Time: $(date)"
echo

for service in nginx cockpit docker fail2ban; do
    if systemctl is-active --quiet $service; then
        echo "$service: ✓ Running"
    else
        echo "$service: ✗ Stopped"
    fi
done

if [[ -d "/opt/marzban-deployment/marzban" ]]; then
    cd /opt/marzban-deployment/marzban
    if docker-compose ps | grep -q "Up"; then
        echo "Marzban: ✓ Running"
    else
        echo "Marzban: ✗ Stopped"
    fi
fi

echo
echo "=== SSL Certificates ==="
certbot certificates 2>/dev/null | grep -E "(Certificate Name|Expiry Date)" || echo "No certificates"
EOF
    
    chmod +x "$SERVICES_CHECK_SCRIPT"
    log "INFO" "Monitoring scripts created"
}

#===============================================================================
# Главная функция
#===============================================================================

main() {
    # Инициализация
    setup_logging
    check_lock
    check_root
    validate_environment
    check_prerequisites
    
    log "INFO" "Starting VPS setup for domain: $DOMAIN_NAME"
    
    # Основные этапы установки
    update_system
    setup_firewall
    setup_fail2ban
    install_docker
    setup_nginx
    setup_ssl
    setup_cockpit
    
    # Развертывание Marzban если включено
    deploy_marzban
    
    # Создание скриптов мониторинга
    create_monitoring_scripts
    
    # Финальная проверка
    log "INFO" "Running final system check..."
    [[ -x "$SERVICES_CHECK_SCRIPT" ]] && "$SERVICES_CHECK_SCRIPT"
    
    # Создание финального отчета
    log "INFO" "=== VPS Setup Completed Successfully ==="
    log "INFO" "🌐 Website: https://$DOMAIN_NAME"
    log "INFO" "🖥️  Cockpit: https://$DOMAIN_NAME:9090"
    
    if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
        log "INFO" "🔒 Marzban Panel: https://$DOMAIN_NAME:${MARZBAN_PANEL_PORT:-8000}"
        log "INFO" "⚙️  Marzban Management: /root/marzban-manage.sh"
    fi
    
    log "INFO" "📊 Service Check: $SERVICES_CHECK_SCRIPT"
    log "INFO" "Setup completed at $(date)"
}

# Установка переменных из аргументов
DOMAIN_NAME="${DOMAIN_NAME:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
VPS_IP="${VPS_IP:-}"
COCKPIT_PASSWORD="${COCKPIT_PASSWORD:-}"
COCKPIT_USER="${COCKPIT_USER:-cockpit-admin}"
DEPLOY_MARZBAN="${DEPLOY_MARZBAN:-false}"
MARZBAN_PANEL_PORT="${MARZBAN_PANEL_PORT:-8000}"
XRAY_PORT="${XRAY_PORT:-2083}"

# Запуск основной функции
main "$@"