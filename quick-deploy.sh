#!/bin/bash

#===============================================================================
# Quick Deploy Script for VPS with Marzban
# Быстрый скрипт деплоя VPS с Marzban
#===============================================================================

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Логирование
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] $*${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING: $*${NC}"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $*${NC}"
    exit 1
}

# Проверка root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root. Use: sudo $0"
fi

echo -e "${BLUE}"
cat << "EOF"
╭──────────────────────────────────────────────────────────────────────╮
│                      VPS Quick Deploy v3.1                        │
│                   🚀 Nginx + SSL + Cockpit + Docker                │
│                        🔒 + Marzban VPN Server                     │
╰──────────────────────────────────────────────────────────────────────╯
EOF
echo -e "${NC}"

log "Starting VPS deployment..."

# Сбор параметров
echo
log "🌐 Настройка параметров"

read -p "Enter your domain name: " DOMAIN_NAME
if [[ -z "$DOMAIN_NAME" ]]; then
    error "Domain name is required"
fi

read -p "Enter admin email for SSL certificates: " ADMIN_EMAIL
if [[ -z "$ADMIN_EMAIL" ]]; then
    error "Admin email is required"
fi

# Cockpit password
read -s -p "Enter password for Cockpit admin user (optional): " COCKPIT_PASSWORD
echo

# Marzban deployment
echo
read -p "Deploy Marzban VPN server? (y/N): " DEPLOY_MARZBAN_INPUT
if [[ "$DEPLOY_MARZBAN_INPUT" =~ ^[Yy]$ ]]; then
    DEPLOY_MARZBAN="true"
    
    echo "🔒 Marzban configuration:"
    read -p "Marzban panel port (default: 8000): " MARZBAN_PANEL_PORT
    MARZBAN_PANEL_PORT=${MARZBAN_PANEL_PORT:-8000}
    
    read -p "Xray VLESS port (default: 2083): " XRAY_PORT
    XRAY_PORT=${XRAY_PORT:-2083}
else
    DEPLOY_MARZBAN="false"
fi

# Подтверждение
echo
log "⚙️ Configuration summary:"
echo "   Domain: $DOMAIN_NAME"
echo "   Email: $ADMIN_EMAIL"
echo "   Cockpit password: ${COCKPIT_PASSWORD:+Set}"
if [[ "$DEPLOY_MARZBAN" == "true" ]]; then
    echo "   Marzban: ENABLED"
    echo "   Marzban panel port: $MARZBAN_PANEL_PORT"
    echo "   Xray port: $XRAY_PORT"
else
    echo "   Marzban: DISABLED"
fi

echo
read -p "Continue with deployment? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    log "Deployment cancelled"
    exit 0
fi

# Получение IP адреса сервера
log "📍 Detecting server IP..."
VPS_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "unknown")
log "Server IP: $VPS_IP"

# DNS проверка
log "🔍 Checking DNS configuration..."
RESOLVED_IP=$(dig +short "$DOMAIN_NAME" @8.8.8.8 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

if [[ -z "$RESOLVED_IP" ]]; then
    warn "Domain $DOMAIN_NAME does not resolve to any IP"
    warn "Please ensure your domain's A record points to: $VPS_IP"
    read -p "Continue anyway? (y/N): " CONTINUE_DNS
    if [[ ! "$CONTINUE_DNS" =~ ^[Yy]$ ]]; then
        error "Please configure DNS first"
    fi
elif [[ "$RESOLVED_IP" != "$VPS_IP" && "$VPS_IP" != "unknown" ]]; then
    warn "DNS mismatch: $DOMAIN_NAME resolves to $RESOLVED_IP, but server IP is $VPS_IP"
    read -p "Continue anyway? (y/N): " CONTINUE_DNS
    if [[ ! "$CONTINUE_DNS" =~ ^[Yy]$ ]]; then
        error "Please fix DNS configuration first"
    fi
else
    log "DNS verification passed: $DOMAIN_NAME -> $RESOLVED_IP"
fi

# Скачивание и запуск основного скрипта
log "📦 Downloading main installation script..."

INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/install.sh"

# Скачивание скрипта
if ! curl -fsSL "$INSTALL_SCRIPT_URL" -o /tmp/install.sh; then
    error "Failed to download installation script"
fi

chmod +x /tmp/install.sh

# Подготовка переменных окружения
export DOMAIN_NAME
export ADMIN_EMAIL
export VPS_IP
export DEPLOY_MARZBAN

if [[ -n "$COCKPIT_PASSWORD" ]]; then
    export COCKPIT_PASSWORD
fi

if [[ "$DEPLOY_MARZBAN" == "true" ]]; then
    export MARZBAN_PANEL_PORT
    export XRAY_PORT
fi

log "⚙️ Starting main installation..."
echo "================================================================================="

# Запуск основного скрипта
/tmp/install.sh

# Результат
echo "================================================================================="
log "✅ VPS deployment completed successfully!"
echo
log "🌐 Services:"
echo "   Website: https://$DOMAIN_NAME"
echo "   Cockpit: https://$DOMAIN_NAME:9090"

if [[ "$DEPLOY_MARZBAN" == "true" ]]; then
    echo "   Marzban Panel: https://$DOMAIN_NAME:$MARZBAN_PANEL_PORT"
    echo
    log "🔒 Marzban Management:"
    echo "   Start: /root/marzban-manage.sh start"
    echo "   Stop: /root/marzban-manage.sh stop"
    echo "   Logs: /root/marzban-manage.sh logs"
    echo "   Status: /root/marzban-manage.sh status"
fi

echo
log "📊 Monitoring:"
echo "   Service check: /root/check-services.sh"

echo
log "📋 Next steps:"
echo "1. 🌐 Visit https://$DOMAIN_NAME to verify website"
echo "2. 🖥️ Login to Cockpit at https://$DOMAIN_NAME:9090"
if [[ "$DEPLOY_MARZBAN" == "true" ]]; then
    echo "3. 🔒 Configure Marzban at https://$DOMAIN_NAME:$MARZBAN_PANEL_PORT"
    echo "4. ⚙️ Check Marzban status: /root/marzban-manage.sh status"
fi
echo
log "✅ All done! Your VPS is ready to use."

# Очистка
rm -f /tmp/install.sh

exit 0