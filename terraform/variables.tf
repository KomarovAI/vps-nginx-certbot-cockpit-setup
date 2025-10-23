variable "vps_host" {
  type = string
}

variable "vps_user" {
  type    = string
  default = "root"
}

variable "ssh_private_key" {
  type      = string
  sensitive = true
}

variable "domain_name" {
  type = string
}

variable "admin_email" {
  type = string
}

variable "cockpit_password" {
  type      = string
  sensitive = true
}

variable "marzban_username" {
  type    = string
  default = "admin"
}

variable "marzban_password" {
  type      = string
  sensitive = true
}

variable "dnsexit_api_key" {
  type      = string
  sensitive = true
}

variable "root_ip" {
  type    = string
  default = "31.59.58.96"
}
