# 🚀 VPS Setup: Nginx + Certbot SSL + Cockpit

**Автоматическая настройка VPS сервера с Nginx, SSL сертификатом от Let's Encrypt и панелью управления Cockpit.**

![VPS Setup](https://img.shields.io/badge/VPS-Ubuntu%2022.04-orange)
![Nginx](https://img.shields.io/badge/Nginx-Latest-green)
![SSL](https://img.shields.io/badge/SSL-Let's%20Encrypt-blue)
![Cockpit](https://img.shields.io/badge/Cockpit-Web%20Console-red)

---

## 🎯 Конфигурация проекта

- **🌐 Домен:** `botinger789298.work.gd`
- **📍 IP адрес:** `31.59.58.96`
- **📧 Email:** `artur.komarovv@gmail.com`
- **🔧 OS:** Ubuntu 22.04 LTS

---

## ⚡ Быстрый старт

### 🔥 Установка одной командой

```bash
# Скачиваем и запускаем установочный скрипт
curl -s https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/install.sh | sudo bash
```

### 📦 Локальная установка

```bash
# Клонируем репозиторий
git clone https://github.com/KomarovAI/vps-nginx-certbot-cockpit-setup.git
cd vps-nginx-certbot-cockpit-setup

# Делаем скрипт исполнимым и запускаем (от root)
sudo chmod +x install.sh
sudo ./install.sh
```

---

## 🤖 Автоматический деплой через GitHub Actions

### 1️⃣ Настройка SSH ключей на VPS

```bash
# Генерируем SSH ключи
ssh-keygen -t rsa -b 4096 -f ~/.ssh/deploy_key

# Добавляем публичный ключ в authorized_keys
cat ~/.ssh/deploy_key.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Копируем приватный ключ для GitHub (сохраните его)
cat ~/.ssh/deploy_key
```

### 2️⃣ Настройка GitHub Secrets

 В настройках репозитория добавьте секреты:

| Секрет | Значение |
|--------|----------|
| `SSH_PRIVATE_KEY` | Содержимое приватного ключа `~/.ssh/deploy_key` |
| `VPS_HOST` | `31.59.58.96` |
| `VPS_USER` | Ваш пользователь на VPS (например, `root` или `ubuntu`) |

### 3️⃣ Запуск автоматического деплоя

- Сделайте commit и push в репозиторий
- GitHub Actions автоматически запустит деплой
- Следите за прогрессом во вкладке "Actions"

---

## 📊 Что устанавливается

| Компонент | Описание | Статус |
|-----------|----------|--------|
| ✅ **Nginx** | Веб-сервер с оптимизированной конфигурацией | Установлен |
| ✅ **Let's Encrypt SSL** | Бесплатный SSL сертификат с автообновлением | Настроен |
| ✅ **Cockpit** | Веб-панель управления сервером | Активен |
| ✅ **UFW Firewall** | Настроенный брандмауэр | Включен |
| ✅ **Auto-updates** | Автоматическое обновление сертификатов | Настроено |

---

## 🌐 Доступ к сервисам

| Сервис | URL | Описание |
|--------|-----|----------|
| **Веб-сайт** | https://botinger789298.work.gd | Главная страница |
| **Cockpit** | https://botinger789298.work.gd:9090 | Панель управления |
| **HTTP→HTTPS** | http://botinger789298.work.gd | Автоматический редирект |

### 🔐 Данные для входа в Cockpit

- **Пользователь:** `cockpit-admin`
- **Пароль:** `VpsAdmin2025!`

---

## 🔧 Полезные команды

### 📈 Мониторинг и проверки

```bash
# Полная проверка всех служб
/root/check-services.sh

# Мониторинг в реальном времени
/root/monitor.sh

# Обновление системы и всех компонентов
sudo ./update.sh
```

### 📝 Логи и диагностика

```bash
# Логи Nginx
sudo tail -f /var/log/nginx/botinger789298.work.gd.access.log
sudo tail -f /var/log/nginx/botinger789298.work.gd.error.log

# Логи Cockpit
sudo journalctl -u cockpit -f

# Проверка SSL сертификата
sudo certbot certificates
sudo certbot renew --dry-run
```

---

## 🆘 Устранение неполадок

### ❌ Nginx не запускается

```bash
sudo nginx -t
sudo systemctl status nginx
sudo systemctl restart nginx
```

### ❌ SSL сертификат не работает

```bash
sudo certbot certificates
sudo certbot renew --force-renewal
```

### ❌ Cockpit недоступен

```bash
sudo systemctl status cockpit
sudo systemctl restart cockpit
sudo ufw status
```

---

**🎉 Поздравляем! Ваш VPS сервер готов к работе!**