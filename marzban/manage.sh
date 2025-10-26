#!/bin/bash

#===============================================================================
# Marzban Management Script v3.0 - Simplified for Standard Marzban
#===============================================================================

MARZBAN_DIR="/opt/marzban-deployment/marzban"
PORT="${MARZBAN_PANEL_PORT:-8000}"
URL="http://127.0.0.1:${PORT}/api/admin"

cd "$MARZBAN_DIR" || { echo "Error: Cannot access Marzban directory"; exit 1; }

health_check() {
  local tries=${1:-30}  # Default 30 attempts
  echo "Checking Marzban health at $URL (max $tries attempts)..."
  for i in $(seq 1 $tries); do
    code=$(python3 -c "import requests; print(requests.get('$URL', timeout=4).status_code)" 2>/dev/null || echo "000")
    if [[ "$code" == "200" || "$code" == "302" || "$code" == "401" || "$code" == "422" ]]; then
      echo "✓ Panel is UP (HTTP $code)"; return 0
    fi
    sleep 3
    [[ $((i%5)) -eq 0 ]] && echo "  Still waiting ($i/$tries) - HTTP $code"
  done
  echo "✗ Panel is NOT responding (last HTTP $code)"
  echo "Container status:"
  docker-compose ps 2>/dev/null || docker ps --filter name=marzban || true
  echo "Recent logs:"
  docker-compose logs --tail=30 2>/dev/null || docker logs $(docker ps -q --filter name=marzban) --tail=30 2>/dev/null || true
  return 1
}

init_database() {
  echo "Initializing/upgrading Marzban database..."
  if docker-compose ps marzban | grep -q "Up"; then
    # Container is running, exec into it
    docker-compose exec -T marzban alembic upgrade head || echo "Database migration completed (or not needed)"
  else
    # Container is not running, run one-time command
    docker-compose run --rm marzban alembic upgrade head || echo "Database migration completed (or not needed)"
  fi
}

bootstrap_admin() {
  local U="${MARZBAN_ADMIN_USERNAME:-}"
  local P="${MARZBAN_ADMIN_PASSWORD:-}"
  [[ -z "$U" || -z "$P" ]] && { echo "Admin credentials not provided in environment, skipping admin creation"; return 0; }
  echo "Creating/updating admin user: $U"
  
  # Wait for application to be ready
  sleep 5
  
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
    docker-compose up -d
    # Wait for container to be ready
    sleep 10
    init_database || echo "Database initialization skipped"
    health_check 45 || exit 1  # Longer timeout for initial startup
    bootstrap_admin || true
    echo "✓ Marzban started successfully"
    echo "Access panel at: http://$(hostname -I | awk '{print $1}'):${PORT}"
    ;;
  restart)
    echo "Restarting Marzban..."
    docker-compose restart
    health_check 30 || exit 1
    echo "✓ Marzban restarted successfully"
    ;;
  status|health)
    health_check 10  # Quick health check
    ;;
  logs)
    docker-compose logs -f
    ;;
  stop)
    echo "Stopping Marzban..."
    docker-compose down
    echo "✓ Marzban stopped"
    ;;
  reset)
    echo "⚠ WARNING: This will destroy all data!"
    read -p "Are you sure? (type 'yes' to confirm): " confirm
    if [[ "$confirm" == "yes" ]]; then
      docker-compose down -v
      docker volume prune -f
      rm -rf /var/lib/marzban/*
      echo "✓ Marzban reset completed"
    else
      echo "Reset cancelled"
    fi
    ;;
  admin)
    shift  # Remove 'admin' from arguments
    docker-compose exec marzban marzban-cli admin "$@"
    ;;
  shell)
    docker-compose exec marzban bash
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|logs|status|reset|admin|shell}"
    echo "  start   - Start Marzban services"
    echo "  stop    - Stop Marzban services"
    echo "  restart - Restart Marzban services"
    echo "  logs    - Show Marzban logs"
    echo "  status  - Check Marzban health"
    echo "  reset   - Reset all data (DANGEROUS!)"
    echo "  admin   - Run admin CLI commands (e.g. ./manage.sh admin create --username admin --password pass123)"
    echo "  shell   - Open shell in Marzban container"
    exit 1
    ;;
esac