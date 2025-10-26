# VPS Setup Script v3.1 - Production Ready + Marzban

Полностью автоматизированный скрипт для настройки VPS с Nginx, SSL, Docker, Cockpit и кастомным контейнером Marzban.

## 🎆 Новые возможности v3.1

- ✓ **Кастомный контейнер Marzban** - полностью интегрированное VPN решение
- ✓ **Автоматическая генерация Reality ключей** - без ручной конфигурации
- ✓ **Проксирование через Nginx** - SSL терминация и безопасность
- ✓ **Скрипты управления** - простое управление сервисами
- ✓ **Интерактивный деплой** - быстрая настройка

## 🚀 Особенности

### Основные компоненты:
- ✓ **Nginx** с оптимизациями безопасности
- ✓ **Let's Encrypt SSL** с автообновлением
- ✓ **Docker + Docker Compose** последние версии
- ✓ **Cockpit** веб-интерфейс управления
- ✓ **UFW Firewall** с правильными настройками
- ✓ **Fail2ban** защита от брутфорса
- ✓ **Мониторинг и бэкапы** автоматические скрипты

### Marzban VPN сервер:
- ✓ **VLESS Reality** протокол с маскировкой
- ✓ **Автоматическая конфигурация** - Reality ключи, Xray, сертификаты
- ✓ **Веб-панель управления** с SSL и проксированием
- ✓ **Health checks и мониторинг** статуса сервиса
- ✓ **Кастомный контейнер** с собственными скриптами

## 📍 Требования

### Минимальные:
- **ОС:** Ubuntu 20.04/22.04 LTS (рекомендуется)
- **ОЗУ:** 1 GB для базовых компонентов, 2 GB с Marzban
- **Место на диске:** 3 GB свободного места, 4 GB с Marzban
- **Доступ:** Root права на сервере

### Настройка DNS:
ℹ️ **ОБЯЗАТЕЛЬНО:** A-запись домена должна указывать на IP вашего сервера для получения SSL сертификатов!

## 🚀 Быстрый старт (Рекомендуемый)

Интерактивный скрипт для быстрого деплоя:

```bash
# Скачать и запустить быстрый деплой
curl -fsSL https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/feat/custom-marzban-container/quick-deploy.sh | bash
```

Скрипт сам запросит:
- 🌐 Имя домена
- 📧 Email для SSL сертификатов
- 🔒 Пароль для Cockpit (опционально)
- 🔒 Нужен ли Marzban VPN
- ⚙️ Порты Marzban (если выбран)

## 🛠️ Ручной деплой

### 1. Базовая настройка (только Nginx + SSL + Cockpit)

```bash
# Установить переменные
export DOMAIN_NAME="your-domain.com"
export ADMIN_EMAIL="your-email@example.com"
export COCKPIT_PASSWORD="your-secure-password"  # опционально

# Запустить деплой
curl -fsSL https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/feat/custom-marzban-container/install.sh | bash
```

### 2. Полная настройка с Marzban

```bash
# Установить переменные
export DOMAIN_NAME="your-domain.com"
export ADMIN_EMAIL="your-email@example.com"
export COCKPIT_PASSWORD="your-secure-password"

# Marzban конфигурация
export DEPLOY_MARZBAN="true"
export MARZBAN_PANEL_PORT="8000"  # по умолчанию
export XRAY_PORT="2083"           # по умолчанию

# Запустить деплой
curl -fsSL https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/feat/custom-marzban-container/install.sh | bash
```

## 🌐 Что вы получите

После успешного деплоя у вас будет:

### Основные сервисы:
- 🌐 **Веб-сайт**: `https://your-domain.com`
- 🖥️ **Cockpit панель**: `https://your-domain.com:9090`
- 🔒 **Marzban панель**: `https://your-domain.com:8000` (если включен)
- 🔗 **Marzban поддомен**: `https://marzban.your-domain.com` (если доступен SSL)

### Управление сервисами:
```bash
# Основные команды
sudo /root/check-services.sh        # Проверка статуса всех сервисов
sudo /root/monitor.sh               # Мониторинг в реальном времени
sudo /root/health-check.sh          # Health check
sudo /root/backup-configs.sh        # Бэкап конфигурации

# Marzban управление (если включен)
sudo /root/marzban-manage.sh start   # Запуск Marzban
sudo /root/marzban-manage.sh stop    # Остановка
sudo /root/marzban-manage.sh restart # Перезапуск
sudo /root/marzban-manage.sh logs    # Просмотр логов
sudo /root/marzban-manage.sh status  # Проверка статуса
sudo /root/marzban-manage.sh update  # Обновление
sudo /root/marzban-manage.sh backup  # Бэкап данных
```

## 🔧 Кастомизация

### Marzban настройки:
Кастомный контейнер Marzban находится в `/opt/marzban-deployment/marzban/`

```bash
# Переход в директорию Marzban
cd /opt/marzban-deployment/marzban/

# Просмотр конфигурации
cat .env

# Использование Makefile
make help                           # Показать доступные команды
make logs                           # Логи
make shell                          # Открыть shell в контейнере
make health                         # Проверка здоровья
```

### Параметры конфигурации:

| Параметр | Описание | По умолчанию |
|-----------|-------------|------------|
| `DOMAIN_NAME` | Ваш домен | Обязательно |
| `ADMIN_EMAIL` | Email для SSL | Обязательно |
| `COCKPIT_PASSWORD` | Пароль Cockpit | Автогенерация |
| `DEPLOY_MARZBAN` | Включить Marzban | `false` |
| `MARZBAN_PANEL_PORT` | Порт панели | `8000` |
| `XRAY_PORT` | Порт VLESS | `2083` |
| `VPS_IP` | IP сервера | Автоопределение |

## 🔍 Мониторинг и отладка

### Проверка статуса:
```bash
# Полная проверка всех сервисов
sudo /root/check-services.sh

# Проверка SSL сертификатов
sudo certbot certificates

# Просмотр открытых портов
sudo ss -tlnp | grep -E ':(80|443|8000|2083|9090)'

# Просмотр логов системы
sudo tail -f /var/log/vps-setup.log
```

### Логи сервисов:
```bash
# Nginx логи
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/your-domain.com.access.log

# Marzban логи
sudo /root/marzban-manage.sh logs

# Системные логи
sudo journalctl -u nginx -f
sudo journalctl -u cockpit -f
```

## ⚠️ Исправление проблем

### Ошибки SSL:
```bash
# Проверка DNS
nslookup your-domain.com

# Проверка доступности порта 80
sudo ufw status
curl -I http://your-domain.com

# Повторное получение сертификата
sudo certbot --nginx -d your-domain.com
```

### Проблемы с Marzban:
```bash
# Проверка статуса Docker
sudo docker ps

# Пересборка контейнера
cd /opt/marzban-deployment/marzban/
sudo make clean
sudo make build
sudo make up

# Проверка логов инициализации
sudo make logs | grep -E "MARZBAN-INIT|REALITY-INIT|DEPS-CHECK"
```

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
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── entrypoint.sh
│   ├── Makefile
│   ├── README.md
│   ├── .env.example
│   ├── xray_config.json.tpl
│   └── init-scripts/
│       ├── 01-setup-reality.sh
│       └── 02-check-dependencies.sh
│
├── scripts/                     # Вспомогательные скрипты
└── docs/                        # Документация
```

## 🐛 Отчеты о ошибках

Нашли ошибку или есть предложение? Откройте [issue](https://github.com/KomarovAI/vps-nginx-certbot-cockpit-setup/issues) на GitHub.

## 📜 Лицензия

MIT License - см. [LICENSE](LICENSE) файл для подробностей.

---

✨ **Создано с ❤️ для упрощения деплоя VPS серверов**