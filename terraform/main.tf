locals {
  remote_dir = "/opt/vps-setup"
}

resource "null_resource" "bootstrap" {
  connection {
    type        = "ssh"
    host        = var.vps_host
    user        = var.vps_user
    private_key = var.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf ${local.remote_dir}/.git || true",
      "sudo mkdir -p ${local.remote_dir}",
      "sudo chown -R ${var.vps_user}:${var.vps_user} ${local.remote_dir}"
    ]
  }

  provisioner "file" {
    source      = "${path.module}/files/"
    destination = local.remote_dir
  }

  provisioner "remote-exec" {
    inline = [
      "set -euo pipefail",
      "cd ${local.remote_dir}",
      "chmod +x install.sh setup-memory.sh update.sh || true",
      "DOMAIN_NAME='${var.domain_name}' ADMIN_EMAIL='${var.admin_email}' COCKPIT_PASSWORD='${var.cockpit_password}' MARZBAN_USERNAME='${var.marzban_username}' MARZBAN_PASSWORD='${var.marzban_password}' bash ./install.sh",
      "DOMAIN_NAME='${var.domain_name}' ADMIN_EMAIL='${var.admin_email}' COCKPIT_PASSWORD='${var.cockpit_password}' MARZBAN_USERNAME='${var.marzban_username}' MARZBAN_PASSWORD='${var.marzban_password}' bash ./update.sh || true"
    ]
  }

  triggers = {
    install_hash       = filesha256("${path.module}/files/install.sh")
    setup_memory_hash  = filesha256("${path.module}/files/setup-memory.sh")
    update_hash        = filesha256("${path.module}/files/update.sh")
  }
}
