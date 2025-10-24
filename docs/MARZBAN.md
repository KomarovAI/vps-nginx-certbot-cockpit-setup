# Marzban (VLESS REALITY) for Russia — Production Setup

This adds Marzban with Xray VLESS REALITY tuned for the Russian network environment.

## What you get
- VLESS REALITY over 443 with SNI fronting
- Host networking for low latency and fewer NAT issues
- Key generation helper and .env template
- Ready to integrate with existing Nginx and SSL

## Files
- marzban/docker-compose.yml — services (marzban, keygen)
- marzban/.env.example — required environment
- marzban/provision.sh — helper to generate REALITY keys and start

## Prerequisites
- Docker + Docker Compose already installed (part of this repo)
- A domain pointing to your server’s IP (A record)

## Quick Start

```bash
# copy env and edit secrets
cp marzban/.env.example marzban/.env
nano marzban/.env  # set DOMAIN_NAME, XRAY_REALITY_* and admin creds

# start marzban
cd marzban
docker compose --env-file .env up -d

# show logs
docker compose logs -f
```

## Best practice for REALITY in RU
- Use SNI list with highly available CDNs: `www.cloudflare.com,images.unsplash.com`
- Use 2+ short IDs: `0123456789abcdef,1122334455667788`
- Keep panel on HTTPS (443) and avoid obvious fingerprints
- Prefer host networking with strict UFW rules

## UFW additions
```bash
ufw allow 443/tcp comment "Marzban VLESS REALITY"
ufw allow 443/udp comment "QUIC"
```

## Cockpit coexistence
- Cockpit remains on 9090 (nginx not required for Marzban REALITY)
- If you want Marzban panel on subdomain via Nginx, add a proxy server block and Certbot

## Terraform integration (optional)
- Copy `marzban/` into `terraform/files/` and add a remote-exec block to run `docker compose up -d`

## Security notes
- Keep `.env` outside VCS
- Rotate short IDs periodically
- Monitor with `docker compose ps` and logs
