provider "null" {}
provider "tls" {}
# DNSEXIT provider requires API token
provider "dnsexit" {
  api_key = var.dnsexit_api_key
}
