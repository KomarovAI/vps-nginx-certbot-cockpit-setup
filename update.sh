#!/bin/bash

# Скрипт обновления VPS окружения
# Обновляет систему, SSL сертификаты и перезапускает службы

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   error "Скрипт должен быть запущен от root пользователя"
   exit 1
fi

log "Начало обновления VPS окружения..."

# Обновление системы
log "Обновление пакетов Ubuntu..."
apt update && apt upgrade -y
if [ $? -eq 0 ]; then
    log "Пакеты успешно обновлены"
else
    error "Ошибка обновления пакетов"
    exit 1
fi

# Обновление snap пакетов
log "Обновление snap пакетов..."
snap refresh

# Обновление SSL сертификатов
log "Проверка и обновление SSL сертификатов..."
if command -v certbot &> /dev/null; then
    certbot renew --quiet
    if [ $? -eq 0 ]; then
        log "SSL сертификаты проверены/обновлены"
    else
        warning "Ошибка при обновлении SSL сертификатов"
    fi
else
    warning "Certbot не установлен"
fi

# Проверка конфигурации Nginx
log "Проверка конфигурации Nginx..."
nginx -t
if [ $? -eq 0 ]; then
    log "Конфигурация Nginx корректна"
else
    error "Ошибка в конфигурации Nginx!"
    exit 1
fi

# Перезапуск служб
log "Перезапуск служб..."

# Перезагрузка Nginx
systemctl reload nginx
if [ $? -eq 0 ]; then
    log "Nginx перезагружен"
else
    warning "Ошибка перезагрузки Nginx"
fi

# Перезапуск Cockpit
systemctl restart cockpit
if [ $? -eq 0 ]; then
    log "Cockpit перезапущен"
else
    warning "Ошибка перезапуска Cockpit"
fi

# Очистка ненужных пакетов
log "Очистка ненужных пакетов..."
apt autoremove -y
apt autoclean

# Проверка статуса всех служб
log "Проверка статуса служб..."
if [ -f "/root/check-services.sh" ]; then
    /root/check-services.sh
else
    # Базовая проверка
    echo "=== Статус служб ==="
    systemctl status nginx --no-pager -l | head -5
    echo ""
    systemctl status cockpit --no-pager -l | head -5
    echo ""
    echo "=== Открытые порты ==="
    ss -tlnp | grep -E ':(80|443|9090)'
fi

# Обновление времени на странице
if [ -f "/var/www/botinger789298.work.gd/index.html" ]; then
    log "Обновление времени на сайте..."
    sed -i "s/Дата установки:.*</Обновлено: $(date '+%B %d, %Y, %H:%M MSK')</g" /var/www/botinger789298.work.gd/index.html
fi

log "✅ Обновление завершено успешно!"
log ""
log "📋 Сводка обновления:"
log "• Пакеты Ubuntu: Обновлены"
log "• SSL сертификаты: Проверены"
log "• Nginx: Перезагружен"
log "• Cockpit: Перезапущен"
log "• Время обновления: $(date '+%Y-%m-%d %H:%M:%S')"
log ""
log "🌐 Сервисы доступны по адресам:"
log "• Сайт: https://botinger789298.work.gd"
log "• Cockpit: https://botinger789298.work.gd:9090"