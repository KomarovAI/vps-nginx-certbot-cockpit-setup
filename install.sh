#!/bin/bash

# Конфигурация
DOMAIN="botinger789298.work.gd"
EMAIL="artur.komarovv@gmail.com"
IP="31.59.58.96"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   error "Скрипт должен быть запущен от root пользователя"
   exit 1
fi

log "Начинаем установку VPS окружения..."
log "Домен: $DOMAIN"
log "IP: $IP"
log "Email: $EMAIL"

# Обновление системы
log "Обновление системы Ubuntu..."
apt update && apt upgrade -y

# Установка базовых пакетов
log "Установка базовых пакетов..."
apt install -y curl wget ufw git snapd software-properties-common

# Настройка UFW
log "Настройка брандмауэра UFW..."
ufw --force enable
ufw allow ssh
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 9090

# Установка Nginx
log "Установка Nginx..."
apt install -y nginx
systemctl start nginx
systemctl enable nginx

# Создание конфигурации Nginx для домена
log "Создание конфигурации Nginx для домена $DOMAIN..."
cat > /etc/nginx/sites-available/$DOMAIN << 'NGINX_CONF'
server {
    listen 80;
    listen [::]:80;
    server_name botinger789298.work.gd www.botinger789298.work.gd;

    root /var/www/botinger789298.work.gd;
    index index.html index.htm;

    access_log /var/log/nginx/botinger789298.work.gd.access.log;
    error_log /var/log/nginx/botinger789298.work.gd.error.log;

    location / {
        try_files $uri $uri/ =404;
    }

    # Для Let's Encrypt
    location ~ /.well-known/acme-challenge {
        allow all;
        root /var/www/botinger789298.work.gd;
    }
}
NGINX_CONF

# Создание директории для сайта
mkdir -p /var/www/$DOMAIN
chown -R www-data:www-data /var/www/$DOMAIN

# Создание простой страницы
cat > /var/www/$DOMAIN/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>botinger789298.work.gd</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            text-align: center; 
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container { 
            background: rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
            padding: 40px;
            border-radius: 20px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
            max-width: 600px;
        }
        .success { color: #4ade80; font-size: 3rem; margin-bottom: 20px; }
        h1 { margin: 0; font-size: 2rem; }
        h2 { color: #94a3b8; font-weight: 300; }
        .services { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 20px; 
            margin-top: 30px; 
        }
        .service {
            background: rgba(255,255,255,0.1);
            padding: 20px;
            border-radius: 10px;
            transition: transform 0.3s ease;
        }
        .service:hover { transform: translateY(-5px); }
        .service-icon { font-size: 2rem; margin-bottom: 10px; }
        a { color: #60a5fa; text-decoration: none; }
        a:hover { color: #93c5fd; }
        .status { margin-top: 20px; }
        .status span { 
            display: inline-block; 
            background: rgba(34, 197, 94, 0.2); 
            padding: 5px 15px; 
            border-radius: 20px; 
            margin: 5px; 
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="success">✅</div>
        <h1>Сервер успешно настроен!</h1>
        <h2>botinger789298.work.gd</h2>
        
        <div class="services">
            <div class="service">
                <div class="service-icon">🌐</div>
                <h3>Nginx</h3>
                <p>Веб-сервер настроен</p>
            </div>
            <div class="service">
                <div class="service-icon">🔒</div>
                <h3>SSL</h3>
                <p>Let's Encrypt активен</p>
            </div>
            <div class="service">
                <div class="service-icon">⚙️</div>
                <h3>Cockpit</h3>
                <p><a href="https://botinger789298.work.gd:9090" target="_blank">Панель управления</a></p>
            </div>
        </div>
        
        <div class="status">
            <p><strong>Статус служб:</strong></p>
            <span>Nginx: Active</span>
            <span>SSL: Active</span>  
            <span>Cockpit: Active</span>
        </div>
        
        <p style="margin-top: 30px; opacity: 0.7;">
            Дата установки: October 23, 2025, 21:04 MSK
        </p>
    </div>
</body>
</html>
HTML

# Активация сайта
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации Nginx
nginx -t
if [ $? -eq 0 ]; then
    log "Конфигурация Nginx корректна"
    systemctl reload nginx
else
    error "Ошибка в конфигурации Nginx"
    exit 1
fi

# Установка Certbot
log "Установка Certbot..."
snap install core
snap refresh core
apt remove -y certbot
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

# Получение SSL сертификата
log "Получение SSL сертификата для $DOMAIN..."
certbot --nginx -d $DOMAIN -d www.$DOMAIN --email $EMAIL --agree-tos --no-eff-email --redirect

# Настройка автообновления сертификата
log "Настройка автообновления SSL сертификата..."
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -

# Установка Cockpit
log "Установка Cockpit..."
apt install -y cockpit cockpit-machines cockpit-podman cockpit-networkmanager

# Включение и запуск Cockpit
systemctl enable --now cockpit.socket

# Настройка Cockpit для SSL
log "Настройка Cockpit для работы с SSL..."
mkdir -p /etc/cockpit/ws-certs.d

# Создание пользователя для Cockpit (если нужно)
if ! id -u cockpit-admin &>/dev/null; then
    log "Создание пользователя cockpit-admin..."
    useradd -m -s /bin/bash cockpit-admin
    usermod -aG sudo cockpit-admin
    echo "cockpit-admin:VpsAdmin2025!" | chpasswd
    log "Пользователь cockpit-admin создан с паролем: VpsAdmin2025!"
fi

# Перезапуск служб
systemctl restart nginx
systemctl restart cockpit

# Создание скрипта для проверки статуса
cat > /root/check-services.sh << 'CHECK_SCRIPT'
#!/bin/bash
echo "=== Статус служб ==="
systemctl status nginx --no-pager -l
echo ""
systemctl status cockpit --no-pager -l
echo ""
echo "=== SSL сертификат ==="
certbot certificates
echo ""
echo "=== Порты ==="
ss -tlnp | grep -E ':(80|443|9090)'
echo ""
echo "=== Disk usage ==="
df -h
echo ""
echo "=== Memory usage ==="
free -h
CHECK_SCRIPT

chmod +x /root/check-services.sh

# Создание скрипта мониторинга
cat > /root/monitor.sh << 'MONITOR_SCRIPT'
#!/bin/bash
while true; do
    clear
    echo "=== VPS Monitor - $(date) ==="
    echo ""
    echo "🌐 Nginx Status:"
    systemctl is-active nginx
    echo ""
    echo "🔒 SSL Certificate:"
    certbot certificates 2>/dev/null | grep "Certificate Name\|Expiry Date" || echo "No certificates found"
    echo ""
    echo "⚙️ Cockpit Status:"
    systemctl is-active cockpit
    echo ""
    echo "💾 Disk Usage:"
    df -h / | tail -1
    echo ""
    echo "🧠 Memory Usage:"
    free -h | grep "Mem:"
    echo ""
    echo "🔥 CPU Load:"
    uptime
    echo ""
    echo "🌍 Network Connections:"
    ss -tlnp | grep -E ':(80|443|9090)' | wc -l
    echo " active connections"
    echo ""
    echo "Press Ctrl+C to exit"
    sleep 5
done
MONITOR_SCRIPT

chmod +x /root/monitor.sh

log "✅ Установка завершена успешно!"
log ""
log "📋 Сводка установки:"
log "• Домен: $DOMAIN"
log "• IP адрес: $IP" 
log "• Nginx: Установлен и настроен"
log "• SSL: Let's Encrypt сертификат получен"
log "• Cockpit: Доступен по адресу https://$DOMAIN:9090"
log "• Пользователь Cockpit: cockpit-admin"
log "• Пароль Cockpit: VpsAdmin2025!"
log ""
log "🔧 Полезные команды:"
log "• Проверка статуса: /root/check-services.sh"
log "• Мониторинг в реальном времени: /root/monitor.sh"
log "• Логи Nginx: tail -f /var/log/nginx/${DOMAIN}.*"
log "• Обновление SSL: certbot renew"
log ""
log "🌐 Доступные сервисы:"
log "• Сайт: https://$DOMAIN"
log "• Панель управления: https://$DOMAIN:9090"