#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%F %T')] $*${NC}"; }
err() { echo -e "${RED}[ERROR] $*${NC}" >&2; }
warn() { echo -e "${YELLOW}[WARNING] $*${NC}"; }

if [[ $EUID -ne 0 ]]; then
    err "Скрипт должен быть запущен с правами root"; exit 1
fi

log "=== Настройка оптимизации памяти ==="
log "Цель: zram 1GB + swap 4GB (расширение с 1.5GB)"

apt update
apt install -y zram-tools

log "Настройка zram на 1GB..."
cat > /etc/default/zramswap <<'ZRAM'
# Размер zram в MB
ALLOCATION=1024
# Процент использования RAM для zram (50%)
PERCENT=50
# Приоритет (выше чем у обычного swap)
PRIORITY=100
ZRAM

log "Проверка текущего swap..."
SWAP_FILE="/swap.img"
CURRENT_SWAP_SIZE=$(swapon --show=SIZE --noheadings --bytes 2>/dev/null | head -1 | awk '{print $1}')

if [[ -z "$CURRENT_SWAP_SIZE" ]]; then
    warn "Swap не найден, создается новый..."
    CURRENT_SWAP_SIZE=0
else
    log "Текущий swap: $(numfmt --to=iec $CURRENT_SWAP_SIZE)"
fi

TARGET_SWAP_SIZE=$((4 * 1024 * 1024 * 1024))

if [[ "$CURRENT_SWAP_SIZE" -lt "$TARGET_SWAP_SIZE" ]]; then
  log "Расширение swap файла до 4GB..."
  if swapon --show | grep -q "$SWAP_FILE"; then swapoff "$SWAP_FILE" || true; fi
  dd if=/dev/zero of="$SWAP_FILE" bs=1M count=4096 status=progress
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE"
  swapon "$SWAP_FILE"
  if ! grep -q "$SWAP_FILE" /etc/fstab; then
      echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
  fi
else
  log "Swap уже >= 4GB, пропускаем"
fi

log "Запуск zram..."
systemctl restart zramswap || warn "zramswap мог не установиться"

log "Настройка swappiness..."
echo "vm.swappiness=10" > /etc/sysctl.d/99-swappiness.conf
sysctl -p /etc/sysctl.d/99-swappiness.conf || true

log "=== Проверка результатов ==="
free -h || true
swapon --show || true
lsblk | grep zram || log "zram еще не активен (перезагрузите систему)"

log "✅ Настройка памяти завершена!"