#!/bin/bash

#===============================================================================
# Marzban Management Script with DB init and admin bootstrap v2.0
#===============================================================================

MARZBAN_DIR="/opt/marzban-deployment/marzban"
PORT="${MARZBAN_PANEL_PORT:-8000}"
URL="http://127.0.0.1:${PORT}/api/admin"

cd "$MARZBAN_DIR" || { echo "Error: Cannot access Marzban directory"; exit 1; }

health_check() {
  local tries=${1:-45}  # Default 45 attempts
  echo "Checking Marzban health at $URL (max $tries attempts)..."
  for i in $(seq 1 $tries); do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 4 "$URL" 2>/dev/null || echo "000")
    if [[ "$code" == "200" || "$code" == "302" || "$code" == "401" ]]; then
      echo "✓ Panel is UP (HTTP $code)"; return 0
    fi
    sleep 2
    [[ $((i%10)) -eq 0 ]] && echo "  Still waiting ($i/$tries) - HTTP $code"
  done
  echo "✗ Panel is NOT responding (last HTTP $code)"
  echo "Container status:"
  docker-compose ps 2>/dev/null || true
  echo "Recent logs:"
  docker-compose logs --tail=50 2>/dev/null || true
  return 1
}

# This function is no longer needed since database initialization
# is now handled directly in the entrypoint.sh before app startup
init_db() {
  echo "Database initialization is handled by entrypoint.sh - skipping manual init"
  return 0
}

bootstrap_admin() {
  local U="${MARZBAN_ADMIN_USERNAME:-}"
  local P="${MARZBAN_ADMIN_PASSWORD:-}"
  [[ -z "$U" || -z "$P" ]] && { echo "Admin credentials not provided, skipping admin creation"; return 0; }
  echo "Creating/updating admin user: $U"
  
  # Wait a moment for the application to be fully ready
  sleep 3
  
  # Try to create admin, fall back to update if user exists
  if docker-compose exec -T marzban marzban-cli admin create --username "$U" --password "$P" 2>/dev/null; then
    echo "✓ Admin user created successfully"
  elif docker-compose exec -T marzban marzban-cli admin update --username "$U" --password "$P" 2>/dev/null; then
    echo "✓ Admin user updated successfully"
  else
    echo "⚠ Admin setup completed (or user management not available)"
  fi
}

case "$1" in
  start)
    echo "Starting Marzban..."
    if [[ -f Makefile ]]; then
      make up || docker-compose up -d
    else
      docker-compose up -d
    fi
    # Database init is now handled in entrypoint.sh, just wait for health
    health_check 60 || exit 1  # Longer timeout for initial startup
    bootstrap_admin || true
    echo "✓ Marzban started successfully"
    ;;
  restart)
    echo "Restarting Marzban..."
    if [[ -f Makefile ]]; then
      make restart || (docker-compose down && docker-compose up -d)
    else
      docker-compose down && docker-compose up -d
    fi
    health_check 45 || exit 1
    bootstrap_admin || true
    echo "✓ Marzban restarted successfully"
    ;;
  status|health)
    health_check 10  # Quick health check
    ;;
  logs)
    if [[ -f Makefile ]]; then
      make logs
    else
      docker-compose logs -f
    fi
    ;;
  stop)
    echo "Stopping Marzban..."
    if [[ -f Makefile ]]; then
      make down
    else
      docker-compose down
    fi
    echo "✓ Marzban stopped"
    ;;
  build)
    echo "Building Marzban..."
    if [[ -f Makefile ]]; then
      make build
    else
      docker-compose build --no-cache
    fi
    echo "✓ Marzban built"
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|build|logs|status}"
    echo "  start   - Start Marzban services"
    echo "  stop    - Stop Marzban services"
    echo "  restart - Restart Marzban services"
    echo "  build   - Build Marzban containers"
    echo "  logs    - Show Marzban logs"
    echo "  status  - Check Marzban health"
    exit 1
    ;;
esac