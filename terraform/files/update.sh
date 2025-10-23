#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

if [[ $EUID -ne 0 ]]; then
   error "Скрипт должен быть запущен от root пользователя"
   exit 1
fi

log "Начало обновления VPS окружения..."

log "Обновление пакетов Ubuntu..."
apt update && apt upgrade -y || { error "Ошибка обновления пакетов"; exit 1; }

log "Обновление snap пакетов..."
snap refresh || warning "Ошибка обновления snap пакетов"

log "Проверка и обновление SSL сертификатов..."
if command -v certbot &> /dev/null; then
    certbot renew --quiet || warning "Ошибка при обновлении SSL сертификатов"
else
    warning "Certbot не установлен"
fi

log "Проверка конфигурации Nginx..."
nginx -t || { error "Ошибка в конфигурации Nginx!"; exit 1; }

log "Перезагрузка Nginx и Cockpit..."
systemctl reload nginx || warning "Ошибка перезагрузки Nginx"
systemctl restart cockpit || warning "Ошибка перезапуска Cockpit"

log "Очистка ненужных пакетов..."
apt autoremove -y || true
apt autoclean || true

log "Проверка статуса служб..."
if [ -f "/root/check-services.sh" ]; then
    /root/check-services.sh
fi

log "✅ Обновление завершено успешно!"