# Переменные Terraform для VPS deployment
# Версия: 3.0 (исправленная)

variable "vps_host" {
  type        = string
  description = "VPS server IP address or hostname"
  
  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$|^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.vps_host))
    error_message = "VPS host must be a valid IP address or domain name."
  }
}

variable "vps_user" {
  type        = string
  default     = "root"
  description = "SSH user for VPS connection"
  
  validation {
    condition     = length(var.vps_user) > 0
    error_message = "VPS user cannot be empty."
  }
}

variable "ssh_private_key" {
  type        = string
  sensitive   = true
  description = "SSH private key for VPS authentication (PEM format)"
  
  validation {
    condition     = can(regex("-----BEGIN.*PRIVATE KEY-----", var.ssh_private_key))
    error_message = "SSH private key must be in PEM format and start with '-----BEGIN.*PRIVATE KEY-----'."
  }
}

variable "domain_name" {
  type        = string
  description = "Primary domain name for the server"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid domain (e.g., example.com)."
  }
}

variable "admin_email" {
  type        = string
  description = "Administrator email for SSL certificates and notifications"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Admin email must be a valid email address."
  }
}

variable "cockpit_password" {
  type        = string
  sensitive   = true
  default     = ""
  description = "Password for Cockpit web interface admin user (optional)"
  
  validation {
    condition     = var.cockpit_password == "" || length(var.cockpit_password) >= 8
    error_message = "Cockpit password must be at least 8 characters long or empty."
  }
}

variable "cockpit_user" {
  type        = string
  default     = "cockpit-admin"
  description = "Username for Cockpit web interface admin user"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9._-]*$", var.cockpit_user))
    error_message = "Cockpit user must start with a letter and contain only letters, numbers, dots, underscores, and hyphens."
  }
}

# Дополнительные опциональные переменные для расширенной конфигурации

variable "enable_fail2ban" {
  type        = bool
  default     = true
  description = "Enable fail2ban for additional security"
}

variable "enable_auto_updates" {
  type        = bool
  default     = true 
  description = "Enable automatic security updates"
}

variable "ssl_email_notifications" {
  type        = bool
  default     = true
  description = "Enable email notifications for SSL certificate renewals"
}

variable "backup_retention_days" {
  type        = number
  default     = 30
  description = "Number of days to retain configuration backups"
  
  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 7 and 365 days."
  }
}

variable "ufw_ssh_rate_limit" {
  type        = bool
  default     = true
  description = "Enable UFW SSH rate limiting"
}

variable "nginx_client_max_body_size" {
  type        = string
  default     = "64M"
  description = "Maximum client request body size for Nginx"
  
  validation {
    condition     = can(regex("^[0-9]+[MmGgKk]?$", var.nginx_client_max_body_size))
    error_message = "Nginx client max body size must be a valid size (e.g., 64M, 1G)."
  }
}

variable "timezone" {
  type        = string
  default     = "UTC"
  description = "System timezone"
  
  validation {
    condition     = can(regex("^[A-Za-z_/]+$", var.timezone))
    error_message = "Timezone must be a valid timezone identifier (e.g., UTC, Europe/Moscow)."
  }
}

# Переменные для расширенного мониторинга
variable "enable_monitoring" {
  type        = bool
  default     = true
  description = "Enable system monitoring and health checks"
}

variable "health_check_interval" {
  type        = number
  default     = 15
  description = "Health check interval in minutes"
  
  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 60
    error_message = "Health check interval must be between 5 and 60 minutes."
  }
}

# Переменные для дополнительной безопасности
variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port number"
  
  validation {
    condition     = var.ssh_port >= 1 && var.ssh_port <= 65535
    error_message = "SSH port must be between 1 and 65535."
  }
}

variable "allowed_ssh_ips" {
  type        = list(string)
  default     = []
  description = "List of IP addresses allowed to connect via SSH (empty = allow all)"
  
  validation {
    condition = alltrue([
      for ip in var.allowed_ssh_ips : can(cidrhost(ip, 0))
    ])
    error_message = "All SSH IPs must be valid CIDR notation (e.g., 192.168.1.1/32)."
  }
}

# Переменные для Docker конфигурации
variable "docker_log_max_size" {
  type        = string
  default     = "10m"
  description = "Maximum Docker container log file size"
}

variable "docker_log_max_file" {
  type        = number
  default     = 3
  description = "Maximum number of Docker log files to retain"
  
  validation {
    condition     = var.docker_log_max_file >= 1 && var.docker_log_max_file <= 10
    error_message = "Docker log max file count must be between 1 and 10."
  }
}