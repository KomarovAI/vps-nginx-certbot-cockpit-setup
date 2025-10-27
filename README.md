# VPS Setup Script v3.2 - Production Ready + Marzban (Idempotent)

🚀 **Полностью автоматизированный и идемпотентный скрипт для настройки VPS с Nginx, SSL, Docker, Cockpit и кастомным контейнером Marzban VPN.**

## 🎆 Ключевые особенности v3.2

### ✅ **Полная идемпотентность**
- **Безопасные повторные запуски** - можно запускать сколько угодно раз
- **Система состояний** - отслеживает установленные компоненты
- **Умные проверки** - пропускает уже настроенные сервисы
- **Мягкие обновления** - не ломает существующие конфигурации

### 🛠️ **Кастомный Marzban VPN**
- ✓ **Автогенерация Reality ключей** - никаких ручных настроек
- ✓ **Docker контейнер с init-скриптами** - модульная инициализация
- ✓ **VLESS Reality с QUIC/gRPC** - максимальная производительность
- ✓ **UDP порты** - полная поддержка QUIC протокола
- ✓ **Nginx интеграция** - SSL проксирование и субдомены
- ✓ **Makefile управление** - простые команды для администрирования

### 🔄 **GitHub Actions CI/CD**
- **Автоматический деплой** - push в ветку = деплой на сервер
- **Гранулярные workflow** - выбор типа развертывания
- **Comprehensive health checks** - полная диагностика после деплоя
- **Pre-deployment validation** - проверки перед развертыванием

## 🚀 Быстрый старт

### Метод 1: GitHub Actions (Рекомендуемый)

1. **Fork этого репозитория**

2. **Настройте GitHub Secrets** в Settings → Secrets and variables → Actions:

   **Обязательные секреты:**
   ```
   VPS_HOST              # IP адрес вашего VPS
   VPS_USER              # SSH пользователь (обычно root)
   SSH_PRIVATE_KEY       # SSH приватный ключ
   DOMAIN_NAME           # Ваш домен
   ADMIN_EMAIL           # Email для SSL сертификатов
   ```

   **Опциональные секреты для Marzban:**
   ```
   COCKPIT_PASSWORD       # Пароль для Cockpit (автогенерация если не задан)
   MARZBAN_ADMIN_USERNAME # Логин админа Marzban
   MARZBAN_ADMIN_PASSWORD # Пароль админа Marzban
   XRAY_REALITY_PRIVATE_KEY # Reality приватный ключ (автогенерация)
   MARZBAN_PANEL_PORT     # Порт панели Marzban (по умолчанию 8000)
   XRAY_PORT             # Порт Xray VLESS (по умолчанию 2083)
   ```

3. **Настройте DNS** - создайте A-запись домена, указывающую на IP вашего VPS

4. **Запустите деплой:**
   - **Автоматически:** Push в `main` ветку
   - **Вручную:** Actions → "VPS Infrastructure Deploy" → Run workflow

### Метод 2: Интерактивный деплой на сервере

```bash
# Скачать и запустить быстрый деплой
curl -fsSL https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/feat/custom-marzban-container/quick-deploy.sh | bash
```

### Метод 3: Ручной деплой

```bash
# Установить переменные
export DOMAIN_NAME="your-domain.com"
export ADMIN_EMAIL="your-email@example.com"
export DEPLOY_MARZBAN="true"  # Включить Marzban

# Запустить установку
curl -fsSL https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/feat/custom-marzban-container/install.sh | bash
```

## 🎯 Типы деплоя в GitHub Actions

| Тип | Описание | Когда использовать |
|-----|----------|-----------------|
| **full** | Полная инфраструктура + Marzban | Первый деплой или полное обновление |
| **marzban-only** | Только Marzban VPN | Обновление/переустановка Marzban |
| **base-only** | Только базовая инфраструктура | Обновление Nginx/SSL/Cockpit |
| **update** | Обновление существующего деплоя | Регулярные обновления |

## 🌐 Результат развертывания

После успешного деплоя у вас будет:

### 🖥️ **Основные сервисы:**
- 🌐 **Веб-сайт**: `https://your-domain.com`
- 🖥️ **Cockpit панель**: `https://your-domain.com:9090`
- 🔒 **Marzban VPN**: `https://your-domain.com:8000`
- 🔗 **Marzban поддомен**: `https://marzban.your-domain.com` (если DNS настроен)

### 🛡️ **Безопасность:**
- ✅ SSL сертификаты от Let's Encrypt с автообновлением
- ✅ UFW Firewall с настроенными правилами
- ✅ Fail2ban защита от брутфорса
- ✅ Автоматические обновления безопасности
- ✅ Modern SSL/TLS конфигурация
- ✅ Security headers для всех сервисов

### 🔧 **Управление:**
- ✅ Docker + Docker Compose последних версий
- ✅ Система мониторинга и health checks
- ✅ Автоматическое резервное копирование
- ✅ Скрипты управления сервисами

## 🛠️ Управление после установки

### Основные команды мониторинга:
```bash
# Проверка статуса всех сервисов
sudo /root/check-services.sh

# Мониторинг в реальном времени
sudo /root/monitor.sh

# Health check системы
sudo /root/health-check.sh

# Создание backup конфигураций
sudo /root/backup-configs.sh
```

### Управление Marzban:
```bash
# Основные команды
sudo /root/marzban-manage.sh start     # Запуск
sudo /root/marzban-manage.sh stop      # Остановка
sudo /root/marzban-manage.sh restart   # Перезапуск
sudo /root/marzban-manage.sh status    # Статус
sudo /root/marzban-manage.sh logs      # Логи

# Управление
sudo /root/marzban-manage.sh build     # Пересборка контейнера
sudo /root/marzban-manage.sh update    # Обновление из Git
sudo /root/marzban-manage.sh backup    # Резервная копия данных
sudo /root/marzban-manage.sh clean     # Очистка контейнеров

# Отладка
sudo /root/marzban-manage.sh shell     # Shell в контейнере
```

### Прямое управление через Makefile:
```bash
cd /opt/marzban-deployment/marzban

# Основные команды
sudo make up          # Запуск сервисов
sudo make down        # Остановка сервисов
sudo make restart     # Перезапуск
sudo make logs        # Просмотр логов
sudo make health      # Проверка здоровья

# Разработка
sudo make build       # Сборка контейнера
sudo make shell       # Shell в контейнере
sudo make clean       # Очистка
```

## 🔧 Архитектура кастомного Marzban

### Структура контейнера:
```
marzban/
├── Dockerfile              # Кастомный образ
├── docker-compose.yml      # Конфигурация сервисов
├── entrypoint.sh           # Точка входа с инициализацией
├── Makefile               # Команды управления
├── .env.example           # Пример конфигурации
├── xray_config.json.tpl   # Шаблон Xray конфигурации
└── init-scripts/          # Скрипты инициализации
    ├── 01-setup-reality.sh    # Настройка Reality ключей
    └── 02-check-dependencies.sh # Проверка зависимостей
```

### Процесс инициализации:
1. **Создание директорий** и установка прав доступа
2. **Выполнение init-скриптов** в порядке нумерации
3. **Генерация Reality ключей** если не заданы
4. **Создание Xray конфигурации** из шаблона
5. **Валидация конфигурации** перед запуском
6. **Запуск Marzban** с корректными параметрами

### Отличия от стандартного Marzban:
- ✅ **Автономная инициализация** - всё настраивается автоматически
- ✅ **UDP порты** - полная поддержка QUIC протокола
- ✅ **Модульные скрипты** - легко добавлять новую логику
- ✅ **Валидация конфигурации** - проверка перед запуском
- ✅ **Расширенные инструменты** - curl, jq, envsubst

## 🔍 Отладка и решение проблем

### Диагностика системы:
```bash
# Полная диагностика
sudo /root/check-services.sh

# Проверка портов
sudo ss -tlnp | grep -E ':(80|443|8000|2083|9090)'

# Проверка SSL сертификатов
sudo certbot certificates

# Логи системы
sudo journalctl -u nginx -f
sudo journalctl -u cockpit -f
```

### Диагностика Marzban:
```bash
# Статус контейнеров
sudo docker ps | grep marzban

# Логи контейнера
sudo docker logs marzban --tail 50

# Проверка конфигурации Xray
sudo docker exec marzban cat /var/lib/marzban/xray_config.json

# Переменные окружения
sudo docker exec marzban env | grep XRAY

# Проверка портов внутри контейнера
sudo docker exec marzban ss -tlnp
```

### Решение типичных проблем:

**🔴 SSL сертификат не получается:**
```bash
# Проверка DNS
nslookup your-domain.com

# Проверка доступности порта 80
curl -I http://your-domain.com

# Повторное получение сертификата
sudo certbot --nginx -d your-domain.com
```

**🔴 Marzban не стартует:**
```bash
# Проверка логов инициализации
sudo docker logs marzban | grep "MARZBAN-INIT"

# Пересборка контейнера
cd /opt/marzban-deployment/marzban
sudo make clean
sudo make build
sudo make up
```

**🔴 QUIC не работает:**
```bash
# Проверка UDP портов
sudo ss -ulnp | grep 2083

# Проверка UFW правил
sudo ufw status | grep 2083

# Добавление UDP правила если отсутствует
sudo ufw allow 2083/udp
```

## ⚙️ Кастомизация

### Изменение портов:
```bash
# В GitHub Secrets или переменных окружения
MARZBAN_PANEL_PORT=8080  # Порт панели Marzban
XRAY_PORT=2084          # Порт Xray VLESS
```

### Добавление Reality серверов:
```bash
# В GitHub Secrets
XRAY_REALITY_SERVER_NAMES="discord.com,www.discord.com,github.com"
```

### Кастомная конфигурация Xray:
1. Отредактируйте `marzban/xray_config.json.tpl`
2. Используйте переменные окружения: `${VARIABLE_NAME}`
3. Пересоберите контейнер: `make build && make restart`

## 📊 Мониторинг и метрики

### Автоматические проверки:
- **Health checks** каждые 30 секунд
- **SSL renewal** проверки ежедневно
- **System updates** автоматически
- **Fail2ban** мониторинг в реальном времени

### Логи и диагностика:
- **VPS Setup**: `/var/log/vps-setup.log`
- **Nginx**: `/var/log/nginx/`
- **Marzban**: `docker logs marzban`
- **System**: `journalctl -p err`

## 🔄 Обновления

### Автоматические через GitHub Actions:
1. Push изменения в `main` ветку
2. Workflow автоматически определит тип обновления
3. Применит только необходимые изменения
4. Выполнит health check после обновления

### Ручные обновления:
```bash
# Обновление всей системы
export DOMAIN_NAME="your-domain.com"
export ADMIN_EMAIL="your-email@example.com"
sudo -E /opt/marzban-deployment/install.sh

# Обновление только Marzban
sudo /root/marzban-manage.sh update
```

## 📋 Требования

### Минимальные системные требования:
- **ОС**: Ubuntu 20.04/22.04 LTS
- **ОЗУ**: 1GB (2GB с Marzban)
- **Диск**: 3GB свободного места (4GB с Marzban)
- **Сеть**: Публичный IP адрес
- **Доступ**: Root права на сервере

### DNS настройки:
**⚠️ ОБЯЗАТЕЛЬНО:** A-запись домена должна указывать на IP вашего VPS!

```
# Основной домен
your-domain.com.     IN A    YOUR_VPS_IP

# Опционально: поддомен для Marzban
marzban.your-domain.com.  IN A    YOUR_VPS_IP
```

## 🤝 Поддержка и развитие

### Отчеты об ошибках:
Если вы обнаружили проблему:
1. Запустите диагностику: `sudo /root/check-services.sh`
2. Соберите логи: `sudo journalctl -p err --since "1 hour ago"`
3. Создайте [issue](https://github.com/KomarovAI/vps-nginx-certbot-cockpit-setup/issues) с подробным описанием

### Предложения по улучшению:
Мы приветствуем:
- Предложения по новым функциям
- Улучшения безопасности и производительности
- Обновления документации
- Дополнительные init-скрипты для Marzban

## 📄 Лицензия

MIT License - см. [LICENSE](LICENSE) файл для подробностей.

---

## 🎉 Changelog v3.2

### 🔥 Новые возможности
- ✅ **Полная идемпотентность** - безопасные повторные запуски
- ✅ **Система состояний** - отслеживание установленных компонентов
- ✅ **UDP порты для Xray** - полная поддержка QUIC протокола
- ✅ **Улучшенный CI/CD** - гранулярные типы деплоя
- ✅ **Comprehensive health checks** - детальная диагностика
- ✅ **Pre-deployment validation** - проверки перед развертыванием

### 🛠️ Улучшения
- ✅ **Унифицированный XRAY_JSON путь** - консистентная конфигурация
- ✅ **Мягкие обновления конфигураций** - без поломки существующих настроек
- ✅ **Улучшенная обработка ошибок** - более информативные сообщения
- ✅ **Автоматические обновления безопасности** - восстановлено из v3.0
- ✅ **DNS валидация для поддоменов** - проверка перед получением SSL

### 🔧 Исправления
- ✅ **UFW безопасность** - мягкий reset без нарушения SSH
- ✅ **Docker compose порты** - явное указание TCP/UDP
- ✅ **SSL renewal hooks** - корректная перезагрузка nginx
- ✅ **Fail2ban фильтры** - проверка существующих конфигураций
- ✅ **Memory management** - автоматическая настройка swap

**✨ Готовая к production VPS инфраструктура с полной автоматизацией деплоя через GitHub!**