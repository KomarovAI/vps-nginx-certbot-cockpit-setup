# VPS Setup Script v3.3 - Production Ready + Marzban
Полностью автоматизированный скрипт для настройки VPS с Nginx, SSL, Docker, Cockpit и стабильным Marzban VPN сервером.

## 🎆 Новые возможности v3.3 (Стабильная версия)
- ✅ "no such table: users" - ПОЛНОСТЬЮ УСТРАНЕНА - переход на стабильный образ
- ✅ Надёжный запуск - нет больше циклов перезапуска контейнеров
- ✅ Стандартная архитектура - использует официальный Marzban образ
- ✅ Простая инициализация БД - стандартные Alembic миграции
- ✅ Улучшенная диагностика - лучшие health checks и логирование

### Что исправлено:
- 🔧 Убраны кастомные сборки - источник всех проблем с контейнерами
- 🔧 Стандартизированы пути БД - используется `db.sqlite3`
- 🔧 Улучшены health checks - Python requests вместо curl
- 🔧 Упрощено управление - меньше сложности, больше надёжности
- 🔧 Обратная совместимость - можно использовать без Marzban

## 🚀 Особенности
### Основные компоненты:
- ✅ Nginx с оптимизациями безопасности
- ✅ Let's Encrypt SSL с автообновлением
- ✅ Docker + Docker Compose последние версии
- ✅ Cockpit веб-интерфейс управления
- ✅ UFW Firewall с правильными настройками
- ✅ Fail2ban защита от брутфорса

### Marzban VPN сервер (опционально):
- ✅ Стабильный образ - официальный `gozargah/marzban:latest`
- ✅ VLESS Reality протокол с маскировкой
- ✅ Автоматическая настройка - без сложных конфигураций
- ✅ Веб-панель управления с SSL защитой

---

## 🌐 Новое: Деплой внешнего сайта (service.moscow) вместе с инфраструктурой
Добавлена поддержка одновременного запуска Marzban, Nginx, Cockpit и внешнего сайта из Docker-образа `ghcr.io/komarovai/service.moscow` через общий docker-compose.

- Образ: `ghcr.io/komarovai/service.moscow:${IMAGE_TAG:-latest}`
- Переменные:
  - `IMAGE_TAG` — тег образа сайта (по умолчанию `latest`)
  - `WEBSITE_PORT` — внешний порт сайта (по умолчанию `3000`), внутри контейнера порт `80`
- Сеть: общий `marzban-network` для корректной работы с обратным прокси Nginx

### Пример compose-блока (уже добавлен в marzban/docker-compose.yml):
```yaml
  service-moscow:
    image: ghcr.io/komarovai/service.moscow:${IMAGE_TAG:-latest}
    container_name: service-moscow
    restart: unless-stopped
    ports:
      - "${WEBSITE_PORT:-3000}:80"
    networks:
      - marzban-network
    environment:
      - NODE_ENV=production
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:80"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

### Автодеплой сайта через IMAGE_TAG
Можно обновлять сайт без правки compose-файла, меняя только переменную окружения.

- Одноразово (разовый запуск с нужным тегом):
```bash
IMAGE_TAG=latest WEBSITE_PORT=3000 docker compose -f marzban/docker-compose.yml up -d service-moscow
```

- Постоянно (через .env рядом с docker-compose):
```env
IMAGE_TAG=latest
WEBSITE_PORT=3000
```
После правки .env:
```bash
docker compose -f marzban/docker-compose.yml up -d service-moscow
```

- Обновление до последней версии:
```bash
IMAGE_TAG=latest docker compose -f marzban/docker-compose.yml pull service-moscow
IMAGE_TAG=latest docker compose -f marzban/docker-compose.yml up -d service-moscow
```

### Совместный запуск всей инфраструктуры
```bash
# Запуск всех сервисов (Marzban, сайт, и т.д.)
IMAGE_TAG=latest WEBSITE_PORT=3000 \
  docker compose -f marzban/docker-compose.yml up -d
```

Если Nginx-прокси и SSL подготавливаются отдельными скриптами — убедитесь, что домен и бэкенд-роутинг указывают на WEBSITE_PORT или на сервис по имени `service-moscow` внутри сети `marzban-network`.

### Диагностика
```bash
# Логи сайта
docker logs -f service-moscow
# Проверка здоровья контейнера
docker inspect --format='{{json .State.Health}}' service-moscow | jq
# Проверка доступности
curl -I http://localhost:${WEBSITE_PORT:-3000}
```

---

## ⚙️ Быстрый старт
1) Подготовьте сервер с помощью скрипта установки (Nginx, Docker, SSL, Cockpit)
2) Перейдите в каталог проекта и откройте файл `marzban/docker-compose.yml`
3) Убедитесь, что блок `service-moscow` присутствует (см. выше)
4) Запустите инфраструктуру:
```bash
IMAGE_TAG=latest WEBSITE_PORT=3000 docker compose -f marzban/docker-compose.yml up -d
```
5) Настройте Nginx proxy на домен сайта, проксируя на `service-moscow:80` (внутри сети) или на `127.0.0.1:${WEBSITE_PORT}` (снаружи)

Готово — Marzban, Cockpit, Nginx и ваш сайт запущены вместе.
