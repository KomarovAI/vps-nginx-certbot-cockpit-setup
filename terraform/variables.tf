variable "vps_host" {
  type        = string
  description = "VPS server IP address or hostname"
}

variable "vps_user" {
  type        = string
  default     = "root"
  description = "SSH user for VPS connection"
}

variable "ssh_private_key" {
  type        = string
  sensitive   = true
  description = "SSH private key for VPS authentication"
}

variable "domain_name" {
  type        = string
  description = "Primary domain name for the server"
}

variable "admin_email" {
  type        = string
  description = "Administrator email for SSL certificates and notifications"
}

variable "cockpit_password" {
  type        = string
  sensitive   = true
  description = "Password for Cockpit web interface admin user"
}

variable "marzban_username" {
  type        = string
  default     = "admin"
  description = "Marzban VPN panel admin username"
}

variable "marzban_password" {
  type        = string
  sensitive   = true
  description = "Marzban VPN panel admin password"
}