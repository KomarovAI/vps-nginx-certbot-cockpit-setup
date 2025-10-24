# 🚀 VPS Setup v3.0: Nginx + SSL + Cockpit + Docker

**Полностью переработанная система автоматической настройки VPS с исправленными критическими ошибками, улучшенной безопасностью и production-ready решениями.**

## 🎯 Ключевые улучшения v3.0

### ✅ Исправленные критические проблемы
- **Безопасность**: Исправлена утечка SSH-ключей в GitHub Actions
- **Стабильность**: Устранены синтаксические ошибки в Terraform
- **Валидация**: Добавлена проверка всех переменных окружения  
- **Логирование**: Унифицированная система логирования во всех скриптах
- **Обработка ошибок**: Улучшенная обработка ошибок с retry логикой

### 🔒 Усиленная безопасность
- **fail2ban**: Защита от брутфорс атак
- **UFW**: Настроенный firewall с rate limiting
- **Modern SSL**: Современные настройки SSL/TLS
- **Security Headers**: Полный набор заголовков безопасности
- **Auto Updates**: Автоматические обновления безопасности

### 📊 Мониторинг и диагностика
- **Health Checks**: Автоматические проверки состояния системы
- **Backup System**: Резервное копирование конфигураций
- **Monitoring Scripts**: Скрипты мониторинга в реальном времени
- **Detailed Logging**: Подробное логирование всех операций

## 🔧 Быстрая установка

### Метод 1: Автоматический деплой (GitHub Actions)

1. **Fork репозитория** или создайте новый с файлами проекта

2. **Настройте GitHub Secrets** в Settings → Secrets and variables → Actions:

| Секрет | Описание | Пример значения |
|--------|----------|-----------------|
| `VPS_HOST` | IP адрес или домен VPS | `31.59.58.96` |
| `VPS_USER` | SSH пользователь | `root` |
| `SSH_PRIVATE_KEY` | Приватный SSH ключ | Содержимое `~/.ssh/id_rsa` |
| `DOMAIN_NAME` | Ваш домен | `botinger789298.work.gd` |
| `ADMIN_EMAIL` | Email администратора | `your-email@example.com` |
| `COCKPIT_PASSWORD` | Пароль для Cockpit | `SecurePassword123!` |

3. **Подготовьте SSH ключи** на VPS:
```bash
# На VPS сервере
ssh-keygen -t rsa -b 4096 -f ~/.ssh/deploy_key -N ""
cat ~/.ssh/deploy_key.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Покажите приватный ключ для GitHub Secret
cat ~/.ssh/deploy_key
```

4. **Запустите деплой**: Push в main ветку или вручную в Actions → Infrastructure Deploy

### Метод 2: Прямая установка на VPS

```bash
# Установите переменные окружения
export DOMAIN_NAME="your-domain.com"
export ADMIN_EMAIL="your-email@example.com"  
export COCKPIT_PASSWORD="YourStrongPassword123!"

# Скачайте и запустите улучшенный скрипт
curl -s https://raw.githubusercontent.com/KomarovAI/vps-nginx-certbot-cockpit-setup/main/install.sh | sudo -E bash
```

### Метод 3: Terraform (Recommended для Production)

```bash
# Клонирование и настройка
git clone https://github.com/KomarovAI/vps-nginx-certbot-cockpit-setup.git
cd vps-nginx-certbot-cockpit-setup/terraform

# Создание terraform.tfvars
cat > terraform.tfvars <<EOF
vps_host = "your-server-ip"
vps_user = "root"
ssh_private_key = file("~/.ssh/id_rsa")
domain_name = "your-domain.com"
admin_email = "your-email@example.com"
cockpit_password = "SecurePassword123!"
EOF

# Деплой
terraform init
terraform plan
terraform apply
```

## 📋 Что устанавливается

### Основные компоненты
| Компонент | Версия | Статус | Описание |
|-----------|--------|--------|----------|
| **Nginx** | Latest | ✅ Активен | Веб-сервер с оптимизированной конфигурацией |
| **Let's Encrypt SSL** | - | ✅ Настроен | Бесплатные SSL сертификаты с автообновлением |
| **Cockpit** | Latest | ✅ Запущен | Веб-панель управления сервером |
| **Docker + Compose** | Latest | ✅ Установлен | Контейнеризация приложений |
| **UFW Firewall** | - | ✅ Включен | Настроенный брандмауэр |
| **fail2ban** | Latest | ✅ Активен | Защита от брутфорс атак |

### Системные улучшения
| Функция | Описание | Статус |
|---------|----------|--------|
| **Auto Updates** | Автоматические обновления безопасности | ✅ Настроено |
| **Memory Optimization** | zram 1GB + swap 4GB | ✅ Настроено |
| **Health Monitoring** | Автоматические проверки каждые 15 мин | ✅ Активно |
| **Backup System** | Еженедельное резервирование конфигураций | ✅ Настроено |
| **Log Management** | Ротация и очистка логов | ✅ Настроено |

## 🌐 Доступ к сервисам

После успешной установки:

| Сервис | URL | Описание |
|--------|-----|----------|
| **Основной сайт** | `https://YOUR-DOMAIN` | Главная страница с информацией |
| **Cockpit панель** | `https://YOUR-DOMAIN:9090` | Веб-интерфейс управления сервером |
| **Cockpit поддомен** | `https://cockpit.YOUR-DOMAIN` | Альтернативный доступ к панели |

### 🔐 Вход в Cockpit
- **Пользователь**: `cockpit-admin`
- **Пароль**: Значение `COCKPIT_PASSWORD` или установите вручную: `passwd cockpit-admin`

## 🔧 Управление системой

### Скрипты мониторинга
```bash
# Полная проверка всех сервисов
/root/check-services.sh

# Мониторинг в реальном времени  
/root/monitor.sh

# Проверка состояния памяти
/root/check-memory.sh

# Health check системы
/root/health-check.sh

# Создание backup конфигураций
/root/backup-configs.sh
```

### Обновление системы
```bash
# Обновление всех компонентов
export DOMAIN_NAME="your-domain.com"
export ADMIN_EMAIL="your-email@example.com"
sudo -E /opt/vps-setup/update.sh
```

### Проверка статуса сервисов
```bash
# Статус основных сервисов
sudo systemctl status nginx cockpit docker fail2ban

# Проверка SSL сертификатов
sudo certbot certificates

# Открытые порты
sudo ss -tlnp | grep -E ':(80|443|9090)'

# Использование памяти и swap
free -h && swapon --show
```

## 🔍 Диагностика и устранение неполадок

### Логи системы
```bash
# Основной лог установки
sudo tail -f /var/log/vps-setup.log

# Логи обновлений
sudo tail -f /var/log/vps-update.log

# Логи настройки памяти
sudo tail -f /var/log/memory-setup.log

# Логи Nginx
sudo tail -f /var/log/nginx/YOUR-DOMAIN.error.log

# Системные логи
sudo journalctl -f
```

### Часто встречающиеся проблемы

#### ❌ SSL сертификат не получается
**Проверьте:**
1. DNS запись домена указывает на ваш сервер
2. Порт 80 доступен из интернета
3. Нет конфликтующих веб-серверов

```bash
# Проверка DNS
nslookup YOUR-DOMAIN
dig YOUR-DOMAIN

# Принудительное обновление SSL
sudo certbot renew --force-renewal
```

#### ❌ Nginx не запускается
```bash
# Проверка конфигурации
sudo nginx -t

# Перезапуск с диагностикой
sudo systemctl restart nginx
sudo systemctl status nginx
```

#### ❌ Cockpit недоступен
```bash
# Проверка сервиса
sudo systemctl status cockpit
sudo systemctl restart cockpit

# Проверка firewall
sudo ufw status
sudo ufw allow 9090

# Проверка локального доступа
curl -k https://localhost:9090
```

#### ❌ Проблемы с памятью
```bash
# Проверка zram
lsblk | grep zram
sudo systemctl status zramswap

# Проверка swap
swapon --show
sudo swapon /swap.img

# Перезапуск zram
sudo systemctl restart zramswap
```

## 🛡️ Безопасность

### Рекомендуемые настройки безопасности

1. **Смена SSH порта** (опционально):
```bash
# Измените порт в /etc/ssh/sshd_config
sudo sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
sudo systemctl restart ssh
sudo ufw allow 2222
sudo ufw delete allow 22
```

2. **Ограничение SSH по IP** (для production):
```bash
# Разрешить SSH только с определенных IP
sudo ufw delete allow ssh
sudo ufw allow from YOUR-IP to any port 22
```

3. **Настройка дополнительных заголовков безопасности** уже включена в конфигурацию.

4. **Мониторинг логов fail2ban**:
```bash
# Проверка заблокированных IP
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

### Регулярное обслуживание

#### Еженедельно
- Проверка логов безопасности: `sudo journalctl -p err --since "1 week ago"`
- Анализ fail2ban статистики: `sudo fail2ban-client status`
- Проверка обновлений: `/root/health-check.sh`

#### Ежемесячно  
- Проверка размера логов: `sudo journalctl --disk-usage`
- Анализ использования ресурсов: `/root/check-memory.sh`
- Проверка backup'ов: `ls -la /root/config-backup/`

## 📚 Дополнительная документация

### Структура проекта
```
├── install.sh                  # Основной скрипт установки v3.0
├── setup-memory.sh             # Скрипт оптимизации памяти
├── update.sh                   # Скрипт обновления системы
├── terraform/                  # Terraform конфигурация
│   ├── main.tf                 # Основная конфигурация
│   ├── variables.tf            # Переменные с валидацией
│   └── outputs.tf              # Выходные значения
├── .github/workflows/          # GitHub Actions
│   └── infra-apply.yml         # Workflow деплоя (исправленный)
├── templates/                  # Шаблоны конфигураций
└── README.md                   # Эта документация
```

### Переменные окружения

| Переменная | Обязательная | Описание | Пример |
|------------|--------------|----------|--------|
| `DOMAIN_NAME` | ✅ | Основной домен сервера | `example.com` |
| `ADMIN_EMAIL` | ✅ | Email для SSL и уведомлений | `admin@example.com` |
| `VPS_IP` | ❌ | IP адрес сервера (автоопределение) | `192.168.1.100` |
| `COCKPIT_PASSWORD` | ❌ | Пароль для Cockpit | `SecurePass123!` |
| `COCKPIT_USER` | ❌ | Пользователь Cockpit | `cockpit-admin` |

### Terraform переменные (расширенные)

Полный список переменных с валидацией доступен в `terraform/variables.tf`. Ключевые дополнительные параметры:

- `enable_fail2ban` - Включить fail2ban (по умолчанию: true)
- `enable_auto_updates` - Автообновления (по умолчанию: true)
- `backup_retention_days` - Дни хранения backup'ов (по умолчанию: 30)
- `ssh_port` - SSH порт (по умолчанию: 22)
- `allowed_ssh_ips` - Разрешенные IP для SSH (по умолчанию: все)

## 🤝 Поддержка и развитие

### Отчеты об ошибках
Если вы обнаружили проблему:
1. Запустите диагностику: `/root/check-services.sh`
2. Соберите логи: `sudo journalctl -u nginx -n 50`
3. Создайте issue в репозитории с подробным описанием

### Предложения по улучшению
Мы приветствуем:
- Предложения по новым функциям
- Улучшения безопасности
- Оптимизации производительности
- Обновления документации

## 📄 Лицензия

MIT License - свободное использование в личных и коммерческих проектах.

---

## 🎉 Changelog v3.0

### 🔥 Критические исправления
- Исправлена утечка SSH-ключей в GitHub Actions
- Устранены синтаксические ошибки в Terraform конфигурации
- Добавлена полная валидация переменных окружения
- Исправлены проблемы с созданием пользователя Cockpit

### 🚀 Новые функции
- fail2ban защита от брутфорс атак
- Автоматические обновления безопасности
- Система health checks и мониторинга
- Резервное копирование конфигураций
- Улучшенные SSL настройки
- Rate limiting для Nginx

### 🛡️ Безопасность
- Modern SSL/TLS конфигурация
- Полный набор security headers
- UFW firewall с rate limiting
- Cockpit timeout конфигурация
- Secure password handling

### 📊 Мониторинг
- Real-time мониторинг системы
- Автоматические health checks
- Подробное логирование всех операций
- Memory usage optimization
- Service status monitoring

**✨ Готовый к production VPS сервер за 5-10 минут!**