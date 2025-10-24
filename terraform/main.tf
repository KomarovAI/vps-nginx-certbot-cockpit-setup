terraform {
  required_version = ">= 1.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Локальные переменные
locals {
  remote_dir = "/opt/vps-setup"
  timestamp  = formatdate("YYYY-MM-DD_hhmm", timestamp())
}

# Основной ресурс для развертывания
resource "null_resource" "vps_bootstrap" {
  # SSH соединение
  connection {
    type        = "ssh"
    host        = var.vps_host
    user        = var.vps_user
    private_key = var.ssh_private_key
    timeout     = "10m"
  }

  # Предварительная очистка и подготовка
  provisioner "remote-exec" {
    inline = [
      "echo 'Starting VPS setup at ${local.timestamp}'",
      "sudo rm -rf ${local.remote_dir}/.git || true",
      "sudo mkdir -p ${local.remote_dir}",
      "sudo chown -R ${var.vps_user}:${var.vps_user} ${local.remote_dir}",
      "echo 'Directory prepared: ${local.remote_dir}'"
    ]
  }

  # Копирование файлов установки
  provisioner "file" {
    source      = "${path.module}/files/"
    destination = local.remote_dir
  }

  # Установка прав выполнения
  provisioner "remote-exec" {
    inline = [
      "cd ${local.remote_dir}",
      "chmod +x *.sh || true",
      "ls -la ${local.remote_dir}"
    ]
  }

  # Выполнение основной установки
  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "cd ${local.remote_dir}",
      "export DOMAIN_NAME='${var.domain_name}'",
      "export ADMIN_EMAIL='${var.admin_email}'",
      "export VPS_IP='${var.vps_host}'",
      "export COCKPIT_PASSWORD='${var.cockpit_password}'",
      "export COCKPIT_USER='cockpit-admin'",
      "echo 'Environment variables set'",
      "echo 'Starting main installation...'",
      "sudo -E ./install.sh 2>&1 | tee /tmp/install.log",
      "echo 'Installation completed'"
    ]
    
    on_failure = continue
  }

  # Выполнение обновлений (необязательно)
  provisioner "remote-exec" {
    inline = [
      "cd ${local.remote_dir}",
      "export DOMAIN_NAME='${var.domain_name}'",
      "export ADMIN_EMAIL='${var.admin_email}'", 
      "if [ -f './update.sh' ]; then",
      "  echo 'Running update script...'",
      "  sudo -E ./update.sh || echo 'Update script failed (non-critical)'",
      "else",
      "  echo 'Update script not found, skipping'",
      "fi"
    ]
    
    on_failure = continue
  }

  # Финальная проверка статуса
  provisioner "remote-exec" {
    inline = [
      "echo '=== Final Status Check ==='",
      "sudo systemctl status nginx --no-pager -l | head -10 || true",
      "sudo systemctl status cockpit --no-pager -l | head -10 || true",
      "sudo systemctl status docker --no-pager -l | head -10 || true",
      "echo '=== SSL Certificates ==='", 
      "sudo certbot certificates | head -20 || echo 'Certbot not available'",
      "echo '=== Open Ports ==='",
      "sudo ss -tlnp | grep -E ':(80|443|9090)' || true",
      "echo '=== Disk Space ==='",
      "df -h / | tail -1",
      "echo '=== Installation Log Summary ==='",
      "tail -20 /var/log/vps-setup.log || tail -20 /tmp/install.log || echo 'No installation log found'",
      "echo 'VPS setup completed at $(date)'"
    ]
  }

  # Триггеры для перезапуска при изменениях
  triggers = {
    # Хеши основных скриптов из корня репозитория
    install_hash      = fileexists("${path.root}/../install.sh") ? filesha256("${path.root}/../install.sh") : "no-install-script"
    setup_memory_hash = fileexists("${path.root}/../setup-memory.sh") ? filesha256("${path.root}/../setup-memory.sh") : "no-memory-script"
    update_hash       = fileexists("${path.root}/../update.sh") ? filesha256("${path.root}/../update.sh") : "no-update-script"
    
    # Хеши переменных для отслеживания изменений конфигурации
    domain_name       = var.domain_name
    admin_email       = var.admin_email
    vps_host         = var.vps_host
    
    # Временная метка для принудительного обновления
    timestamp        = local.timestamp
  }
}