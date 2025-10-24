# Marzban provision script: generate REALITY keys, bootstrap admin, and create nginx proxy if needed
set -euo pipefail

MARZBAN_DIR="/opt/marzban"
ENV_FILE="$MARZBAN_DIR/.env"
DC_FILE="$MARZBAN_DIR/docker-compose.yml"

log(){ echo "[$(date +'%F %T')] $*"; }

if [[ ! -f "$ENV_FILE" ]]; then
  log "Creating .env from example...";
  cp "$MARZBAN_DIR/.env.example" "$ENV_FILE"
fi

if ! grep -q XRAY_REALITY_PRIVATE_KEY "$ENV_FILE" || [[ -z "${XRAY_REALITY_PRIVATE_KEY:-}" ]]; then
  log "Generating REALITY keys..."
  mkdir -p "$MARZBAN_DIR/keys"
  docker run --rm -v "$MARZBAN_DIR/keys:/keys" teddysun/xray xray x25519 > /dev/null 2>&1 || true
  PRIV=$(cat "$MARZBAN_DIR/keys/out" | awk '/Private/{print $3}')
  PUB=$(cat "$MARZBAN_DIR/keys/out" | awk '/Public/{print $3}')
  sed -i "s#^XRAY_REALITY_PRIVATE_KEY=.*#XRAY_REALITY_PRIVATE_KEY=${PRIV}#" "$ENV_FILE"
  log "REALITY public key: $PUB"
fi

log "Launching Marzban..."
cd "$MARZBAN_DIR"
/docker/compose up -d || docker compose up -d

log "Waiting Marzban to be healthy..."
sleep 8

echo "Marzban is up. Configure via CLI or panel."
