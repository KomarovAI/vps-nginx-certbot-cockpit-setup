output "site_url" { value = "https://${var.domain_name}" }
output "cockpit_url" { value = "https://${var.domain_name}:9090" }
output "vpn_url" { value = "https://vpn.${var.domain_name}" }
