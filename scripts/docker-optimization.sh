#!/bin/bash

#===============================================================================
# Docker Optimization Script for VPS
# Оптимизация Docker для production среды
#===============================================================================

set -euo pipefail

# Константы
readonly LOGFILE="/var/log/docker-optimization.log"

# Логирование
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "=== Docker Optimization Started ==="

# Оптимизация Docker daemon
log "Optimizing Docker daemon configuration..."
mkdir -p /etc/docker

cat > /etc/docker/daemon.json <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ],
    "live-restore": true,
    "userland-proxy": false,
    "no-new-privileges": true,
    "icc": false,
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 64000,
            "Soft": 64000
        }
    }
}
EOF

# Перезапуск Docker
log "Restarting Docker with new configuration..."
systemctl restart docker

# Очистка Docker
log "Cleaning up Docker resources..."
docker system prune -f
docker volume prune -f
docker network prune -f

log "=== Docker Optimization Completed ==="