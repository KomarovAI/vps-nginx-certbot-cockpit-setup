# VPS Setup Script v3.2 - Production Ready + Marzban

Полностью автоматизированный скрипт для настройки VPS с Nginx, SSL, Docker, Cockpit и современным Marzban VPN сервером.

## 🎆 Новые возможности v3.2

- ✅ **Исправлена ошибка "no such table: users"** - автоинициализация базы данных
- ✅ **Надёжный запуск** - инициализация базы перед запуском приложения
- ✅ **Улучшенные таймауты** - достаточно времени для инициализации
- ✅ **Лучшая обработка ошибок** - детальное логирование и диагностика

### Ключевые исправления:
- ✅ **Кастомный Marzban контейнер** - автоматическая настройка VLESS Reality
- ✅ **Простое управление** - скрипты для легкого контроля
- ✅ **Интерактивный деплой** - простое развёртывание
- ✅ **Обратная совместимость** - можно использовать без Marzban
- ✅ **Мониторинг** - встроенные скрипты мониторинга

## 🚀 Особенности

### Основные компоненты:
- ✅ **Nginx** с оптимизациями безопасности
- ✅ **Let's Encrypt SSL** с автообновлением
- ✅ **Docker + Docker Compose** последние версии
- ✅ **Cockpit** веб-интерфейс управления
- ✅ **UFW Firewall** с правильными настройками
- ✅ **Fail2ban** защита от брутфорса

### Marzban VPN сервер (опционально):
- ✅ **VLESS Reality** протокол с маскировкой
- ✅ **Автоматическая конфигурация** Reality ключи, Xray
- ✅ **Веб-панель управления** с SSL защитой
- ✅ **Простое управление** через скрипты
- ✅ **Надёжная инициализация БД** - нет ошибок с таблицами

## 📍 Требования

### Минимальные:
- **ОС:** Ubuntu 20.04/22.04 LTS (рекомендуется)
- **ОЗУ:** 1 GB (базово), 2 GB с Marzban
- **Место:** 3 GB свободного места, 4 GB с Marzban
- **Доступ:** Root права на сервере

### Настройка DNS:
ℹ️ **ОБЯЗАТЕЛЬНО:** A-запись домена должна указывать на IP вашего сервера!

## 🚀 Быстрый старт

### Метод 1: Интерактивный (Рекомендуемый)

Просто запустите одну команду:

```bash
curl -fsSL https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/quick-deploy.sh | bash
```

Скрипт сам запросит все необходимые параметры и выполнит полный деплой.

### Метод 2: Ручная конфигурация

#### Базовая настройка (только Nginx + SSL + Cockpit):

```bash
export DOMAIN_NAME="your-domain.com"
export ADMIN_EMAIL="your-email@example.com"
export COCKPIT_PASSWORD="your-secure-password"  # опционально

curl -fsSL https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/install.sh | bash
```

#### Полная настройка с Marzban VPN:

```bash
export DOMAIN_NAME="your-domain.com"
export ADMIN_EMAIL="your-email@example.com"
export COCKPIT_PASSWORD="your-secure-password"

# Marzban конфигурация
export DEPLOY_MARZBAN="true"
export MARZBAN_PANEL_PORT="8000"  # по умолчанию
export XRAY_PORT="2083"           # по умолчанию

# Опционально: создать админа автоматически
export MARZBAN_ADMIN_USERNAME="admin"
export MARZBAN_ADMIN_PASSWORD="your-marzban-password"

curl -fsSL https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/install.sh | bash
```

## 🌐 Результат

После успешного деплоя у вас будет:

### Доступные сервисы:
- 🌐 **Веб-сайт**: `https://your-domain.com`
- 🖥️ **Cockpit панель**: `https://your-domain.com:9090`
- 🔒 **Marzban панель**: `https://your-domain.com:8000` (если включен)

### Команды управления:
```bash
# Основные команды
/root/check-services.sh        # Проверка статуса всех сервисов

# Marzban управление (если включен)
cd /opt/marzban-deployment/marzban
./manage.sh start              # Запуск Marzban
./manage.sh stop               # Остановка Marzban
./manage.sh restart            # Перезапуск Marzban
./manage.sh logs               # Логи Marzban
./manage.sh status             # Статус Marzban
./manage.sh build              # Пересборка контейнера
```

## 🔧 Конфигурация

### Параметры окружения:

| Параметр | Описание | По умолчанию |
|-----------|--------------|--------------|
| `DOMAIN_NAME` | Ваш домен | Обязательно |
| `ADMIN_EMAIL` | Email для SSL | Обязательно |
| `COCKPIT_PASSWORD` | Пароль Cockpit | Автогенерация |
| `DEPLOY_MARZBAN` | Включить Marzban | `false` |
| `MARZBAN_PANEL_PORT` | Порт панели Marzban | `8000` |
| `XRAY_PORT` | Порт VLESS | `2083` |
| `MARZBAN_ADMIN_USERNAME` | Админ Marzban | Опционально |
| `MARZBAN_ADMIN_PASSWORD` | Пароль админа | Опционально |
| `VPS_IP` | IP сервера | Автоопределение |

## 🔍 Мониторинг и отладка

### Проверка статуса:
```bash
# Полная проверка всех сервисов
/root/check-services.sh

# Проверка SSL сертификатов
certbot certificates

# Просмотр открытых портов
ss -tlnp | grep -E ':(80|443|8000|2083|9090)'

# Просмотр логов
tail -f /var/log/vps-setup.log
```

### Логи сервисов:
```bash
# Nginx логи
tail -f /var/log/nginx/error.log

# Marzban логи (если включен)
cd /opt/marzban-deployment/marzban && ./manage.sh logs

# Системные логи
journalctl -u nginx -f
journalctl -u cockpit -f
```

## ⚠️ Исправление проблем

### Ошибки SSL:
```bash
# Проверка DNS
nslookup your-domain.com

# Проверка доступности порта 80
ufw status
curl -I http://your-domain.com

# Повторное получение сертификата
certbot --nginx -d your-domain.com
```

### Проблемы с Marzban:
```bash
# Проверка статуса Docker
docker ps

# Перезапуск Marzban
cd /opt/marzban-deployment/marzban && ./manage.sh restart

# Просмотр логов Marzban
cd /opt/marzban-deployment/marzban && ./manage.sh logs

# Пересборка контейнера (при ошибках БД)
cd /opt/marzban-deployment/marzban && ./manage.sh build && ./manage.sh restart
```

### Ошибка "no such table: users" (исправлена в v3.2):
В версии 3.2 эта проблема решена автоматически. База данных инициализируется перед запуском приложения.

## 📁 Структура проекта

```
vps-nginx-certbot-cockpit-setup/
│
├── README.md                    # Основная документация
├── quick-deploy.sh              # Быстрый интерактивный деплой
├── install.sh                   # Основной скрипт установки
├── update.sh                    # Скрипт обновления
│
├── marzban/                     # Marzban кастомный контейнер
│   ├── entrypoint.sh             # Улучшенная точка входа с инициализацией БД
│   ├── manage.sh                 # Скрипт управления Marzban
│   ├── docker-compose.yml        # Docker Compose конфигурация
│   └── init-scripts/             # Скрипты инициализации
└── scripts/                     # Вспомогательные скрипты
```

## 🌟 Пример использования

```bash
# 1. Простое развёртывание VPS с веб-сайтом
curl -fsSL https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/quick-deploy.sh | bash

# 2. Проверка статуса после установки
/root/check-services.sh

# 3. Если установили Marzban - проверка его статуса
cd /opt/marzban-deployment/marzban && ./manage.sh status
```

## 🐛 Отчеты о ошибках

Нашли ошибку или есть предложение? Откройте [issue](https://github.com/KomarovAI/vps-nginx-certbot-cockpit-setup/issues) на GitHub.

## 📜 Лицензия

MIT License - см. [LICENSE](LICENSE) файл для подробностей.

---

✨ **Создано с ❤️ для упрощения деплоя VPS серверов**