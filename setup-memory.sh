#!/bin/bash
set -euo pipefail

# Цвета для логов
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%F %T')] $*${NC}"; }
err() { echo -e "${RED}[ERROR] $*${NC}" >&2; }
warn() { echo -e "${YELLOW}[WARNING] $*${NC}"; }

# Проверка root прав
if [[ $EUID -ne 0 ]]; then
    err "Скрипт должен быть запущен с правами root"
    exit 1
fi

log "=== Настройка оптимизации памяти ==="
log "Цель: zram 1GB + swap 4GB (расширение с 1.5GB)"

# 1. Установка zram-tools
log "Установка zram-tools..."
apt update
apt install -y zram-tools

# 2. Настройка zram на 1GB
log "Настройка zram на 1GB..."
cat > /etc/default/zramswap <<'ZRAM'
# Размер zram в процентах от RAM (будет 1GB)
ALLOCATION=1024
# Процент использования RAM для zram (50%)
PERCENT=50
# Приоритет (выше чем у обычного swap)
PRIORITY=100
ZRAM

# 3. Проверка текущего swap
log "Проверка текущего swap..."
SWAP_FILE="/swap.img"
CURRENT_SWAP_SIZE=$(swapon --show=SIZE --noheadings --bytes 2>/dev/null | head -1 | awk '{print $1}')

if [[ -z "$CURRENT_SWAP_SIZE" ]]; then
    warn "Swap не найден, создается новый..."
    CURRENT_SWAP_SIZE=0
else
    log "Текущий swap: $(numfmt --to=iec $CURRENT_SWAP_SIZE)"
fi

# 4. Расширение swap до 4GB
TARGET_SWAP_SIZE=$((4 * 1024 * 1024 * 1024))  # 4GB в байтах

log "Расширение swap файла до 4GB..."

# Отключаем текущий swap
if swapon --show | grep -q "$SWAP_FILE"; then
    log "Отключение текущего swap..."
    swapoff "$SWAP_FILE"
fi

# Создаем новый swap файл 4GB
log "Создание нового swap файла 4GB..."
dd if=/dev/zero of="$SWAP_FILE" bs=1M count=4096 status=progress
chmod 600 "$SWAP_FILE"
mkswap "$SWAP_FILE"
swapon "$SWAP_FILE"

# Добавляем в fstab если еще нет
if ! grep -q "$SWAP_FILE" /etc/fstab; then
    log "Добавление swap в /etc/fstab..."
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
fi

# 5. Запуск zram
log "Запуск zram..."
systemctl restart zramswap

# 6. Настройка swappiness (приоритет использования swap)
log "Настройка swappiness..."
echo "vm.swappiness=10" > /etc/sysctl.d/99-swappiness.conf
sysctl -p /etc/sysctl.d/99-swappiness.conf

# 7. Проверка результатов
log "=== Проверка результатов ==="
echo ""
log "Память:"
free -h
echo ""
log "Swap устройства:"
swapon --show
echo ""
log "Zram устройства:"
lsblk | grep zram || log "zram еще не активен (перезагрузите систему)"
echo ""

log "✅ Настройка памяти завершена!"
log "📊 Итог: zram ~1GB (приоритет 100) + swap 4GB (приоритет -2)"
log "💡 Для полной активации zram рекомендуется перезагрузить систему"
log "   Команда: reboot"
