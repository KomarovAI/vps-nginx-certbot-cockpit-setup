#!/bin/bash

# Конфигурация (читаем из env/секретов, с дефолтами для локального запуска)
DOMAIN="${DOMAIN_NAME:-example.com}"
EMAIL="${ADMIN_EMAIL:-admin@example.com}"
IP="${VPS_IP:-127.0.0.1}"
COCKPIT_USER="${COCKPIT_USER:-cockpit-admin}"
COCKPIT_PASSWORD="${COCKPIT_PASSWORD:-}"

# Валидация обязательных параметров
if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo "[ERROR] Не заданы DOMAIN_NAME и/или ADMIN_EMAIL (секреты/переменные окружения)" >&2
  exit 1
fi

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}" >&2; }
warning() { echo -e "${YELLOW}[WARNING] $1${NC}"; }

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
cat > /etc/nginx/sites-available/$DOMAIN << NGINX_CONF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    root /var/www/${DOMAIN};
    index index.html index.htm;

    access_log /var/log/nginx/${DOMAIN}.access.log;
    error_log /var/log/nginx/${DOMAIN}.error.log;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Для Let's Encrypt
    location ~ /.well-known/acme-challenge {
        allow all;
        root /var/www/${DOMAIN};
    }
}
NGINX_CONF

# Создание директории для сайта
mkdir -p /var/www/$DOMAIN
chown -R www-data:www-data /var/www/$DOMAIN

# Создание простой страницы
cat > /var/www/$DOMAIN/index.html << HTML
<!DOCTYPE html>
<html>
<head>
    <title>${DOMAIN}</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 100px; }
        .container { max-width: 600px; margin: 0 auto; }
        .success { color: #28a745; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="success">✅ Сервер успешно настроен!</h1>
        <h2>${DOMAIN}</h2>
        <p>Nginx, SSL и Cockpit установлены и настроены</p>
        <p>Дата установки: $(date)</p>
        <hr>
        <p><a href="https://${DOMAIN}:9090">Панель управления Cockpit</a></p>
    </div>
</body>
</html>
HTML

# Активация сайта
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации Nginx
nginx -t && systemctl reload nginx || { error "Ошибка в конфигурации Nginx"; exit 1; }

# Установка Certbot
log "Установка Certbot..."
snap install core
snap refresh core
apt remove -y certbot || true
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

# Получение SSL сертификата
log "Получение SSL сертификата для $DOMAIN..."
certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --email "$EMAIL" --agree-tos --no-eff-email --redirect

# Настройка автообновления сертификата
log "Настройка автообновления SSL сертификата..."
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -

# Установка Cockpit
log "Установка Cockpit..."
apt install -y cockpit cockpit-machines cockpit-podman cockpit-networkmanager
systemctl enable --now cockpit.socket

# Создание пользователя для Cockpit (если нужно)
if ! id -u "$COCKPIT_USER" &>/dev/null; then
    log "Создание пользователя $COCKPIT_USER..."
    useradd -m -s /bin/bash "$COCKPIT_USER"
    usermod -aG sudo "$COCKPIT_USER"
    if [[ -n "$COCKPIT_PASSWORD" ]]; then
      echo "$COCKPIT_USER:$COCKPIT_PASSWORD" | chpasswd
      log "Пароль для $COCKPIT_USER установлен из переменной окружения"
    else
      warning "Пароль для $COCKPIT_USER не задан. Установите вручную: passwd $COCKPIT_USER"
    fi
fi

# Перезапуск служб
systemctl restart nginx
systemctl restart cockpit || true

# Скрипт проверки статуса
cat > /root/check-services.sh << 'CHECK_SCRIPT'
#!/bin/bash
systemctl status nginx --no-pager -l
systemctl status cockpit --no-pager -l
certbot certificates
ss -tlnp | grep -E ':(80|443|9090)'
CHECK_SCRIPT
chmod +x /root/check-services.sh

log "✅ Установка завершена успешно!"
log "• Домен: $DOMAIN"
log "• IP адрес: $IP"
log "• Cockpit: https://$DOMAIN:9090"
