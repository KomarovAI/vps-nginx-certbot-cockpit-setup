#!/bin/bash

#===============================================================================
# VPS Memory Optimization Script v3.0
# Улучшенная настройка zram и swap для VPS серверов
# Исправлены все проблемы оригинальной версии
#===============================================================================

set -euo pipefail

# Константы
readonly SCRIPT_VERSION="3.0"
readonly LOGFILE="/var/log/memory-setup.log"
readonly ZRAM_SIZE_MB=1024  # 1GB
readonly SWAP_SIZE_MB=4096  # 4GB
readonly SWAP_FILE="/swap.img"

# Цвета только если TTY доступен
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
# Функции логирования
#===============================================================================

# Настройка логирования
setup_logging() {
    # Создаем лог файл если не существует
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
    log "ERROR" "Script failed at line $line_no with exit code $exit_code"
    exit "$exit_code"
}

trap 'error_exit $LINENO $?' ERR

#===============================================================================
# Проверки системы
#===============================================================================

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root"
        exit 1
    fi
}

# Проверка системных требований
check_system() {
    log "INFO" "Checking system requirements..."
    
    # Проверка доступной памяти
    local total_mem_mb
    total_mem_mb=$(free -m | awk 'NR==2{print $2}')
    
    if [[ $total_mem_mb -lt 512 ]]; then
        log "WARN" "Low system memory detected: ${total_mem_mb}MB. Recommended: 512MB+"
    fi
    
    # Проверка доступного дискового пространства для swap
    local available_space_mb
    available_space_mb=$(df / | awk 'NR==2 {print int($4/1024)}')
    
    if [[ $available_space_mb -lt $SWAP_SIZE_MB ]]; then
        log "ERROR" "Insufficient disk space for swap. Available: ${available_space_mb}MB, Required: ${SWAP_SIZE_MB}MB"
        exit 1
    fi
    
    log "INFO" "System requirements check passed"
    log "INFO" "Total RAM: ${total_mem_mb}MB"
    log "INFO" "Available disk space: ${available_space_mb}MB"
}

# Проверка существующих zram устройств
check_existing_zram() {
    log "INFO" "Checking existing zram devices..."
    
    if lsblk | grep -q zram; then
        log "INFO" "Found existing zram devices:"
        lsblk | grep zram || true
        
        # Отключаем существующие zram устройства
        for zram_dev in /dev/zram*; do
            if [[ -b "$zram_dev" ]] && swapon --show | grep -q "$zram_dev"; then
                log "INFO" "Disabling existing zram device: $zram_dev"
                swapoff "$zram_dev" 2>/dev/null || true
            fi
        done
    fi
}

#===============================================================================
# Установка и настройка zram
#===============================================================================

install_zram_tools() {
    log "INFO" "Installing zram-tools..."
    
    # Обновление списка пакетов
    apt update -q
    
    # Установка zram-tools с обработкой ошибок
    if apt install -y zram-tools; then
        log "INFO" "zram-tools installed successfully"
    else
        log "WARN" "Failed to install zram-tools package, trying manual setup"
        setup_zram_manually
        return
    fi
}

setup_zram_manually() {
    log "INFO" "Setting up zram manually..."
    
    # Загружаем модуль zram
    modprobe zram num_devices=1 2>/dev/null || {
        log "ERROR" "Failed to load zram kernel module"
        return 1
    }
    
    # Настраиваем размер и включаем
    if [[ -b /dev/zram0 ]]; then
        echo "${ZRAM_SIZE_MB}M" > /sys/block/zram0/disksize
        mkswap /dev/zram0
        swapon -p 100 /dev/zram0
        log "INFO" "Manual zram setup completed"
    else
        log "ERROR" "zram device not available"
        return 1
    fi
}

configure_zram() {
    log "INFO" "Configuring zram (${ZRAM_SIZE_MB}MB)..."
    
    # Остановка текущего zramswap сервиса если запущен
    systemctl stop zramswap 2>/dev/null || true
    
    # Конфигурация zram
    cat > /etc/default/zramswap <<EOF
# zram configuration - automatically generated by VPS setup v${SCRIPT_VERSION}
# Size in MB
ALLOCATION=${ZRAM_SIZE_MB}
# Percentage of RAM to use (calculated automatically)
PERCENT=50
# Priority (higher than regular swap)
PRIORITY=100
# Compression algorithm (lz4 is fastest)
ALGO=lz4
EOF
    
    # Включение и запуск zramswap
    systemctl enable zramswap
    systemctl restart zramswap
    
    # Проверка статуса
    if systemctl is-active --quiet zramswap; then
        log "INFO" "zramswap service is running"
    else
        log "WARN" "zramswap service failed to start, trying manual setup"
        setup_zram_manually
    fi
}

#===============================================================================
# Настройка обычного swap
#===============================================================================

setup_swap_file() {
    log "INFO" "Setting up swap file (${SWAP_SIZE_MB}MB)..."
    
    # Отключаем существующий swap если есть
    if swapon --show | grep -q "$SWAP_FILE"; then
        log "INFO" "Disabling existing swap file: $SWAP_FILE"
        swapoff "$SWAP_FILE"
    fi
    
    # Удаляем старый swap файл
    if [[ -f "$SWAP_FILE" ]]; then
        log "INFO" "Removing old swap file"
        rm -f "$SWAP_FILE"
    fi
    
    # Создание нового swap файла с прогрессом
    log "INFO" "Creating new swap file: $SWAP_FILE"
    
    # Используем fallocate если доступен (быстрее)
    if command -v fallocate &>/dev/null; then
        fallocate -l "${SWAP_SIZE_MB}M" "$SWAP_FILE"
    else
        dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=progress
    fi
    
    # Установка правильных прав доступа
    chmod 600 "$SWAP_FILE"
    
    # Создание и активация swap
    mkswap "$SWAP_FILE"
    swapon "$SWAP_FILE"
    
    # Добавление в fstab если еще нет
    if ! grep -q "$SWAP_FILE" /etc/fstab; then
        log "INFO" "Adding swap to /etc/fstab"
        echo "$SWAP_FILE none swap sw,pri=-1 0 0" >> /etc/fstab
    fi
    
    log "INFO" "Swap file setup completed"
}

#===============================================================================
# Оптимизация параметров памяти
#===============================================================================

optimize_memory_settings() {
    log "INFO" "Optimizing memory settings..."
    
    # Создание файла настроек sysctl
    cat > /etc/sysctl.d/99-memory-optimization.conf <<EOF
# Memory optimization settings - VPS setup v${SCRIPT_VERSION}

# Swappiness: как агрессивно использовать swap (0-100)
# 10 = использовать swap только при нехватке RAM
vm.swappiness=10

# Настройки кэша страниц
# vm.vfs_cache_pressure: давление на кэш VFS (по умолчанию 100)
vm.vfs_cache_pressure=50

# Настройки dirty pages (грязных страниц)
# vm.dirty_background_ratio: процент RAM для фонового сброса
vm.dirty_background_ratio=5
# vm.dirty_ratio: процент RAM до принудительного сброса
vm.dirty_ratio=10

# Настройки overcommit
# vm.overcommit_memory: политика выделения памяти (0=эвристика, 1=всегда, 2=строго)
vm.overcommit_memory=1
# vm.overcommit_ratio: процент RAM+swap для overcommit при режиме 2
vm.overcommit_ratio=50

# Настройки для zram
# vm.page-cluster: количество страниц читаемых за раз при page fault
vm.page-cluster=0
EOF
    
    # Применение настроек
    sysctl -p /etc/sysctl.d/99-memory-optimization.conf
    
    log "INFO" "Memory optimization settings applied"
}

#===============================================================================
# Функции мониторинга и отчетности
#===============================================================================

create_memory_monitoring() {
    log "INFO" "Creating memory monitoring script..."
    
    cat > /root/check-memory.sh <<'EOF'
#!/bin/bash

# Скрипт мониторинга памяти

echo "=== Memory Status Report ==="
echo "Date: $(date)"
echo

echo "=== RAM Usage ==="
free -h

echo
echo "=== Swap Devices ==="
swapon --show

echo  
echo "=== Swap Usage Summary ==="
swapon --show=NAME,SIZE,USED,PRIO --noheadings | while read name size used prio; do
    echo "Device: $name, Size: $size, Used: $used, Priority: $prio"
done

echo
echo "=== zram Devices ==="
if lsblk | grep -q zram; then
    lsblk | grep zram
    echo
    echo "zram Statistics:"
    for zram_dev in /sys/block/zram*; do
        if [[ -d "$zram_dev" ]]; then
            dev_name=$(basename "$zram_dev")
            if [[ -f "$zram_dev/disksize" && -f "$zram_dev/orig_data_size" && -f "$zram_dev/compr_data_size" ]]; then
                disksize=$(cat "$zram_dev/disksize" 2>/dev/null)
                orig_size=$(cat "$zram_dev/orig_data_size" 2>/dev/null)
                compr_size=$(cat "$zram_dev/compr_data_size" 2>/dev/null)
                
                if [[ $disksize -gt 0 ]]; then
                    echo "  $dev_name: Disk Size: $(numfmt --to=iec $disksize), Original: $(numfmt --to=iec $orig_size), Compressed: $(numfmt --to=iec $compr_size)"
                    if [[ $orig_size -gt 0 ]]; then
                        ratio=$(( (compr_size * 100) / orig_size ))
                        echo "    Compression Ratio: ${ratio}%"
                    fi
                fi
            fi
        fi
    done
else
    echo "No zram devices found"
fi

echo
echo "=== Memory Parameters ==="
echo "Swappiness: $(cat /proc/sys/vm/swappiness)"
echo "VFS Cache Pressure: $(cat /proc/sys/vm/vfs_cache_pressure)"
echo "Dirty Background Ratio: $(cat /proc/sys/vm/dirty_background_ratio)"
echo "Dirty Ratio: $(cat /proc/sys/vm/dirty_ratio)"

echo
echo "=== Process Memory Top 5 ==="
ps aux --sort=-%mem | head -6
EOF
    
    chmod +x /root/check-memory.sh
    
    log "INFO" "Memory monitoring script created: /root/check-memory.sh"
}

show_final_status() {
    log "INFO" "=== Memory Optimization Summary ==="
    
    echo
    log "INFO" "Memory configuration:"
    free -h
    
    echo
    log "INFO" "Swap devices:"
    swapon --show
    
    echo
    log "INFO" "zram devices:"
    lsblk | grep zram || log "INFO" "No zram devices active (may need system reboot)"
    
    echo
    log "INFO" "Memory parameters:"
    log "INFO" "  Swappiness: $(cat /proc/sys/vm/swappiness)"
    log "INFO" "  VFS Cache Pressure: $(cat /proc/sys/vm/vfs_cache_pressure)"
    
    echo
    log "INFO" "Configuration files created:"
    log "INFO" "  /etc/default/zramswap - zram configuration"
    log "INFO" "  /etc/sysctl.d/99-memory-optimization.conf - memory parameters"
    log "INFO" "  /root/check-memory.sh - memory monitoring script"
    
    echo
    log "INFO" "✅ Memory optimization completed successfully!"
    log "INFO" "📊 Summary: zram ${ZRAM_SIZE_MB}MB (priority 100) + swap ${SWAP_SIZE_MB}MB (priority -1)"
    log "INFO" "💡 For full zram activation, consider rebooting: 'reboot'"
    log "INFO" "📈 Monitor with: '/root/check-memory.sh'"
}

#===============================================================================
# Главная функция
#===============================================================================

main() {
    setup_logging
    
    log "INFO" "=== Memory Optimization Script v${SCRIPT_VERSION} ==="
    log "INFO" "Target: zram ${ZRAM_SIZE_MB}MB + swap ${SWAP_SIZE_MB}MB"
    
    # Выполнение проверок
    check_root
    check_system
    check_existing_zram
    
    # Установка и настройка zram
    install_zram_tools
    configure_zram
    
    # Настройка swap файла
    setup_swap_file
    
    # Оптимизация параметров системы
    optimize_memory_settings
    
    # Создание скриптов мониторинга
    create_memory_monitoring
    
    # Финальный отчет
    show_final_status
    
    log "INFO" "Memory optimization script completed at $(date)"
}

# Запуск основной функции
main "$@"