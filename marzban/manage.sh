#!/bin/bash

# Marzban Management Script with extended health

MARZBAN_DIR="/opt/marzban-deployment/marzban"
PORT="${MARZBAN_PANEL_PORT:-8000}"
URL="http://127.0.0.1:${PORT}/api/admin"

cd "$MARZBAN_DIR" || { echo "Error: Cannot access Marzban directory"; exit 1; }

health_check() {
  echo "Checking Marzban panel at $URL ..."
  for i in {1..20}; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 "$URL" || echo "000")
    if [[ "$code" == "200" || "$code" == "302" || "$code" == "401" ]]; then
      echo "Panel is UP (HTTP $code)"
      return 0
    fi
    sleep 2
  done
  echo "Panel is NOT responding (last HTTP $code)"
  docker-compose ps || true
  docker-compose logs --tail=80 || true
  return 1
}

case "$1" in
  start)
    echo "Starting Marzban..."; [[ -f Makefile ]] && make up || docker-compose up -d; health_check ;;
  stop)
    echo "Stopping Marzban..."; [[ -f Makefile ]] && make down || docker-compose down ;;
  restart)
    echo "Restarting Marzban..."; [[ -f Makefile ]] && make restart || (docker-compose down && docker-compose up -d); health_check ;;
  logs)
    echo "Showing Marzban logs..."; [[ -f Makefile ]] && make logs || docker-compose logs -f ;;
  status|health)
    health_check ;;
  *)
    echo "Usage: $0 {start|stop|restart|logs|status}"; exit 1 ;;
esac
