# DNSEXIT DNS records for production
# Requires DNSEXIT_API_KEY secret (provided to TF_VAR_dnsexit_api_key)

resource "dnsexit_record" "root_a" {
  hostname = "botinger789298.work.gd"
  type     = "A"
  content  = var.root_ip
  ttl      = 300
}

resource "dnsexit_record" "vpn_a" {
  hostname = "vpn.botinger789298.work.gd"
  type     = "A"
  content  = var.root_ip
  ttl      = 300
}

resource "dnsexit_record" "cockpit_a" {
  hostname = "cockpit.botinger789298.work.gd"
  type     = "A"
  content  = var.root_ip
  ttl      = 300
}
