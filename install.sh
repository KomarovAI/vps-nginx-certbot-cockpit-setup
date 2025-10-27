#!/bin/bash

#===============================================================================
# VPS Setup Script v3.2 - Production Ready with Full Idempotency
# Автоматическая настройка VPS с Nginx, SSL, Cockpit, Docker и Marzban
# Полностью идемпотентная версия с улучшенной обработкой повторных запусков
#===============================================================================

set -euo pipefail
IFS=$'\n\t'

# Константы и конфигурация
readonly SCRIPT_VERSION="3.2"
readonly LOGFILE="/var/log/vps-setup.log"
readonly LOCKFILE="/tmp/vps-setup.lock"
readonly NGINX_CONF_DIR="/etc/nginx"
readonly SSL_CHALLENGE_DIR="/var/www"
readonly SERVICES_CHECK_SCRIPT="/root/check-services.sh"
readonly BACKUP_DIR="/root/config-backup"
readonly MARZBAN_DIR="/opt/marzban-deployment"
readonly STATE_FILE="/var/lib/vps-setup-state"

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
# Функции состояния и идемпотентности
#===============================================================================

# Сохранение состояния компонента
save_component_state() {
    local component="$1"
    local status="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "${component}=${status}:${timestamp}" >> "$STATE_FILE"
    log "DEBUG" "Saved state: $component = $status"
}

# Проверка состояния компонента
get_component_state() {
    local component="$1"
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${component}=" "$STATE_FILE" | tail -1 | cut -d'=' -f2 | cut -d':' -f1
    fi
}

# Проверка готовности компонента
is_component_ready() {
    local component="$1"
    [[ "$(get_component_state "$component")" == "completed" ]]
}

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
    find /tmp -name "*_key" -type f -delete 2>/dev/null || true
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
    if is_component_ready "prerequisites"; then
        log "INFO" "Prerequisites already checked, skipping..."
        return 0
    fi
    
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
    
    save_component_state "prerequisites" "completed"
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
    if ! grep -q 'vm.swappiness=10' /etc/sysctl.conf; then
        echo 'vm.swappiness=10' >> /etc/sysctl.conf
        sysctl vm.swappiness=10
    fi
    
    log "INFO" "Swap file configured successfully"
}

#===============================================================================
# Функции установки с идемпотентностью
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
    if is_component_ready "system_update"; then
        log "INFO" "System already updated, skipping..."
        return 0
    fi
    
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
    
    save_component_state "system_update" "completed"
    log "INFO" "System packages updated successfully"
}

# Настройка автоматических обновлений
setup_auto_updates() {
    if is_component_ready "auto_updates"; then
        log "INFO" "Auto-updates already configured, skipping..."
        return 0
    fi
    
    log "INFO" "Configuring automatic security updates..."
    
    # Конфигурация unattended-upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    # Включение автоматических обновлений
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
    
    systemctl enable --now unattended-upgrades
    save_component_state "auto_updates" "completed"
    log "INFO" "Automatic security updates enabled"
}

# Установка Docker
install_docker() {
    if is_component_ready "docker"; then
        log "INFO" "Docker already installed and configured, skipping..."
        return 0
    fi
    
    log "INFO" "Installing Docker..."
    
    # Проверка существующей установки
    if command -v docker &>/dev/null && command -v docker-compose &>/dev/null; then
        local docker_version=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        local compose_version=$(docker-compose --version | grep -oP '\d+\.\d+\.\d+' | head -1)
        
        if docker info &>/dev/null; then
            log "INFO" "Docker $docker_version and Docker Compose $compose_version already working"
            save_component_state "docker" "completed"
            return 0
        else
            log "WARN" "Docker installed but not working, will fix..."
        fi
    fi
    
    # Установка Docker через official script
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
    
    save_component_state "docker" "completed"
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
    if is_component_ready "firewall"; then
        log "INFO" "Firewall already configured, checking rules..."
        
        # Проверяем и добавляем недостающие правила
        if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
            local marzban_port="${MARZBAN_PANEL_PORT:-8000}"
            local xray_port="${XRAY_PORT:-2083}"
            
            if ! ufw status | grep -q "$xray_port"; then
                log "INFO" "Adding missing Marzban ports..."
                ufw allow "$marzban_port"/tcp comment "Marzban Panel"
                ufw allow "$xray_port"/tcp comment "Xray VLESS TCP"
                ufw allow "$xray_port"/udp comment "Xray VLESS UDP"
            fi
        fi
        return 0
    fi
    
    log "INFO" "Configuring UFW firewall..."
    
    # Проверка активности UFW
    if ! ufw status | grep -q "Status: active"; then
        log "INFO" "UFW is inactive, configuring from scratch..."
        ufw default deny incoming
        ufw default allow outgoing
        ufw --force enable
    else
        log "INFO" "UFW already active, updating rules..."
    fi
    
    # Убеждаемся что SSH разрешен (критично!)
    if ! ufw status | grep -q "22"; then
        ufw limit ssh comment "SSH with rate limiting"
    fi
    
    # Добавляем правила только если их нет
    for port_rule in "80/tcp:HTTP" "443/tcp:HTTPS" "9090/tcp:Cockpit"; do
        port_num=$(echo $port_rule | cut -d: -f1)
        description=$(echo $port_rule | cut -d: -f2)
        
        if ! ufw status | grep -q "$port_num"; then
            ufw allow $port_num comment "$description"
        fi
    done
    
    # Marzban порты если включен
    if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
        local marzban_port="${MARZBAN_PANEL_PORT:-8000}"
        local xray_port="${XRAY_PORT:-2083}"
        
        if ! ufw status | grep -q "$marzban_port"; then
            ufw allow "$marzban_port"/tcp comment "Marzban Panel"
        fi
        
        if ! ufw status | grep -q "$xray_port"; then
            ufw allow "$xray_port"/tcp comment "Xray VLESS TCP"
            ufw allow "$xray_port"/udp comment "Xray VLESS UDP"
        fi
        
        log "INFO" "Marzban ports configured: $marzban_port, $xray_port (TCP/UDP)"
    fi
    
    save_component_state "firewall" "completed"
    log "INFO" "UFW firewall configured successfully"
}

# Настройка fail2ban
setup_fail2ban() {
    if is_component_ready "fail2ban"; then
        log "INFO" "Fail2ban already configured, skipping..."
        return 0
    fi
    
    log "INFO" "Configuring fail2ban..."
    
    # Проверка существующей конфигурации
    if systemctl is-active --quiet fail2ban; then
        log "INFO" "Fail2ban already running, updating configuration..."
    fi
    
    # Бэкап существующей конфигурации
    if [[ -f /etc/fail2ban/jail.local ]]; then
        cp /etc/fail2ban/jail.local "/etc/fail2ban/jail.local.backup.$(date +%s)"
    fi
    
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true

[nginx-http-auth]
enabled = true

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /var/log/nginx/error.log

[cockpit]
enabled = true
port = 9090
filter = cockpit
logpath = /var/log/auth.log
maxretry = 3
EOF
    
    # Фильтр для Cockpit
    cat > /etc/fail2ban/filter.d/cockpit.conf <<EOF
[Definition]
failregex = pam_authenticate: authentication failure.*rhost=<HOST>
            pam_authenticate: authentication error.*rhost=<HOST>
ignoreregex =
EOF
    
    # Мягкий перезапуск
    if systemctl is-active --quiet fail2ban; then
        systemctl reload fail2ban || systemctl restart fail2ban
    else
        systemctl enable --now fail2ban
    fi
    
    save_component_state "fail2ban" "completed"
    log "INFO" "fail2ban configured successfully"
}

# Настройка Nginx с проксированием для Marzban
setup_nginx() {
    if is_component_ready "nginx"; then
        log "INFO" "Nginx already configured, checking for updates..."
        
        local domain="$DOMAIN_NAME"
        
        # Проверяем если конфигурация устарела
        if ! grep -q "ssl_certificate" "$NGINX_CONF_DIR/sites-available/$domain" 2>/dev/null; then
            log "INFO" "HTTP-only config detected, will upgrade to HTTPS later"
        else
            log "INFO" "HTTPS config already exists"
        fi
        return 0
    fi
    
    log "INFO" "Configuring Nginx..."
    
    local domain="$DOMAIN_NAME"
    local webroot="/var/www/$domain"
    
    # Создание веб-директории
    mkdir -p "$webroot"
    chown www-data:www-data "$webroot"
    
    # Создание базовой страницы
    create_default_page "$webroot" "$domain"
    
    # Удаление дефолтного сайта
    rm -f "$NGINX_CONF_DIR/sites-enabled/default"
    
    # Создание начальной HTTP конфигурации
    create_nginx_http_config "$domain" "$webroot"
    
    # Тест конфигурации и перезагрузка
    nginx -t || error_exit $LINENO 1
    systemctl reload nginx
    
    save_component_state "nginx" "completed"
    log "INFO" "Nginx configured successfully for HTTP"
}

create_default_page() {
    local webroot="$1"
    local domain="$2"
    local current_time=$(date '+%B %d, %Y, %H:%M MSK')
    
    cat > "$webroot/index.html" <<EOF
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Добро пожаловать на $domain</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; color: #2c3e50; margin-bottom: 30px; }
        .status { background: #d4edda; padding: 15px; border-radius: 5px; color: #155724; margin: 20px 0; }
        .info { background: #d1ecf1; padding: 15px; border-radius: 5px; color: #0c5460; margin: 10px 0; }
        .footer { text-align: center; margin-top: 30px; color: #6c757d; font-size: 0.9em; }
        .service-link { display: inline-block; padding: 10px 20px; margin: 5px; background: #007bff; color: white; text-decoration: none; border-radius: 5px; }
        .service-link:hover { background: #0056b3; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 VPS Server Ready</h1>
            <h2>Добро пожаловать на $domain</h2>
        </div>
        
        <div class="status">
            ✅ <strong>Статус:</strong> Сервер успешно настроен и работает
        </div>
        
        <div class="info">
            <h3>📋 Доступные сервисы:</h3>
            <p>
                <a href="https://$domain" class="service-link">🌐 Главная</a>
                <a href="https://$domain:9090" class="service-link">🖥️ Cockpit</a>
EOF
    
    # Добавляем ссылку на Marzban если он включен
    if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
        local marzban_port="${MARZBAN_PANEL_PORT:-8000}"
        cat >> "$webroot/index.html" <<EOF
                <a href="https://$domain:$marzban_port" class="service-link">🔒 Marzban</a>
EOF
    fi
    
    cat >> "$webroot/index.html" <<EOF
            </p>
        </div>
        
        <div class="info">
            <h3>🔒 Безопасность:</h3>
            <ul>
                <li>SSL сертификат от Let's Encrypt</li>
                <li>Firewall (UFW) настроен</li>
                <li>Fail2ban активен</li>
                <li>Автоматические обновления безопасности включены</li>
EOF
    
    if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
        cat >> "$webroot/index.html" <<EOF
                <li>Marzban VPN сервер развернут</li>
EOF
    fi
    
    cat >> "$webroot/index.html" <<EOF
            </ul>
        </div>
        
        <div class="footer">
            Дата установки: $current_time<br>
            Powered by nginx + Docker + Cockpit
EOF
    
    if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
        cat >> "$webroot/index.html" <<EOF
 + Marzban
EOF
    fi
    
    cat >> "$webroot/index.html" <<EOF
        </div>
    </div>
</body>
</html>
EOF
}

create_nginx_http_config() {
    local domain="$1"
    local webroot="$2"
    
    cat > "$NGINX_CONF_DIR/sites-available/$domain" <<EOF
# HTTP Configuration for $domain (ACME Challenge)
server {
    listen 80;
    server_name $domain;
    root $webroot;
    index index.html index.htm;
    
    # ACME Challenge location
    location /.well-known/acme-challenge/ {
        root $webroot;
        allow all;
    }
    
    # Serve content normally before SSL setup
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Security headers (basic)
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    
    # Logging
    access_log /var/log/nginx/${domain}.access.log;
    error_log /var/log/nginx/${domain}.error.log;
}
EOF
    
    ln -sf "$NGINX_CONF_DIR/sites-available/$domain" "$NGINX_CONF_DIR/sites-enabled/$domain"
}

#===============================================================================
# Функции развертывания Marzban
#===============================================================================

# Клонирование проекта с GitHub
clone_project() {
    if [[ -d "$MARZBAN_DIR/.git" ]]; then
        log "INFO" "Project already cloned, updating..."
        cd "$MARZBAN_DIR"
        git fetch origin
        git reset --hard origin/feat/custom-marzban-container || git reset --hard origin/main
        return 0
    fi
    
    log "INFO" "Cloning VPS setup project..."
    
    local repo_url="https://github.com/KomarovAI/vps-nginx-certbot-cockpit-setup.git"
    local target_branch="feat/custom-marzban-container"
    
    # Создание директории для развертывания
    mkdir -p "$MARZBAN_DIR"
    cd "$MARZBAN_DIR"
    
    retry_with_backoff "$MAX_RETRIES" git clone -b "$target_branch" "$repo_url" .
    
    log "INFO" "Project cloned successfully to $MARZBAN_DIR"
}

# Развертывание Marzban
deploy_marzban() {
    if [[ "${DEPLOY_MARZBAN:-false}" != "true" ]]; then
        log "INFO" "Marzban deployment skipped (DEPLOY_MARZBAN not set to true)"
        return 0
    fi
    
    if is_component_ready "marzban" && [[ "${FORCE_REBUILD:-false}" != "true" ]]; then
        log "INFO" "Marzban already deployed, checking status..."
        
        cd "$MARZBAN_DIR/marzban"
        if docker-compose ps marzban | grep -q "Up"; then
            log "INFO" "Marzban is already running"
            # Обновляем только nginx интеграцию если нужно
            setup_marzban_nginx_integration
            return 0
        else
            log "INFO" "Marzban deployed but not running, starting..."
            make up
            setup_marzban_nginx_integration
            return 0
        fi
    fi
    
    log "INFO" "Starting Marzban deployment..."
    
    # Клонирование проекта
    clone_project
    
    # Переход в директорию Marzban
    cd "$MARZBAN_DIR/marzban"
    
    # Настройка environment файла
    setup_marzban_env
    
    # Сборка и запуск контейнера
    build_and_start_marzban
    
    # Интеграция с Nginx
    setup_marzban_nginx_integration
    
    save_component_state "marzban" "completed"
    log "INFO" "Marzban deployment completed successfully"
}

# Настройка .env файла для Marzban
setup_marzban_env() {
    log "INFO" "Setting up Marzban environment configuration..."
    
    # Копирование примера конфигурации если не существует
    [[ ! -f .env ]] && cp .env.example .env
    
    # Функция для установки переменной в .env
    set_env_var() {
        local key="$1"
        local value="$2"
        
        if [[ -n "$value" ]]; then
            if grep -q "^$key=" .env; then
                sed -i "s|^$key=.*|$key=$value|" .env
            else
                echo "$key=$value" >> .env
            fi
        fi
    }
    
    # Настройка переменных
    set_env_var "DOMAIN_NAME" "${DOMAIN_NAME}"
    set_env_var "MARZBAN_PANEL_PORT" "${MARZBAN_PANEL_PORT:-8000}"
    set_env_var "XRAY_PORT" "${XRAY_PORT:-2083}"
    set_env_var "XRAY_REALITY_SERVER_NAMES" "google.com,www.google.com"
    set_env_var "MARZBAN_QUIC" "true"
    set_env_var "MARZBAN_DB_URL" "sqlite:////var/lib/marzban/marzban.db"
    set_env_var "XRAY_VLESS_REALITY" "true"
    set_env_var "XRAY_GRPC_ENABLE" "true"
    
    log "INFO" "Marzban environment configured"
}

# Сборка и запуск Marzban контейнера
build_and_start_marzban() {
    log "INFO" "Building and starting Marzban container..."
    
    # Использование Makefile для управления
    make build
    make up
    
    # Ожидание готовности сервиса
    log "INFO" "Waiting for Marzban to start..."
    local max_wait=60
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        if make health &>/dev/null; then
            log "INFO" "Marzban is ready"
            break
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
        log "DEBUG" "Waiting for Marzban... (${wait_time}s)"
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        log "WARN" "Marzban health check timeout, but continuing..."
    fi
    
    # Вывод статуса
    make logs | tail -20
}

# Интеграция Marzban с Nginx (проксирование)
setup_marzban_nginx_integration() {
    local domain="$DOMAIN_NAME"
    local marzban_port="${MARZBAN_PANEL_PORT:-8000}"
    local marzban_subdomain="marzban.$domain"
    
    # Проверка существующей конфигурации
    if [[ -f "$NGINX_CONF_DIR/sites-enabled/marzban-$domain" ]]; then
        log "INFO" "Marzban Nginx integration already configured"
        return 0
    fi
    
    log "INFO" "Setting up Nginx integration for Marzban..."
    
    # Создание конфигурации для проксирования Marzban
    cat > "$NGINX_CONF_DIR/sites-available/marzban-$domain" <<EOF
# Marzban Proxy Configuration
upstream marzban_backend {
    server 127.0.0.1:$marzban_port;
    keepalive 32;
}

# Marzban subdomain (if SSL available)
server {
    listen 443 ssl http2;
    server_name $marzban_subdomain;
    
    # Use main domain SSL certificate
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    # Modern SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    
    # Proxy to Marzban
    location / {
        proxy_pass http://marzban_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Logging
    access_log /var/log/nginx/marzban-${domain}.access.log;
    error_log /var/log/nginx/marzban-${domain}.error.log;
}

# Direct port access (fallback)
server {
    listen $marzban_port ssl http2;
    server_name $domain;
    
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    # Basic SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    
    location / {
        proxy_pass http://marzban_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    
    # Включение конфигурации после получения SSL сертификатов
    log "INFO" "Marzban Nginx configuration created (will be enabled after SSL setup)"
}

#===============================================================================
# SSL с поддержкой Marzban субдомена
#===============================================================================

# Обновленная настройка SSL с поддержкой Marzban
setup_ssl() {
    if is_component_ready "ssl"; then
        log "INFO" "SSL already configured, checking certificates..."
        
        local domain="$DOMAIN_NAME"
        
        # Проверка существующих сертификатов
        if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
            local expiry_date=$(openssl x509 -in "/etc/letsencrypt/live/$domain/fullchain.pem" -noout -dates | grep notAfter | cut -d= -f2)
            local expiry_timestamp=$(date -d "$expiry_date" +%s)
            local current_timestamp=$(date +%s)
            local days_left=$(( (expiry_timestamp - current_timestamp) / 86400 ))
            
            if [[ $days_left -gt 30 ]]; then
                log "INFO" "SSL certificate valid for $days_left days"
                create_nginx_https_config "$domain"  # Обновляем nginx конфиг
                
                # Обработка Marzban SSL если нужно
                if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
                    setup_marzban_ssl "$domain" "$ADMIN_EMAIL"
                fi
                
                setup_ssl_renewal
                return 0
            else
                log "WARN" "SSL certificate expires in $days_left days, will renew"
            fi
        fi
    fi
    
    log "INFO" "Setting up SSL certificates..."
    
    local domain="$DOMAIN_NAME"
    local email="$ADMIN_EMAIL"
    
    # Установка Certbot
    install_certbot
    
    # Проверка DNS перед получением сертификата
    verify_dns "$domain"
    
    # Получение основного SSL сертификата
    obtain_ssl_certificate "$domain" "$email"
    
    # Обновление Nginx конфигурации для HTTPS
    create_nginx_https_config "$domain"
    
    # Получение сертификата для Marzban поддомена если нужно
    if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
        setup_marzban_ssl "$domain" "$email"
    fi
    
    # Настройка автообновления сертификатов
    setup_ssl_renewal
    
    save_component_state "ssl" "completed"
    log "INFO" "SSL certificates configured successfully"
}

# Настройка SSL для Marzban
setup_marzban_ssl() {
    local domain="$1"
    local email="$2"
    local marzban_subdomain="marzban.$domain"
    local webroot="/var/www/$domain"
    
    log "INFO" "Setting up SSL for Marzban subdomain: $marzban_subdomain"
    
    # ПРОВЕРКА DNS ДЛЯ ПОДДОМЕНА
    local resolved_ip
    resolved_ip=$(dig +short "$marzban_subdomain" @8.8.8.8 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    
    if [[ -z "$resolved_ip" ]]; then
        log "WARN" "Subdomain $marzban_subdomain does not resolve, skipping separate SSL"
        # Используем основной сертификат
        ln -sf "$NGINX_CONF_DIR/sites-available/marzban-$domain" "$NGINX_CONF_DIR/sites-enabled/marzban-$domain"
        if nginx -t; then
            systemctl reload nginx
        fi
        return 0
    fi
    
    # Проверяем что поддомен указывает на тот же сервер
    local server_ip="${VPS_IP:-$(curl -s ifconfig.me 2>/dev/null || echo 'unknown')}"
    if [[ "$resolved_ip" != "$server_ip" && "$server_ip" != "unknown" ]]; then
        log "WARN" "Subdomain $marzban_subdomain resolves to $resolved_ip but server IP is $server_ip"
        log "WARN" "Using main domain certificate instead"
        ln -sf "$NGINX_CONF_DIR/sites-available/marzban-$domain" "$NGINX_CONF_DIR/sites-enabled/marzban-$domain"
        if nginx -t; then
            systemctl reload nginx
        fi
        return 0
    fi
    
    # Попытка получить сертификат для поддомена
    if certbot certonly \
        --webroot \
        --webroot-path "$webroot" \
        --domain "$marzban_subdomain" \
        --email "$email" \
        --agree-tos \
        --no-eff-email \
        --non-interactive; then
        
        log "INFO" "SSL certificate obtained for Marzban subdomain"
        
        # Обновляем конфигурацию Nginx для использования собственного сертификата
        sed -i "s|/etc/letsencrypt/live/$domain/|/etc/letsencrypt/live/$marzban_subdomain/|g" \
            "$NGINX_CONF_DIR/sites-available/marzban-$domain"
            
        # Включаем конфигурацию Marzban
        ln -sf "$NGINX_CONF_DIR/sites-available/marzban-$domain" "$NGINX_CONF_DIR/sites-enabled/marzban-$domain"
        
        # Тест и перезагрузка
        if nginx -t; then
            systemctl reload nginx
            log "INFO" "Marzban SSL integration completed"
        else
            log "WARN" "Nginx configuration error for Marzban SSL"
        fi
    else
        log "WARN" "Could not obtain SSL certificate for Marzban subdomain, using main domain certificate"
        
        # Включаем конфигурацию с основным сертификатом
        ln -sf "$NGINX_CONF_DIR/sites-available/marzban-$domain" "$NGINX_CONF_DIR/sites-enabled/marzban-$domain"
        
        if nginx -t; then
            systemctl reload nginx
        fi
    fi
}

# Остальные функции SSL остаются прежними...
install_certbot() {
    if command -v certbot &>/dev/null; then
        log "INFO" "Certbot already installed"
        return 0
    fi
    
    log "INFO" "Installing Certbot..."
    
    snap install core
    snap refresh core
    retry_with_backoff "$MAX_RETRIES" snap install --classic certbot
    
    ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
    
    log "INFO" "Certbot installed successfully"
}

verify_dns() {
    local domain="$1"
    local server_ip="${VPS_IP:-$(curl -s ifconfig.me 2>/dev/null || echo 'unknown')}"
    
    log "INFO" "Verifying DNS configuration for $domain..."
    
    local resolved_ip
    resolved_ip=$(dig +short "$domain" @8.8.8.8 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    
    if [[ -z "$resolved_ip" ]]; then
        log "ERROR" "Domain $domain does not resolve to any IP address"
        log "INFO" "Please ensure your domain's A record points to: $server_ip"
        exit 1
    fi
    
    if [[ "$resolved_ip" != "$server_ip" && "$server_ip" != "unknown" ]]; then
        log "WARN" "DNS mismatch: $domain resolves to $resolved_ip, but server IP is $server_ip"
        log "WARN" "Continuing anyway, but SSL certificate request may fail"
    else
        log "INFO" "DNS verification passed: $domain -> $resolved_ip"
    fi
}

obtain_ssl_certificate() {
    local domain="$1"
    local email="$2"
    local webroot="/var/www/$domain"
    
    log "INFO" "Obtaining SSL certificate for $domain..."
    
    get_certificate() {
        timeout "$CERTBOT_TIMEOUT" certbot certonly \
            --webroot \
            --webroot-path "$webroot" \
            --domain "$domain" \
            --email "$email" \
            --agree-tos \
            --no-eff-email \
            --non-interactive \
            --verbose
    }
    
    if retry_with_backoff "$MAX_RETRIES" get_certificate; then
        log "INFO" "SSL certificate obtained successfully"
        
        local cert_files=(
            "/etc/letsencrypt/live/$domain/fullchain.pem"
            "/etc/letsencrypt/live/$domain/privkey.pem"
        )
        
        for cert_file in "${cert_files[@]}"; do
            if [[ ! -f "$cert_file" ]]; then
                log "ERROR" "Certificate file not found: $cert_file"
                exit 1
            fi
        done
        
        log "INFO" "Certificate files verified"
    else
        log "ERROR" "Failed to obtain SSL certificate after $MAX_RETRIES attempts"
        exit 1
    fi
}

create_nginx_https_config() {
    local domain="$1"
    
    log "INFO" "Creating HTTPS Nginx configuration..."
    
    [[ -f "$NGINX_CONF_DIR/sites-available/$domain" ]] && \
        cp "$NGINX_CONF_DIR/sites-available/$domain" "$BACKUP_DIR/nginx-$domain-$(date +%s).conf"
    
    cat > "$NGINX_CONF_DIR/sites-available/$domain" <<EOF
# HTTPS Configuration for $domain
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name $domain;
    
    # ACME Challenge (for renewals)
    location /.well-known/acme-challenge/ {
        root /var/www/$domain;
        allow all;
    }
    
    # Redirect everything else to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS Server Block
server {
    listen 443 ssl http2;
    server_name $domain;
    
    root /var/www/$domain;
    index index.html index.htm;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    # Modern SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # OCSP Stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/letsencrypt/live/$domain/chain.pem;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self';" always;
    
    # Rate Limiting
    limit_req_zone \$binary_remote_addr zone=main:10m rate=10r/s;
    limit_req zone=main burst=20 nodelay;
    
    # Main location
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Security: Hide nginx version
    server_tokens off;
    
    # Logging
    access_log /var/log/nginx/${domain}.access.log;
    error_log /var/log/nginx/${domain}.error.log;
}
EOF
    
    nginx -t || error_exit $LINENO 1
    systemctl reload nginx
    
    log "INFO" "HTTPS configuration applied successfully"
}

setup_ssl_renewal() {
    log "INFO" "Setting up SSL certificate auto-renewal..."
    
    mkdir -p /etc/letsencrypt/renewal-hooks/post
    cat > /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh <<'EOF'
#!/bin/bash
# Перезагрузка nginx после обновления сертификатов
systemctl reload nginx
logger "SSL certificates renewed and nginx reloaded"
EOF
    
    chmod +x /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh
    
    certbot renew --dry-run || log "WARN" "SSL renewal dry-run failed"
    
    log "INFO" "SSL auto-renewal configured"
}

#===============================================================================
# Базовые функции (Cockpit, мониторинг)
#===============================================================================

setup_cockpit() {
    if is_component_ready "cockpit"; then
        log "INFO" "Cockpit already configured, skipping..."
        return 0
    fi
    
    log "INFO" "Installing and configuring Cockpit..."
    
    local cockpit_packages=(
        "cockpit"
        "cockpit-machines"
        "cockpit-podman"
        "cockpit-networkmanager"
        "cockpit-storaged"
    )
    
    retry_with_backoff "$MAX_RETRIES" apt install -y "${cockpit_packages[@]}"
    
    # Создание пользователя cockpit-admin
    local cockpit_user="${COCKPIT_USER:-cockpit-admin}"
    local cockpit_password="${COCKPIT_PASSWORD:-}"
    
    if ! id "$cockpit_user" &>/dev/null; then
        useradd -m -s /bin/bash -G sudo "$cockpit_user"
        log "INFO" "User $cockpit_user created"
    fi
    
    if [[ -n "$cockpit_password" ]]; then
        echo "$cockpit_user:$cockpit_password" | chpasswd
        log "INFO" "Password set for $cockpit_user"
    fi
    
    systemctl enable --now cockpit.socket
    save_component_state "cockpit" "completed"
    log "INFO" "Cockpit configured successfully"
}

# Создание скрипта управления Marzban
create_marzban_management_script() {
    if [[ "${DEPLOY_MARZBAN:-false}" != "true" ]]; then
        return 0
    fi
    
    log "INFO" "Creating Marzban management script..."
    
    cat > /root/marzban-manage.sh <<EOF
#!/bin/bash

# Marzban Management Script

MARZBAN_DIR="$MARZBAN_DIR/marzban"

cd "\$MARZBAN_DIR" || { echo "Error: Cannot access Marzban directory"; exit 1; }

case "\$1" in
    "start")
        echo "Starting Marzban..."
        make up
        ;;
    "stop")
        echo "Stopping Marzban..."
        make down
        ;;
    "restart")
        echo "Restarting Marzban..."
        make restart
        ;;
    "logs")
        echo "Showing Marzban logs..."
        make logs
        ;;
    "status"|"health")
        echo "Checking Marzban health..."
        make health
        ;;
    "build")
        echo "Rebuilding Marzban container..."
        make build
        ;;
    "shell")
        echo "Opening shell in Marzban container..."
        make shell
        ;;
    "update")
        echo "Updating Marzban..."
        git pull
        make build
        make restart
        ;;
    "backup")
        echo "Creating Marzban backup..."
        tar -czf "/root/marzban-backup-\$(date +%Y%m%d_%H%M%S).tar.gz" -C "\$MARZBAN_DIR" data logs
        echo "Backup created in /root/"
        ;;
    "clean")
        echo "Cleaning Marzban containers and images..."
        make clean
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|logs|status|build|shell|update|backup|clean}"
        echo
        echo "Commands:"
        echo "  start    - Start Marzban services"
        echo "  stop     - Stop Marzban services"
        echo "  restart  - Restart Marzban services"
        echo "  logs     - Show container logs"
        echo "  status   - Check service health"
        echo "  build    - Rebuild containers"
        echo "  shell    - Open shell in container"
        echo "  update   - Update from git and rebuild"
        echo "  backup   - Create data backup"
        echo "  clean    - Clean containers and images"
        exit 1
        ;;
esac
EOF
    
    chmod +x /root/marzban-manage.sh
    log "INFO" "Marzban management script created: /root/marzban-manage.sh"
}

# Обновленные скрипты мониторинга
create_monitoring_scripts() {
    if is_component_ready "monitoring"; then
        log "INFO" "Monitoring scripts already created, skipping..."
        return 0
    fi
    
    log "INFO" "Creating monitoring and diagnostic scripts..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Проверка существующих скриптов
    if [[ -f "$SERVICES_CHECK_SCRIPT" ]]; then
        log "INFO" "Updating existing monitoring scripts..."
        cp "$SERVICES_CHECK_SCRIPT" "$SERVICES_CHECK_SCRIPT.backup.$(date +%s)"
    fi
    
    # Обновленный скрипт проверки сервисов с поддержкой Marzban
    cat > "$SERVICES_CHECK_SCRIPT" <<'EOF'
#!/bin/bash

# Скрипт проверки всех сервисов VPS setup с поддержкой Marzban

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    local service="$1"
    local status="$2"
    local color="$3"
    printf "%-20s %s\n" "$service:" "${color}${status}${NC}"
}

echo "=== VPS Services Status Check ==="
echo "Time: $(date)"
echo

# Base Services
for service in nginx cockpit docker ufw fail2ban; do
    case $service in
        "ufw")
            if ufw status | grep -q "Status: active"; then
                print_status "UFW Firewall" "✓ Active" "$GREEN"
            else
                print_status "UFW Firewall" "✗ Inactive" "$RED"
            fi
            ;;
        *)
            if systemctl is-active --quiet $service; then
                print_status "$(echo $service | tr a-z A-Z)" "✓ Running" "$GREEN"
            else
                print_status "$(echo $service | tr a-z A-Z)" "✗ Stopped" "$RED"
            fi
            ;;
    esac
done

# Marzban Check
if [[ -d "/opt/marzban-deployment/marzban" ]]; then
    cd /opt/marzban-deployment/marzban
    if docker-compose ps marzban 2>/dev/null | grep -q "Up"; then
        print_status "Marzban" "✓ Running" "$GREEN"
    else
        print_status "Marzban" "✗ Stopped" "$RED"
    fi
else
    print_status "Marzban" "Not deployed" "$YELLOW"
fi

echo
echo "=== SSL Certificates ==="
certbot certificates 2>/dev/null | grep -E "(Certificate Name|Expiry Date)" || echo "No certificates found"

echo
echo "=== Network Ports ==="
ss -tlnp | grep -E ':(80|443|8000|2083|9090)' | while read line; do
    echo "$line"
done

echo
echo "=== System Resources ==="
echo "Memory Usage:"
free -h | grep -E "(Mem|Swap)"
echo
echo "Disk Usage:"
df -h / | tail -1

if [[ -d "/opt/marzban-deployment/marzban" ]]; then
    echo
    echo "=== Marzban Docker Status ==="
    cd /opt/marzban-deployment/marzban
    docker-compose ps 2>/dev/null || echo "Docker compose not available"
fi

echo
echo "=== Recent Errors (last 10) ==="
journalctl --since "1 hour ago" -p err --no-pager -n 10 | grep -v "^--" | tail -5 || echo "No recent errors"
EOF
    
    chmod +x "$SERVICES_CHECK_SCRIPT"
    
    save_component_state "monitoring" "completed"
    log "INFO" "Monitoring scripts created successfully"
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
    setup_auto_updates
    setup_firewall
    setup_fail2ban
    install_docker
    setup_nginx
    setup_ssl
    setup_cockpit
    
    # Развертывание Marzban если включено
    deploy_marzban
    create_marzban_management_script
    
    # Создание скриптов мониторинга
    create_monitoring_scripts
    
    # Финальная проверка
    log "INFO" "Running final system check..."
    if [[ -x "$SERVICES_CHECK_SCRIPT" ]]; then
        "$SERVICES_CHECK_SCRIPT"
    fi
    
    # Создание финального отчета
    log "INFO" "=== VPS Setup Completed Successfully ==="
    log "INFO" "🌐 Website: https://$DOMAIN_NAME"
    log "INFO" "🖥️  Cockpit: https://$DOMAIN_NAME:9090"
    
    if [[ "${DEPLOY_MARZBAN:-false}" == "true" ]]; then
        local marzban_port="${MARZBAN_PANEL_PORT:-8000}"
        log "INFO" "🔒 Marzban Panel: https://$DOMAIN_NAME:$marzban_port"
        log "INFO" "🔗 Marzban Subdomain: https://marzban.$DOMAIN_NAME (if SSL available)"
        log "INFO" "⚙️  Marzban Management: /root/marzban-manage.sh"
        log "INFO" "📁 Marzban Directory: $MARZBAN_DIR/marzban"
    fi
    
    log "INFO" "📊 Service Check: $SERVICES_CHECK_SCRIPT"
    log "INFO" "📋 Logs: $LOGFILE"
    
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
FORCE_REBUILD="${FORCE_REBUILD:-false}"

# Запуск основной функции
main "$@"