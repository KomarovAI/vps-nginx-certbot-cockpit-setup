#!/bin/bash

#===============================================================================
# VPS Update Script v3.0 - Production Ready
# Обновление системы, SSL сертификатов и служб
# Исправленная версия с улучшенным логированием и обработкой ошибок
#===============================================================================

set -euo pipefail

# Константы
readonly SCRIPT_VERSION="3.0"
readonly LOGFILE="/var/log/vps-update.log"
readonly BACKUP_DIR="/root/update-backup"
readonly MAX_RETRIES=3

# Получаем переменные окружения с дефолтными значениями
readonly DOMAIN="${DOMAIN_NAME:-}"
readonly EMAIL="${ADMIN_EMAIL:-}"

# Цвета для вывода (только если TTY)
if [[ -t 1 ]]; then
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly RED='\033[0;31m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m'
else
    readonly GREEN=''
    readonly YELLOW=''
    readonly RED=''
    readonly BLUE=''
    readonly NC=''
fi

#===============================================================================
# Функции логирования
#===============================================================================

# Настройка логирования
setup_logging() {
    # Создание лог файла если не существует
    touch "$LOGFILE"
    exec 1> >(tee -a "$LOGFILE")
    exec 2>&1
}

# Унифицированное логирование
log() {
    local level="$1"
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        "INFO")  echo -e "${GREEN}[$timestamp] [INFO]  $*${NC}" ;;
        "WARN")  echo -e "${YELLOW}[$timestamp] [WARN]  $*${NC}" ;;
        "ERROR") echo -e "${RED}[$timestamp] [ERROR] $*${NC}" ;;
        "DEBUG") echo -e "${BLUE}[$timestamp] [DEBUG] $*${NC}" ;;
    esac
}

# Обработка ошибок
error_exit() {
    local line_no=${1:-$LINENO}
    local exit_code=${2:-1}
    log "ERROR" "Update script failed at line $line_no with exit code $exit_code"
    exit "$exit_code"
}

trap 'error_exit $LINENO $?' ERR

#===============================================================================
# Проверки и валидация
#===============================================================================

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
}

# Проверка переменных окружения
validate_environment() {
    if [[ -z "$DOMAIN" ]]; then
        log "WARN" "DOMAIN_NAME not set, some features may not work correctly"
    else
        log "INFO" "Domain: $DOMAIN"
    fi
    
    if [[ -z "$EMAIL" ]]; then
        log "WARN" "ADMIN_EMAIL not set, SSL renewal notifications may not work"
    else
        log "INFO" "Admin email: $EMAIL"
    fi
}

# Проверка доступности сервисов
check_services() {
    log "INFO" "Checking service status..."
    
    local services=("nginx" "cockpit" "docker")
    local failed_services=()
    
    for service in "${services[@]}"; do
        if systemctl is-installed "$service" &>/dev/null; then
            if systemctl is-active --quiet "$service"; then
                log "INFO" "✓ $service is running"
            else
                log "WARN" "✗ $service is not running"
                failed_services+=("$service")
            fi
        else
            log "WARN" "Service $service is not installed"
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log "WARN" "Some services are not running: ${failed_services[*]}"
        return 1
    fi
    
    return 0
}

#===============================================================================
# Функции обновления с retry логикой
#===============================================================================

# Retry функция
retry_command() {
    local max_attempts="$1"
    shift
    local attempt=1
    local delay=2
    
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

# Создание backup'а конфигураций
create_backup() {
    log "INFO" "Creating configuration backup..."
    
    local backup_timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_path="$BACKUP_DIR/update-backup-$backup_timestamp"
    
    mkdir -p "$backup_path"
    
    # Backup важных конфигурационных файлов
    local config_files=(
        "/etc/nginx/sites-available"
        "/etc/nginx/sites-enabled"
        "/etc/nginx/nginx.conf"
        "/etc/cockpit"
        "/etc/letsencrypt"
        "/etc/crontab"
        "/etc/fstab"
        "/etc/default/zramswap"
        "/etc/sysctl.d"
    )
    
    for config in "${config_files[@]}"; do
        if [[ -e "$config" ]]; then
            cp -r "$config" "$backup_path/" 2>/dev/null || log "WARN" "Failed to backup $config"
        fi
    done
    
    # Список установленных пакетов
    dpkg --get-selections > "$backup_path/installed-packages.txt"
    systemctl list-unit-files --state=enabled > "$backup_path/enabled-services.txt"
    
    log "INFO" "Backup created: $backup_path"
    
    # Очистка старых backup'ов (старше 7 дней)
    find "$BACKUP_DIR" -name "update-backup-*" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
}

#===============================================================================
# Обновление системы
#===============================================================================

update_system_packages() {
    log "INFO" "Updating system packages..."
    
    # Обновление списка пакетов
    retry_command "$MAX_RETRIES" apt update
    
    # Обновление пакетов
    retry_command "$MAX_RETRIES" bash -c "DEBIAN_FRONTEND=noninteractive apt upgrade -y"
    
    # Обновление snap пакетов
    log "INFO" "Updating snap packages..."
    if command -v snap &>/dev/null; then
        snap refresh 2>/dev/null || log "WARN" "Snap refresh failed (non-critical)"
    fi
    
    log "INFO" "System packages updated successfully"
}

# Обновление Docker и контейнеров
update_docker() {
    log "INFO" "Updating Docker and containers..."
    
    if command -v docker &>/dev/null; then
        # Обновление Docker images которые используются
        log "INFO" "Updating Docker images..."
        
        # Получаем список запущенных контейнеров
        local running_containers
        running_containers=$(docker ps --format "table {{.Image}}" | tail -n +2 | sort -u)
        
        if [[ -n "$running_containers" ]]; then
            while IFS= read -r image; do
                if [[ -n "$image" ]]; then
                    log "INFO" "Pulling latest version of $image"
                    docker pull "$image" || log "WARN" "Failed to pull $image"
                fi
            done <<< "$running_containers"
        fi
        
        # Очистка неиспользуемых images
        docker image prune -f || log "WARN" "Docker image cleanup failed"
        
        log "INFO" "Docker update completed"
    else
        log "INFO" "Docker not found, skipping Docker updates"
    fi
}

#===============================================================================
# Обновление SSL сертификатов
#===============================================================================

update_ssl_certificates() {
    log "INFO" "Checking and updating SSL certificates..."
    
    if ! command -v certbot &>/dev/null; then
        log "WARN" "Certbot not installed, skipping SSL update"
        return 0
    fi
    
    # Проверка сертификатов
    log "INFO" "Current certificate status:"
    certbot certificates | head -20 || log "WARN" "Failed to list certificates"
    
    # Обновление сертификатов (dry run для проверки)
    log "INFO" "Testing certificate renewal..."
    if certbot renew --dry-run; then
        log "INFO" "Certificate renewal test passed"
        
        # Реальное обновление
        log "INFO" "Renewing certificates..."
        certbot renew --quiet || log "WARN" "Certificate renewal had issues"
        
        # Проверка сроков действия
        check_certificate_expiry
    else
        log "WARN" "Certificate renewal test failed"
    fi
}

# Проверка сроков действия сертификатов
check_certificate_expiry() {
    if [[ -n "$DOMAIN" ]] && [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
        local expiry_date
        expiry_date=$(openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -dates | grep notAfter | cut -d= -f2)
        local days_left
        days_left=$(( ($(date -d "$expiry_date" +%s) - $(date +%s)) / 86400 ))
        
        log "INFO" "SSL certificate expires in $days_left days"
        
        if [[ $days_left -lt 30 ]]; then
            log "WARN" "SSL certificate expires soon ($days_left days)"
        fi
    fi
}

#===============================================================================
# Проверка и обновление конфигураций
#===============================================================================

# Проверка конфигурации Nginx
check_nginx_config() {
    log "INFO" "Checking Nginx configuration..."
    
    if command -v nginx &>/dev/null; then
        if nginx -t; then
            log "INFO" "Nginx configuration is valid"
            return 0
        else
            log "ERROR" "Nginx configuration has errors!"
            return 1
        fi
    else
        log "WARN" "Nginx not installed"
        return 0
    fi
}

# Обновление конфигурационных файлов
update_configs() {
    log "INFO" "Updating configurations..."
    
    # Обновление временной метки на главной странице
    if [[ -n "$DOMAIN" && -f "/var/www/$DOMAIN/index.html" ]]; then
        local current_time=$(date '+%B %d, %Y, %H:%M MSK')
        sed -i "s/Дата установки:.*/Обновлено: $current_time/g" "/var/www/$DOMAIN/index.html" || log "WARN" "Failed to update website timestamp"
        log "INFO" "Website timestamp updated"
    fi
    
    # Обновление Cockpit сертификатов если необходимо
    update_cockpit_ssl
}

# Обновление SSL сертификатов для Cockpit
update_cockpit_ssl() {
    if [[ -n "$DOMAIN" ]] && [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
        log "INFO" "Updating Cockpit SSL certificates..."
        
        mkdir -p /etc/cockpit/ws-certs.d
        
        # Копирование обновленных сертификатов
        cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "/etc/cockpit/ws-certs.d/$DOMAIN.crt" || log "WARN" "Failed to copy Cockpit cert"
        cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "/etc/cockpit/ws-certs.d/$DOMAIN.key" || log "WARN" "Failed to copy Cockpit key"
        
        # Установка правильных прав
        chgrp cockpit-ws "/etc/cockpit/ws-certs.d/$DOMAIN."* 2>/dev/null || true
        chmod 640 "/etc/cockpit/ws-certs.d/$DOMAIN."* 2>/dev/null || true
        
        log "INFO" "Cockpit SSL certificates updated"
    fi
}

#===============================================================================
# Перезапуск сервисов
#===============================================================================

restart_services() {
    log "INFO" "Restarting services..."
    
    local services_to_restart=(
        "nginx:reload"
        "cockpit:restart"
        "fail2ban:restart"
    )
    
    for service_action in "${services_to_restart[@]}"; do
        local service="${service_action%:*}"
        local action="${service_action#*:}"
        
        if systemctl is-installed "$service" &>/dev/null; then
            log "INFO" "Performing $action on $service..."
            
            if systemctl "$action" "$service"; then
                log "INFO" "✓ $service ${action}ed successfully"
            else
                log "WARN" "✗ Failed to $action $service"
            fi
        else
            log "INFO" "Service $service not installed, skipping"
        fi
    done
}

#===============================================================================
# Очистка системы
#===============================================================================

cleanup_system() {
    log "INFO" "Performing system cleanup..."
    
    # Очистка пакетов
    apt autoremove -y || log "WARN" "Failed to remove unused packages"
    apt autoclean || log "WARN" "Failed to clean package cache"
    
    # Очистка логов старше 30 дней
    journalctl --vacuum-time=30d || log "WARN" "Failed to vacuum journal logs"
    
    # Очистка временных файлов
    find /tmp -type f -atime +7 -delete 2>/dev/null || true
    
    # Очистка старых ядер (только если установлен пакет)
    if dpkg -l | grep -q linux-image; then
        apt autoremove --purge -y || log "WARN" "Failed to remove old kernels"
    fi
    
    log "INFO" "System cleanup completed"
}

#===============================================================================
# Мониторинг и отчеты
#===============================================================================

# Генерация отчета о состоянии системы
generate_status_report() {
    log "INFO" "Generating system status report..."
    
    local report_file="/tmp/update-report-$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" <<EOF
=== VPS Update Report ===
Date: $(date)
Update Script Version: $SCRIPT_VERSION
Domain: ${DOMAIN:-not configured}
Email: ${EMAIL:-not configured}

=== System Information ===
Hostname: $(hostname)
Uptime: $(uptime -p)
Kernel: $(uname -r)
OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")

=== Disk Usage ===
$(df -h /)

=== Memory Usage ===  
$(free -h)

=== Service Status ===
EOF
    
    # Статус сервисов
    local services=("nginx" "cockpit" "docker" "fail2ban" "ufw")
    for service in "${services[@]}"; do
        if systemctl is-installed "$service" &>/dev/null; then
            local status=$(systemctl is-active "$service")
            echo "$service: $status" >> "$report_file"
        fi
    done
    
    echo "" >> "$report_file"
    echo "=== SSL Certificates ===" >> "$report_file"
    certbot certificates 2>/dev/null | grep -E "(Certificate Name|Expiry Date)" >> "$report_file" || echo "No certificates found" >> "$report_file"
    
    echo "" >> "$report_file"
    echo "=== Network Ports ===" >> "$report_file"
    ss -tlnp | grep -E ':(80|443|9090)' >> "$report_file" || echo "No ports listening" >> "$report_file"
    
    echo "" >> "$report_file"
    echo "=== Recent Updates ===" >> "$report_file"
    grep "$(date +%Y-%m-%d)" /var/log/dpkg.log | tail -10 >> "$report_file" 2>/dev/null || echo "No recent package updates" >> "$report_file"
    
    log "INFO" "Status report created: $report_file"
    
    # Показать краткую сводку
    echo
    log "INFO" "=== Update Summary ==="
    grep -A 20 "=== System Information ===" "$report_file"
}

# Проверка статуса всех служб
final_service_check() {
    log "INFO" "Running final service check..."
    
    if [[ -x "/root/check-services.sh" ]]; then
        log "INFO" "Running comprehensive service check..."
        /root/check-services.sh || log "WARN" "Service check script had issues"
    else
        # Базовая проверка
        log "INFO" "=== Service Status ==="
        systemctl status nginx --no-pager -l | head -5 || log "WARN" "Nginx status check failed"
        systemctl status cockpit --no-pager -l | head -5 || log "WARN" "Cockpit status check failed"
        systemctl status docker --no-pager -l | head -5 || log "WARN" "Docker status check failed"
        
        log "INFO" "=== Open Ports ==="
        ss -tlnp | grep -E ':(80|443|9090)' || log "WARN" "No expected ports found listening"
    fi
}

#===============================================================================
# Главная функция
#===============================================================================

main() {
    setup_logging
    
    log "INFO" "=== VPS Update Script v$SCRIPT_VERSION Started ==="
    
    # Проверки
    check_root
    validate_environment
    
    # Pre-update проверки
    log "INFO" "Performing pre-update checks..."
    check_services || log "WARN" "Some services are not running properly"
    
    # Создание backup'а
    create_backup
    
    # Обновления
    update_system_packages
    update_docker
    update_ssl_certificates
    
    # Проверка конфигураций
    check_nginx_config || error_exit $LINENO 1
    update_configs
    
    # Перезапуск сервисов
    restart_services
    
    # Очистка
    cleanup_system
    
    # Финальные проверки
    final_service_check
    
    # Отчет
    generate_status_report
    
    log "INFO" "✅ VPS update completed successfully!"
    log "INFO" "📊 Summary:"
    log "INFO" "• System packages: Updated"
    log "INFO" "• SSL certificates: Checked/Renewed"
    log "INFO" "• Services: Restarted"
    log "INFO" "• System: Cleaned up"
    log "INFO" "• Update time: $(date '+%Y-%m-%d %H:%M:%S')"
    
    if [[ -n "$DOMAIN" ]]; then
        log "INFO" "🌐 Services available at:"
        log "INFO" "• Website: https://$DOMAIN"
        log "INFO" "• Cockpit: https://$DOMAIN:9090"
    fi
    
    log "INFO" "📋 Full log: $LOGFILE"
}

# Запуск основной функции
main "$@"