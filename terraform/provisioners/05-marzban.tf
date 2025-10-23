resource "null_resource" "marzban" {
  depends_on = [null_resource.bootstrap]

  connection {
    type        = "ssh"
    host        = var.vps_host
    user        = var.vps_user
    private_key = var.ssh_private_key
  }

  provisioner "file" {
    source      = "${path.module}/files/marzban/"
    destination = "/opt/marzban"
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "cd /opt/marzban",
      "export MARZBAN_USERNAME='${var.marzban_username}' MARZBAN_PASSWORD='${var.marzban_password}'",
      "sudo -E docker-compose down || true",
      "sudo -E docker-compose up -d",
      "sleep 5; sudo docker ps | grep -q marzban || (sudo docker-compose logs && exit 1)",
      # Подменяем домен в nginx-конфиге при необходимости
      "sudo sed -i 's/vpn\\.botinger789298\\.work\\.gd/vpn.${var.domain_name}/g' /opt/marzban/marzban.conf || true",
      "sudo ln -sf /opt/marzban/marzban.conf /etc/nginx/sites-available/marzban.conf",
      "sudo ln -sf /etc/nginx/sites-available/marzban.conf /etc/nginx/sites-enabled/marzban.conf",
      "sudo certbot --nginx -d vpn.${var.domain_name} --email ${var.admin_email} --agree-tos --no-eff-email --redirect --non-interactive || true",
      "sudo nginx -t && sudo systemctl reload nginx"
    ]
  }

  triggers = {
    compose_hash = filesha256("${path.module}/files/marzban/docker-compose.yml")
    conf_hash    = filesha256("${path.module}/files/marzban/marzban.conf")
    creds_hash   = sha1("${var.marzban_username}:${var.marzban_password}")
  }
}
