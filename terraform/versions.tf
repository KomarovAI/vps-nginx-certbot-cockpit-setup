terraform {
  required_version = ">= 1.6.0"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    dnsexit = {
      source  = "DNSEXIT/dnsexit"
      version = "~> 0.1"
    }
  }
}
