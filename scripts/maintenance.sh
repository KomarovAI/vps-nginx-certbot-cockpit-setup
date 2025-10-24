#!/bin/bash

#===============================================================================
# VPS Maintenance Script
# Автоматическое обслуживание VPS сервера
#===============================================================================

set -euo pipefail

# Константы
readonly MAINTENANCE_LOG="/var/log/maintenance.log"
readonly DOMAIN="${DOMAIN_NAME:-localhost}"

# Логирование
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MAINTENANCE_LOG"
}

# Проверка root прав
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

log "=== VPS Maintenance Started ==="

# 1. Обновление системы
log "Updating system packages..."
apt update -q
apt upgrade -y
apt autoremove -y
apt autoclean

# 2. Очистка логов
log "Cleaning old logs..."
journalctl --vacuum-time=30d
find /var/log -name "*.log" -mtime +30 -delete 2>/dev/null || true
find /var/log/nginx -name "*.log.*" -mtime +7 -delete 2>/dev/null || true

# 3. Очистка Docker
if command -v docker &>/dev/null; then
    log "Cleaning Docker resources..."
    docker system prune -f
    docker image prune -a -f
fi

# 4. Проверка SSL сертификатов
if command -v certbot &>/dev/null; then
    log "Checking SSL certificates..."
    certbot renew --quiet
fi

# 5. Проверка дискового пространства
log "Checking disk space..."
DISK_USAGE=$(df / | awk 'NR==2 {print $(NF-1)}' | sed 's/%//')
if [[ $DISK_USAGE -gt 85 ]]; then
    log "WARNING: Disk usage is at ${DISK_USAGE}%"
    # Отправка уведомления если настроено
fi

# 6. Проверка сервисов
log "Checking critical services..."
for service in nginx cockpit docker fail2ban; do
    if systemctl is-installed "$service" &>/dev/null; then
        if ! systemctl is-active --quiet "$service"; then
            log "WARNING: Service $service is not running, attempting restart..."
            systemctl restart "$service" || log "ERROR: Failed to restart $service"
        fi
    fi
done

# 7. Мониторинг безопасности
log "Security monitoring..."
if command -v fail2ban-client &>/dev/null; then
    BANNED_IPS=$(fail2ban-client status sshd 2>/dev/null | grep -oP 'Currently banned:\s*\K\d+' || echo "0")
    log "fail2ban: $BANNED_IPS IPs currently banned"
fi

# 8. Создание отчета
REPORT_FILE="/var/log/maintenance-report-$(date +%Y%m%d).txt"
cat > "$REPORT_FILE" <<EOF
VPS Maintenance Report - $(date)
Domain: $DOMAIN
Disk Usage: ${DISK_USAGE}%
Memory Usage: $(free | awk 'NR==2{printf "%.1f%%", $3*100/$2 }')
Uptime: $(uptime -p)

Services Status:
EOF

for service in nginx cockpit docker fail2ban; do
    if systemctl is-installed "$service" &>/dev/null; then
        echo "$service: $(systemctl is-active "$service")" >> "$REPORT_FILE"
    fi
done

log "=== VPS Maintenance Completed ==="
log "Report saved: $REPORT_FILE"