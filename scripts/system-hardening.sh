#!/bin/bash

#===============================================================================
# System Hardening Script for VPS
# Дополнительное укрепление безопасности системы
#===============================================================================

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

log "=== System Hardening Started ==="

# Отключение ненужных сервисов
log "Disabling unnecessary services..."
services_to_disable=("cups" "avahi-daemon" "bluetooth" "ModemManager")
for service in "${services_to_disable[@]}"; do
    if systemctl is-enabled "$service" &>/dev/null; then
        systemctl disable "$service"
        systemctl stop "$service"
        log "Disabled $service"
    fi
done

# Настройка kernel параметров безопасности
log "Applying kernel security parameters..."
cat > /etc/sysctl.d/99-security.conf <<EOF
# Network security
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.default.secure_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.default.log_martians=1
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_syn_retries=5

# File system security
fs.suid_dumpable=0
kernel.dmesg_restrict=1
kernel.kptr_restrict=1
kernel.yama.ptrace_scope=1

# Memory protection
kernel.randomize_va_space=2
EOF

sysctl -p /etc/sysctl.d/99-security.conf

# Настройка SSH безопасности
log "Hardening SSH configuration..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Дополнительные SSH настройки безопасности
cat >> /etc/ssh/sshd_config <<EOF

# Additional security settings
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxStartups 10:30:60
LoginGraceTime 30
PermitEmptyPasswords no
X11Forwarding no
AllowTcpForwarding no
Protocol 2
EOF

systemctl restart ssh

log "=== System Hardening Completed ==="
log "Review /etc/sysctl.d/99-security.conf and /etc/ssh/sshd_config for applied changes"