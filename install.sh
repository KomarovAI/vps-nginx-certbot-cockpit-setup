#!/bin/bash

#===============================================================================
# VPS Setup Script v3.0 - Production Ready
# Автоматическая настройка VPS с Nginx, SSL, Cockpit и Docker
# Улучшенная версия с фиксами всех критических проблем
#===============================================================================

set -euo pipefail
IFS=$'\n\t'

# Константы и конфигурация
readonly SCRIPT_VERSION="3.0"
readonly LOGFILE="/var/log/vps-setup.log"
readonly LOCKFILE="/tmp/vps-setup.lock"
readonly NGINX_CONF_DIR="/etc/nginx"
readonly SSL_CHALLENGE_DIR="/var/www"
readonly SERVICES_CHECK_SCRIPT="/root/check-services.sh"
readonly BACKUP_DIR="/root/config-backup"

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
        log "INFO" "  DOMAIN_NAME    - Your domain name"
        log "INFO" "  ADMIN_EMAIL    - Admin email for SSL"
        log "INFO" "Optional variables:"
        log "INFO" "  COCKPIT_PASSWORD - Cockpit admin password"
        log "INFO" "  VPS_IP          - VPS IP for logging"
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
}

# Проверка системных требований
check_prerequisites() {
    log "INFO" "Checking system prerequisites..."
    
    # Проверка Ubuntu версии
    if [[ ! -f /etc/lsb-release ]] || ! grep -q "Ubuntu" /etc/lsb-release; then
        log "WARN" "This script is optimized for Ubuntu, proceed with caution"
    fi
    
    # Проверка свободного места (минимум 2GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local min_space=$((2 * 1024 * 1024)) # 2GB в KB
    
    if [[ $available_space -lt $min_space ]]; then
        log "ERROR" "Insufficient disk space. Required: 2GB, Available: $(($available_space/1024/1024))GB"
        exit 1
    fi
    
    # Проверка памяти (минимум 512MB)
    local available_memory=$(free | awk 'NR==2 {print $7}')
    local min_memory=$((512 * 1024)) # 512MB в KB
    
    if [[ $available_memory -lt $min_memory ]]; then
        log "WARN" "Low available memory: $(($available_memory/1024))MB, consider adding swap"
    fi
    
    log "INFO" "Prerequisites check completed"
}

#===============================================================================
# Функции установки с retry логикой
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

# Обновление системы с кэшированием
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
    )
    
    retry_with_backoff "$MAX_RETRIES" apt install -y "${base_packages[@]}"
    
    log "INFO" "System packages updated successfully"
}

# Настройка автоматических обновлений безопасности
setup_auto_updates() {
    log "INFO" "Configuring automatic security updates..."
    
    # Конфигурация unattended-upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Package-Blacklist {
};
Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
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
    log "INFO" "Automatic security updates enabled"
}

# Конфигурация UFW с улучшенными правилами
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
    
    # Включение UFW
    ufw --force enable
    
    log "INFO" "UFW firewall configured successfully"
}

# Настройка fail2ban
setup_fail2ban() {
    log "INFO" "Configuring fail2ban..."
    
    # Базовая конфигурация fail2ban
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
    
    systemctl enable --now fail2ban
    log "INFO" "fail2ban configured successfully"
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

# Настройка Nginx
setup_nginx() {
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
    
    # Создание начальной HTTP конфигурации для ACME challenge
    create_nginx_http_config "$domain" "$webroot"
    
    # Тест конфигурации и перезагрузка
    nginx -t || error_exit $LINENO 1
    systemctl reload nginx
    
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
            <ul>
                <li><strong>Веб-сайт:</strong> <a href="https://$domain">https://$domain</a></li>
                <li><strong>Панель управления Cockpit:</strong> <a href="https://$domain:9090">https://$domain:9090</a></li>
            </ul>
        </div>
        
        <div class="info">
            <h3>🔒 Безопасность:</h3>
            <ul>
                <li>SSL сертификат от Let's Encrypt</li>
                <li>Firewall (UFW) настроен</li>
                <li>Fail2ban активен</li>
                <li>Автоматические обновления безопасности включены</li>
            </ul>
        </div>
        
        <div class="footer">
            Дата установки: $current_time<br>
            Powered by nginx + Docker + Cockpit
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

# SSL сертификаты
setup_ssl() {
    log "INFO" "Setting up SSL certificates..."
    
    local domain="$DOMAIN_NAME"
    local email="$ADMIN_EMAIL"
    
    # Установка Certbot
    install_certbot
    
    # Проверка DNS перед получением сертификата
    verify_dns "$domain"
    
    # Получение SSL сертификата с retry
    obtain_ssl_certificate "$domain" "$email"
    
    # Обновление Nginx конфигурации для HTTPS
    create_nginx_https_config "$domain"
    
    # Настройка автообновления сертификатов
    setup_ssl_renewal
    
    log "INFO" "SSL certificates configured successfully"
}

install_certbot() {
    log "INFO" "Installing Certbot..."
    
    # Установка через snap (рекомендуемый способ)
    snap install core
    snap refresh core
    retry_with_backoff "$MAX_RETRIES" snap install --classic certbot
    
    # Создание симлинка
    ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
    
    log "INFO" "Certbot installed successfully"
}

verify_dns() {
    local domain="$1"
    local server_ip="${VPS_IP:-$(curl -s ifconfig.me 2>/dev/null || echo 'unknown')}"
    
    log "INFO" "Verifying DNS configuration for $domain..."
    
    # Проверка A записи
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
    
    # Функция получения сертификата
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
    
    # Попытка получения с retry и экспоненциальным backoff
    if retry_with_backoff "$MAX_RETRIES" get_certificate; then
        log "INFO" "SSL certificate obtained successfully"
        
        # Проверка файлов сертификата
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
        log "INFO" "Please check:"
        log "INFO" "1. Domain DNS points to this server"
        log "INFO" "2. Port 80 is accessible from the internet"
        log "INFO" "3. No other web server is running on port 80"
        exit 1
    fi
}

create_nginx_https_config() {
    local domain="$1"
    
    log "INFO" "Creating HTTPS Nginx configuration..."
    
    # Backup старой конфигурации
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
    
    # Тест конфигурации
    nginx -t || error_exit $LINENO 1
    systemctl reload nginx
    
    log "INFO" "HTTPS configuration applied successfully"
}

setup_ssl_renewal() {
    log "INFO" "Setting up SSL certificate auto-renewal..."
    
    # Создание hook скрипта для перезагрузки nginx после обновления
    mkdir -p /etc/letsencrypt/renewal-hooks/post
    cat > /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh <<'EOF'
#!/bin/bash
# Перезагрузка nginx после обновления сертификатов
systemctl reload nginx
logger "SSL certificates renewed and nginx reloaded"
EOF
    
    chmod +x /etc/letsencrypt/renewal-hooks/post/nginx-reload.sh
    
    # Проверка автообновления
    certbot renew --dry-run || log "WARN" "SSL renewal dry-run failed"
    
    log "INFO" "SSL auto-renewal configured"
}

# Установка и настройка Cockpit
setup_cockpit() {
    log "INFO" "Installing and configuring Cockpit..."
    
    # Установка Cockpit пакетов
    local cockpit_packages=(
        "cockpit"
        "cockpit-machines"
        "cockpit-podman"
        "cockpit-networkmanager"
        "cockpit-storaged"
    )
    
    retry_with_backoff "$MAX_RETRIES" apt install -y "${cockpit_packages[@]}"
    
    # Создание пользователя cockpit-admin
    create_cockpit_user
    
    # Настройка SSL для Cockpit
    configure_cockpit_ssl
    
    # Настройка Cockpit конфигурации
    configure_cockpit_settings
    
    # Запуск Cockpit
    systemctl enable --now cockpit.socket
    
    # Создание Nginx прокси для поддомена (опционально)
    setup_cockpit_subdomain
    
    log "INFO" "Cockpit configured successfully"
}

create_cockpit_user() {
    local cockpit_user="${COCKPIT_USER:-cockpit-admin}"
    local cockpit_password="${COCKPIT_PASSWORD:-}"
    
    log "INFO" "Creating Cockpit admin user: $cockpit_user"
    
    # Создание пользователя если не существует
    if ! id "$cockpit_user" &>/dev/null; then
        useradd -m -s /bin/bash -G sudo "$cockpit_user"
        log "INFO" "User $cockpit_user created"
    else
        log "INFO" "User $cockpit_user already exists"
    fi
    
    # Установка пароля
    if [[ -n "$cockpit_password" ]]; then
        echo "$cockpit_user:$cockpit_password" | chpasswd
        log "INFO" "Password set for $cockpit_user"
        
        # Безопасное удаление пароля из памяти
        unset cockpit_password
        unset COCKPIT_PASSWORD
    else
        log "WARN" "No password provided for $cockpit_user"
        log "INFO" "Set password manually: passwd $cockpit_user"
    fi
}

configure_cockpit_ssl() {
    local domain="$DOMAIN_NAME"
    
    log "INFO" "Configuring Cockpit SSL certificates..."
    
    # Создание директории для сертификатов Cockpit
    mkdir -p /etc/cockpit/ws-certs.d
    
    # Копирование SSL сертификатов для Cockpit
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" && -f "/etc/letsencrypt/live/$domain/privkey.pem" ]]; then
        cp "/etc/letsencrypt/live/$domain/fullchain.pem" "/etc/cockpit/ws-certs.d/$domain.crt"
        cp "/etc/letsencrypt/live/$domain/privkey.pem" "/etc/cockpit/ws-certs.d/$domain.key"
        
        # Установка правильных прав
        chgrp cockpit-ws "/etc/cockpit/ws-certs.d/$domain."*
        chmod 640 "/etc/cockpit/ws-certs.d/$domain."*
        
        log "INFO" "SSL certificates configured for Cockpit"
    else
        log "WARN" "SSL certificates not found, Cockpit will use self-signed certificate"
    fi
}

configure_cockpit_settings() {
    log "INFO" "Configuring Cockpit settings..."
    
    # Настройка Cockpit конфигурации
    mkdir -p /etc/cockpit
    cat > /etc/cockpit/cockpit.conf <<EOF
[WebService]
# Отключение автологаута (по запросу пользователя)
IdleTimeout=0
# Увеличение таймаутов для стабильности
Origins = https://$DOMAIN_NAME wss://$DOMAIN_NAME
ProtocolHeader = X-Forwarded-Proto
ForwardedForHeader = X-Forwarded-For

[Session]
# Увеличенное время сессии
IdleTimeout = 0
EOF
    
    log "INFO" "Cockpit configuration updated"
}

setup_cockpit_subdomain() {
    local cockpit_subdomain="cockpit.$DOMAIN_NAME"
    
    log "INFO" "Setting up Cockpit subdomain: $cockpit_subdomain"
    
    # Получение сертификата для поддомена (опционально)
    if certbot certonly --webroot -w "/var/www/$DOMAIN_NAME" -d "$cockpit_subdomain" \
        --email "$ADMIN_EMAIL" --agree-tos --no-eff-email --non-interactive; then
        
        # Создание Nginx конфигурации для Cockpit поддомена
        cat > "$NGINX_CONF_DIR/sites-available/cockpit-$DOMAIN_NAME" <<EOF
# Cockpit Subdomain Configuration
server {
    listen 443 ssl http2;
    server_name $cockpit_subdomain;
    
    ssl_certificate /etc/letsencrypt/live/$cockpit_subdomain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$cockpit_subdomain/privkey.pem;
    
    # Modern SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    
    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    
    # Proxy to Cockpit
    location / {
        proxy_pass https://127.0.0.1:9090;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts (увеличенные по запросу пользователя)
        proxy_buffering off;
        gzip off;
        
        proxy_read_timeout 12h;
        proxy_send_timeout 12h;
        proxy_connect_timeout 60s;
        keepalive_timeout 12h 12h;
    }
}
EOF
        
        ln -sf "$NGINX_CONF_DIR/sites-available/cockpit-$DOMAIN_NAME" "$NGINX_CONF_DIR/sites-enabled/cockpit-$DOMAIN_NAME"
        
        # Тест и перезагрузка
        if nginx -t; then
            systemctl reload nginx
            log "INFO" "Cockpit subdomain configured: https://$cockpit_subdomain"
        else
            log "WARN" "Nginx configuration error for Cockpit subdomain"
        fi
    else
        log "WARN" "Could not obtain SSL certificate for Cockpit subdomain (optional feature)"
    fi
}

# Создание утилит мониторинга и диагностики
create_monitoring_scripts() {
    log "INFO" "Creating monitoring and diagnostic scripts..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Скрипт проверки сервисов
    create_service_check_script
    
    # Скрипт мониторинга
    create_monitoring_script
    
    # Скрипт health check
    create_health_check_script
    
    # Скрипт backup
    create_backup_script
    
    log "INFO" "Monitoring scripts created successfully"
}

create_service_check_script() {
    cat > "$SERVICES_CHECK_SCRIPT" <<'EOF'
#!/bin/bash

# Скрипт проверки всех сервисов VPS setup

# Цвета
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

# Nginx Status
if systemctl is-active --quiet nginx; then
    print_status "Nginx" "✓ Running" "$GREEN"
else
    print_status "Nginx" "✗ Stopped" "$RED"
fi

# Cockpit Status  
if systemctl is-active --quiet cockpit; then
    print_status "Cockpit" "✓ Running" "$GREEN"
else
    print_status "Cockpit" "✗ Stopped" "$RED"
fi

# Docker Status
if systemctl is-active --quiet docker; then
    print_status "Docker" "✓ Running" "$GREEN"
else
    print_status "Docker" "✗ Stopped" "$RED"
fi

# UFW Status
if ufw status | grep -q "Status: active"; then
    print_status "UFW Firewall" "✓ Active" "$GREEN"
else
    print_status "UFW Firewall" "✗ Inactive" "$RED"
fi

# fail2ban Status
if systemctl is-active --quiet fail2ban; then
    print_status "fail2ban" "✓ Running" "$GREEN"
else
    print_status "fail2ban" "✗ Stopped" "$RED"
fi

echo
echo "=== SSL Certificates ==="
certbot certificates 2>/dev/null | grep -E "(Certificate Name|Expiry Date)" || echo "No certificates found"

echo
echo "=== Network Ports ==="
ss -tlnp | grep -E ':(80|443|9090)' | while read line; do
    echo "$line"
done

echo
echo "=== System Resources ==="
echo "Memory Usage:"
free -h | grep -E "(Mem|Swap)"
echo
echo "Disk Usage:"
df -h / | tail -1

echo
echo "=== Recent Errors (last 10) ==="
journalctl --since "1 hour ago" -p err --no-pager -n 10 | grep -v "^--" | tail -5 || echo "No recent errors"
EOF
    
    chmod +x "$SERVICES_CHECK_SCRIPT"
}

create_monitoring_script() {
    cat > /root/monitor.sh <<'EOF'
#!/bin/bash

# Скрипт мониторинга в реальном времени

echo "=== VPS Real-time Monitoring ==="
echo "Press Ctrl+C to exit"
echo

while true; do
    clear
    echo "=== $(date) ==="
    
    # System load
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    
    # Memory
    echo "Memory:"
    free -h | head -2 | tail -1
    
    # Disk
    echo "Disk (/):"
    df -h / | tail -1
    
    # Network connections
    echo "Active connections:"
    ss -tuln | grep -E ':(80|443|9090)' | wc -l | xargs echo "HTTP/HTTPS/Cockpit:"
    
    # Services status
    echo "Services:"
    for service in nginx cockpit docker fail2ban; do
        if systemctl is-active --quiet $service; then
            echo "  $service: ✓"
        else
            echo "  $service: ✗"
        fi
    done
    
    # Recent log entries
    echo "Recent errors:"
    journalctl --since "5 minutes ago" -p err --no-pager -n 3 | grep -v "^--" | tail -3 || echo "  No errors"
    
    sleep 5
done
EOF
    
    chmod +x /root/monitor.sh
}

create_health_check_script() {
    cat > /root/health-check.sh <<'EOF'
#!/bin/bash

# Health check script для мониторинга

HEALTH_FILE="/var/log/health-check.log"
DOMAIN="${DOMAIN_NAME:-localhost}"

log_health() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$HEALTH_FILE"
}

# Проверка HTTP/HTTPS доступности
check_web() {
    if curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN" | grep -q "200"; then
        log_health "WEB: OK - https://$DOMAIN"
        return 0
    else
        log_health "WEB: FAIL - https://$DOMAIN not accessible"
        return 1
    fi
}

# Проверка Cockpit
check_cockpit() {
    if curl -k -s -o /dev/null -w "%{http_code}" "https://$DOMAIN:9090" | grep -q "200"; then
        log_health "COCKPIT: OK - https://$DOMAIN:9090"
        return 0
    else
        log_health "COCKPIT: FAIL - https://$DOMAIN:9090 not accessible"
        return 1
    fi
}

# Проверка SSL сертификата
check_ssl() {
    local expiry_days
    expiry_days=$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2 | xargs -I {} date -d {} +%s)
    local current_time=$(date +%s)
    local days_left=$(( (expiry_days - current_time) / 86400 ))
    
    if [[ $days_left -gt 30 ]]; then
        log_health "SSL: OK - Certificate expires in $days_left days"
        return 0
    elif [[ $days_left -gt 7 ]]; then
        log_health "SSL: WARNING - Certificate expires in $days_left days"
        return 1
    else
        log_health "SSL: CRITICAL - Certificate expires in $days_left days"
        return 2
    fi
}

# Основная проверка
main() {
    log_health "=== Health Check Started ==="
    
    local exit_code=0
    
    check_web || exit_code=1
    check_cockpit || exit_code=1
    check_ssl || exit_code=1
    
    # Проверка сервисов
    for service in nginx cockpit docker; do
        if systemctl is-active --quiet "$service"; then
            log_health "SERVICE: OK - $service is running"
        else
            log_health "SERVICE: FAIL - $service is not running"
            exit_code=1
        fi
    done
    
    log_health "=== Health Check Completed (exit code: $exit_code) ==="
    return $exit_code
}

main "$@"
EOF
    
    chmod +x /root/health-check.sh
    
    # Добавление в cron для автоматической проверки
    (crontab -l 2>/dev/null || true; echo "*/15 * * * * /root/health-check.sh") | crontab -
}

create_backup_script() {
    cat > /root/backup-configs.sh <<'EOF'
#!/bin/bash

# Скрипт резервного копирования конфигураций

BACKUP_DIR="/root/config-backup"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="vps-config-backup-$DATE.tar.gz"

echo "Creating configuration backup..."

mkdir -p "$BACKUP_DIR"

# Создание временной директории для сбора файлов
TEMP_DIR=$(mktemp -d)
BACKUP_TEMP="$TEMP_DIR/vps-config-$DATE"
mkdir -p "$BACKUP_TEMP"

# Копирование конфигурационных файлов
cp -r /etc/nginx "$BACKUP_TEMP/" 2>/dev/null || true
cp -r /etc/letsencrypt "$BACKUP_TEMP/" 2>/dev/null || true
cp -r /etc/cockpit "$BACKUP_TEMP/" 2>/dev/null || true
cp -r /etc/ufw "$BACKUP_TEMP/" 2>/dev/null || true
cp -r /etc/fail2ban "$BACKUP_TEMP/" 2>/dev/null || true
cp /etc/crontab "$BACKUP_TEMP/" 2>/dev/null || true
cp /var/www/*/index.html "$BACKUP_TEMP/" 2>/dev/null || true

# Сохранение списка установленных пакетов
dpkg --get-selections > "$BACKUP_TEMP/installed-packages.txt"
systemctl list-unit-files --state=enabled > "$BACKUP_TEMP/enabled-services.txt"

# Создание архива
cd "$TEMP_DIR"
tar -czf "$BACKUP_DIR/$BACKUP_NAME" "vps-config-$DATE"

# Очистка
rm -rf "$TEMP_DIR"

# Удаление старых backup'ов (старше 30 дней)
find "$BACKUP_DIR" -name "vps-config-backup-*.tar.gz" -mtime +30 -delete

echo "Backup created: $BACKUP_DIR/$BACKUP_NAME"
ls -lh "$BACKUP_DIR/$BACKUP_NAME"
EOF
    
    chmod +x /root/backup-configs.sh
    
    # Добавление в cron для еженедельного backup
    (crontab -l 2>/dev/null || true; echo "0 2 * * 0 /root/backup-configs.sh") | crontab -
}

# Главная функция
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
    log "INFO" "📊 Service Check: $SERVICES_CHECK_SCRIPT"
    log "INFO" "📈 Monitoring: /root/monitor.sh"
    log "INFO" "🔍 Health Check: /root/health-check.sh"  
    log "INFO" "💾 Backup: /root/backup-configs.sh"
    log "INFO" "📋 Logs: $LOGFILE"
    
    log "INFO" "Setup completed at $(date)"
}

# Установка переменных из аргументов
DOMAIN_NAME="${DOMAIN_NAME:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
VPS_IP="${VPS_IP:-}"
COCKPIT_PASSWORD="${COCKPIT_PASSWORD:-}"
COCKPIT_USER="${COCKPIT_USER:-cockpit-admin}"

# Запуск основной функции
main "$@"