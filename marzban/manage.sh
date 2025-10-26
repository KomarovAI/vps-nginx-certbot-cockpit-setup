#!/bin/bash

#===============================================================================
# Marzban Management Script with DB init and admin bootstrap
#===============================================================================

MARZBAN_DIR="/opt/marzban-deployment/marzban"
PORT="${MARZBAN_PANEL_PORT:-8000}"
URL="http://127.0.0.1:${PORT}/api/admin"

cd "$MARZBAN_DIR" || { echo "Error: Cannot access Marzban directory"; exit 1; }

health_check() {
  for i in {1..40}; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 "$URL" || echo "000")
    if [[ "$code" == "200" || "$code" == "302" || "$code" == "401" ]]; then
      echo "Panel is UP (HTTP $code)"; return 0
    fi
    sleep 2
  done
  echo "Panel is NOT responding (last HTTP $code)"
  docker-compose ps || true
  docker-compose logs --tail=120 || true
  return 1
}

init_db() {
  echo "Initializing database (if needed)..."
  # Try alembic if present
  if docker-compose exec -T marzban bash -lc "command -v alembic >/dev/null 2>&1"; then
    docker-compose exec -T marzban alembic upgrade head || true
  fi
  # Fallback: try app's built-in migration if available
  docker-compose exec -T marzban bash -lc "python - <<'PY' || true
try:
    from app.database import init_db
    init_db()
    print('init_db() executed')
except Exception as e:
    print('init_db fallback skipped:', e)
PY"
}

bootstrap_admin() {
  local U="${MARZBAN_ADMIN_USERNAME:-}"
  local P="${MARZBAN_ADMIN_PASSWORD:-}"
  [[ -z "$U" || -z "$P" ]] && { echo "Admin creds not provided, skip"; return 0; }
  echo "Creating/updating admin: $U"
  docker-compose exec -T marzban marzban-cli admin create --username "$U" --password "$P" 2>/dev/null || \
  docker-compose exec -T marzban marzban-cli admin update --username "$U" --password "$P" 2>/dev/null || \
  echo "Admin bootstrap done (or not required)"
}

case "$1" in
  start)
    echo "Starting Marzban..."
    [[ -f Makefile ]] && make up || docker-compose up -d
    init_db || true
    health_check || exit 1
    bootstrap_admin || true
    ;;
  restart)
    echo "Restarting Marzban..."
    [[ -f Makefile ]] && make restart || (docker-compose down && docker-compose up -d)
    init_db || true
    health_check || exit 1
    bootstrap_admin || true
    ;;
  status|health)
    health_check ;;
  logs)
    [[ -f Makefile ]] && make logs || docker-compose logs -f ;;
  stop)
    [[ -f Makefile ]] && make down || docker-compose down ;;
  *)
    echo "Usage: $0 {start|stop|restart|logs|status}"; exit 1 ;;
esac
