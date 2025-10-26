# VPS Setup Script v3.3 - Production Ready + Marzban

Полностью автоматизированный скрипт для настройки VPS с Nginx, SSL, Docker, Cockpit и стабильным Marzban VPN сервером.

## 🎆 Новые возможности v3.3 (Стабильная версия)

- ✅ **"no such table: users" - ПОЛНОСТЬЮ УСТРАНЕНА** - переход на стабильный образ
- ✅ **Надёжный запуск** - нет больше циклов перезапуска контейнеров
- ✅ **Стандартная архитектура** - использует официальный Marzban образ
- ✅ **Простая инициализация БД** - стандартные Alembic миграции
- ✅ **Улучшенная диагностика** - лучшие health checks и логирование

### Что исправлено:
- 🔧 **Убраны кастомные сборки** - источник всех проблем с контейнерами
- 🔧 **Стандартизированы пути БД** - используется `db.sqlite3`
- 🔧 **Улучшены health checks** - Python requests вместо curl
- 🔧 **Упрощено управление** - меньше сложности, больше надёжности
- 🔧 **Обратная совместимость** - можно использовать без Marzban

## 🚀 Особенности

### Основные компоненты:
- ✅ **Nginx** с оптимизациями безопасности
- ✅ **Let's Encrypt SSL** с автообновлением
- ✅ **Docker + Docker Compose** последние версии
- ✅ **Cockpit** веб-интерфейс управления
- ✅ **UFW Firewall** с правильными настройками
- ✅ **Fail2ban** защита от брутфорса

### Marzban VPN сервер (опционально):
- ✅ **Стабильный образ** - официальный `gozargah/marzban:latest`
- ✅ **VLESS Reality** протокол с маскировкой
- ✅ **Автоматическая настройка** - без сложных конфигураций
- ✅ **Веб-панель управления** с SSL защитой
- ✅ **Простое управление** через скрипты
- ✅ **100% надёжная инициализация БД** - никаких ошибок таблиц!

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
./manage.sh admin create --username admin --password pass123  # Создать админа
./manage.sh shell              # Консоль контейнера
./manage.sh reset              # Сброс всех данных (осторожно!)
```

## 🔧 Конфигурация

### Параметры окружения:

| Параметр | Описание | По умолчанию |
|-----------|--------------|------------|
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

# Быстрое исправление
cd /opt/marzban-deployment/marzban && ./manage.sh restart

# Просмотр логов Marzban
cd /opt/marzban-deployment/marzban && ./manage.sh logs

# Полный сброс (удаляет все данные!)
cd /opt/marzban-deployment/marzban && ./manage.sh reset
```

### "no such table: users" - ИСПРАВЛЕНА в v3.3!
Эта проблема полностью решена в версии 3.3. Если вы всё ещё видите эту ошибку:

```bash
# Обновление до v3.3
cd /opt/marzban-deployment
git pull origin main
cd marzban
docker-compose down
docker rmi komarovai/marzban-custom:latest 2>/dev/null || true
docker-compose up -d
./manage.sh status
```

## 🆙 Обновление с предыдущих версий

### С версий 3.2.x:
```bash
cd /opt/marzban-deployment
git pull origin main
cd marzban
docker-compose down
# Удаляем старые кастомные образы
docker rmi komarovai/marzban-custom:latest 2>/dev/null || true
docker system prune -f
# Запускаем новую стабильную версию
docker-compose up -d
./manage.sh status
```

### С версии 3.1.x:
```bash
cd /opt/marzban-deployment
git pull origin main
cd marzban
docker-compose restart
./manage.sh status
```

## 📁 Структура проекта

```
vps-nginx-certbot-cockpit-setup/
│
├── README.md                    # Основная документация
├── CHANGELOG.md                 # История изменений
├── quick-deploy.sh              # Быстрый интерактивный деплой
├── install.sh                   # Основной скрипт установки v3.3
├── update.sh                    # Скрипт обновления
│
├── marzban/                     # Marzban конфигурация
│   ├── docker-compose.yml        # Docker Compose (стабильный образ)
│   ├── manage.sh                 # Упрощённый скрипт управления
│   └── .env.example              # Пример конфигурации
└── scripts/                     # Вспомогательные скрипты
```

## 🌟 Пример использования

```bash
# 1. Быстрое развёртывание VPS с Marzban VPN
curl -fsSL https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/quick-deploy.sh | bash

# 2. Проверка статуса после установки
/root/check-services.sh

# 3. Управление Marzban
cd /opt/marzban-deployment/marzban
./manage.sh status
./manage.sh admin create --username admin --password secure123

# 4. Доступ к панели
# https://your-domain.com:8000
```

## ✅ Что изменилось в v3.3

**Основные улучшения:**
- 🟢 **Стабильность** - нет больше циклов перезапуска
- 🟢 **Простота** - убрана сложная кастомная логика
- 🟢 **Надёжность** - официальный Marzban образ
- 🟢 **Диагностика** - лучшие инструменты отладки
- 🟢 **Совместимость** - стандартные пути и конфигурации

**Исправленные проблемы:**
- ❌ "no such table: users" - полностью устранена
- ❌ Циклы перезапуска контейнера - исправлены  
- ❌ JSON parse ошибки - исчезли
- ❌ Конфликты сборки - убраны
- ❌ Сложная диагностика - упрощена

## 🐛 Отчеты о ошибках

Нашли ошибку или есть предложение? Откройте [issue](https://github.com/KomarovAI/vps-nginx-certbot-cockpit-setup/issues) на GitHub.

## 📜 Лицензия

MIT License - см. [LICENSE](LICENSE) файл для подробностей.

---

✨ **Создано с ❤️ для упрощения деплоя VPS серверов**

🚀 **v3.3 - Надёжный, Стабильный, Проверенный в бою!**