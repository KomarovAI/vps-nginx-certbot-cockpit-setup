# 🚀 VPS Setup: Nginx + Certbot SSL + Cockpit

**Автоматическая настройка VPS (Ubuntu 22.04) с Nginx, SSL (Let's Encrypt) и Cockpit. Все чувствительные данные передаются через GitHub Secrets/ENV. В коде нет хардкодов.**

![VPS Setup](https://img.shields.io/badge/VPS-Ubuntu%2022.04-orange)
![Nginx](https://img.shields.io/badge/Nginx-Latest-green)
![SSL](https://img.shields.io/badge/SSL-Let's%20Encrypt-blue)
![Cockpit](https://img.shields.io/badge/Cockpit-Web%20Console-red)
![Security](https://img.shields.io/badge/Security-No%20Hardcodes-brightgreen)

---

## 🎯 Конфигурация через GitHub Secrets

**В настройках репозитория добавьте следующие секреты:**

| Секрет | Описание | Пример |
|--------|----------|---------|
| `DOMAIN_NAME` | Ваш домен | `example.com` |
| `ADMIN_EMAIL` | Email администратора | `admin@example.com` |
| `VPS_HOST` | IP или хост VPS | `1.2.3.4` |
| `VPS_USER` | SSH пользователь | `root` или `ubuntu` |
| `SSH_PRIVATE_KEY` | Приватный SSH ключ | Содержимое `~/.ssh/deploy_key` |
| `VPS_IP` | IP VPS (для логов) | `1.2.3.4` |
| `COCKPIT_PASSWORD` | Пароль Cockpit (опционально) | `StrongPassword123!` |

---

## ⚡ Быстрый старт

### 🔥 Установка одной командой

```bash
# Загружаем и запускаем (нужны переменные окружения!)
curl -s https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/install.sh | sudo bash
```

⚠️ **Важно:** Перед запуском установите переменные окружения или скрипт завершится с ошибкой.

### 📦 Локальная установка с переменными

```bash
# Клонируем репозиторий
git clone https://github.com/KomarovAI/vps-nginx-certbot-cockpit-setup.git
cd vps-nginx-certbot-cockpit-setup

# ОБЯЗАТЕЛЬНО: устанавливаем переменные окружения
export DOMAIN_NAME="your-domain.com"
export ADMIN_EMAIL="your-email@example.com"
export VPS_IP="your-vps-ip"
export COCKPIT_PASSWORD="YourStrongPassword"  # опционально

# Запускаем с сохранением переменных
sudo chmod +x install.sh
sudo -E ./install.sh
```

---

## 🤖 Автоматический деплой (GitHub Actions)

### 1️⃣ Настройка SSH ключей на VPS

```bash
# Генерируем SSH ключи
ssh-keygen -t rsa -b 4096 -f ~/.ssh/deploy_key -N ""

# Добавляем публичный ключ в authorized_keys
cat ~/.ssh/deploy_key.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Показываем приватный ключ (скопируйте в GitHub Secret SSH_PRIVATE_KEY)
cat ~/.ssh/deploy_key
```

### 2️⃣ Добавление GitHub Secrets

1. Перейдите в **Settings** → **Secrets and variables** → **Actions**
2. Нажмите **New repository secret**
3. Добавьте все секреты из таблицы выше

### 3️⃣ Запуск автоматического деплоя

**Автоматически:**
- Любой push в ветку `main` запускает деплой

**Вручную:**
- **Actions** → **Deploy to VPS** → **Run workflow**

---

## 📊 Что устанавливается

| Компонент | Описание | Статус |
|-----------|----------|--------|
| ✅ **Nginx** | Веб-сервер с автоконфигурацией | Установлен |
| ✅ **Let's Encrypt SSL** | Бесплатный SSL с автообновлением | Настроен |
| ✅ **Cockpit** | Веб-панель управления сервером | Активен |
| ✅ **UFW Firewall** | Настроенный брандмауэр | Включен |
| ✅ **Memory Optimization** | Zram 1GB + Swap 4GB для оптимизации памяти | Настроено |
| ✅ **Auto-renewal** | Автообновление SSL сертификатов | Настроено |

---

## 🌐 Доступ к сервисам

После установки будут доступны:

| Сервис | URL | Описание |
|--------|-----|----------|
| **Веб-сайт** | `https://YOUR-DOMAIN` | Главная страница |
| **Cockpit** | `https://YOUR-DOMAIN:9090` | Панель управления |
| **HTTP→HTTPS** | `http://YOUR-DOMAIN` | Автоматический редирект |

### 🔐 Данные для входа в Cockpit

- **Пользователь:** `cockpit-admin`
- **Пароль:** Из переменной `COCKPIT_PASSWORD` или установите вручную: `passwd cockpit-admin`

---

## 🔐 Безопасность

### ✅ Что защищено:
- **Нет хардкодов** доменов, IP-адресов, паролей в репозитории
- **Все чувствительные данные** в GitHub Secrets/ENV
- **Принудительный HTTPS** (автоматический редирект)
- **UFW брандмауэр** с минимально необходимыми портами
- **Автоматическое обновление** SSL сертификатов

### 🚪 Открытые порты:
- `22` - SSH
- `80` - HTTP (редирект на HTTPS)
- `443` - HTTPS
- `9090` - Cockpit

---

## 🔧 Полезные команды

### 📈 Мониторинг и диагностика

```bash
# Полная проверка всех служб
/root/check-services.sh

# Мониторинг в реальном времени
/root/monitor.sh

# Статус служб
sudo systemctl status nginx cockpit --no-pager

# Проверка SSL сертификата
sudo certbot certificates
sudo certbot renew --dry-run

# Открытые порты
sudo ss -tlnp | grep -E ':(80|443|9090)'
```

### 📝 Логи

```bash
# Логи Nginx (замените YOUR-DOMAIN на ваш домен)
sudo tail -f /var/log/nginx/YOUR-DOMAIN.access.log
sudo tail -f /var/log/nginx/YOUR-DOMAIN.error.log

# Логи Cockpit
sudo journalctl -u cockpit -f

# Системные логи
sudo journalctl -f
```

### 🔄 Обновления

```bash
# Обновление системы и SSL
sudo ./update.sh  # если скрипт существует

# Ручное обновление SSL
sudo certbot renew

# Перезапуск служб
sudo systemctl reload nginx
sudo systemctl restart cockpit
```

---

## 🆘 Устранение неполадок

### ❌ Переменные окружения не переданы

```bash
# Проверьте переменные перед запуском
echo "DOMAIN_NAME: $DOMAIN_NAME"
echo "ADMIN_EMAIL: $ADMIN_EMAIL"

# Используйте sudo -E для сохранения переменных
sudo -E ./install.sh
```

### ❌ Nginx не запускается

```bash
sudo nginx -t
sudo systemctl status nginx
sudo systemctl restart nginx
```

### ❌ SSL сертификат не работает

```bash
# Проверка DNS (домен должен указывать на VPS)
nslookup YOUR-DOMAIN
dig YOUR-DOMAIN

# Принудительное обновление сертификата
sudo certbot renew --force-renewal
```

### ❌ Cockpit недоступен

```bash
sudo systemctl status cockpit
sudo systemctl restart cockpit
sudo ufw status
curl -k https://localhost:9090
```

---

## 🏗️ Архитектура проекта

```
├── install.sh              # Основной скрипт установки
├── update.sh               # Скрипт обновления (опционально)
├── .github/workflows/      
│   └── deploy.yml          # GitHub Actions автодеплой
├── docker-compose.yml      # Для локального тестирования
└── README.md              # Документация
```

---

## 📝 Changelog

- **v2.0** - Полная безопасность: убраны хардкоды, все через Secrets/ENV
- **v1.0** - Базовая функциональность с автодеплоем

---

## 📄 Лицензия

MIT License - используйте свободно в своих проектах.

---

**🎉 Готово! Ваш VPS сервер будет настроен автоматически и безопасно!**

*Создано с ❤️ для эффективного управления VPS серверами*
