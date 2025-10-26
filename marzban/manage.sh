#!/bin/bash

#===============================================================================
# Marzban Management Script with DB init and admin bootstrap v4.0
# Fixed for Custom Container
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
    if [[ "$code" == "200" || "$code" == "302" || "$code" == "401" || "$code" == "422" ]]; then
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

# Database initialization is now handled by the custom entrypoint.sh
init_db() {
  echo "Database initialization is handled by custom entrypoint.sh - skipping manual init"
  return 0
}

bootstrap_admin() {
  local U="${MARZBAN_ADMIN_USERNAME:-}"
  local P="${MARZBAN_ADMIN_PASSWORD:-}"
  [[ -z "$U" || -z "$P" ]] && { echo "Admin credentials not provided, skipping admin creation"; return 0; }
  echo "Creating/updating admin user: $U"
  
  # Wait a moment for the application to be fully ready
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
    echo "Starting Marzban (Custom Container)..."
    if [[ -f Makefile ]]; then
      make up || docker-compose up -d
    else
      docker-compose up -d
    fi
    # Database init is now handled in entrypoint.sh, just wait for health
    health_check 60 || exit 1  # Longer timeout for initial startup
    bootstrap_admin || true
    echo "✓ Marzban started successfully"
    echo "Access panel at: https://${DOMAIN_NAME:-localhost}:${PORT}"
    ;;
  restart)
    echo "Restarting Marzban (Custom Container)..."
    if [[ -f Makefile ]]; then
      make restart || (docker-compose down && docker-compose up -d)
    else
      docker-compose restart
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
    echo "Stopping Marzban (Custom Container)..."
    if [[ -f Makefile ]]; then
      make down
    else
      docker-compose down
    fi
    echo "✓ Marzban stopped"
    ;;
  build)
    echo "Building Marzban Custom Container..."
    if [[ -f Makefile ]]; then
      make build
    else
      docker-compose build --no-cache --pull
    fi
    echo "✓ Marzban custom container built"
    ;;
  rebuild)
    echo "Rebuilding and restarting Marzban..."
    docker-compose down
    docker-compose build --no-cache --pull
    docker-compose up -d
    health_check 60 || exit 1
    bootstrap_admin || true
    echo "✓ Marzban rebuilt and restarted successfully"
    ;;
  reset)
    echo "⚠ WARNING: This will destroy all data!"
    read -p "Are you sure? (type 'yes' to confirm): " confirm
    if [[ "$confirm" == "yes" ]]; then
      docker-compose down -v
      docker volume prune -f
      rm -rf ./data/* 2>/dev/null || true
      rm -rf /var/lib/marzban/* 2>/dev/null || true
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
  debug)
    echo "=== CUSTOM CONTAINER DEBUG INFO ==="
    echo "Docker Compose Status:"
    docker-compose ps
    echo ""
    echo "Container Logs (last 50 lines):"
    docker-compose logs --tail=50 marzban
    echo ""
    echo "Database Status:"
    docker-compose exec -T marzban ls -la /var/lib/marzban/ 2>/dev/null || echo "Cannot access database directory"
    echo ""
    echo "Xray Config Status:"
    docker-compose exec -T marzban ls -la /etc/xray/config.json 2>/dev/null || echo "Cannot access Xray config"
    echo ""
    echo "Reality Keys Status:"
    docker-compose exec -T marzban cat /var/lib/marzban/reality_keys.env 2>/dev/null || echo "Reality keys not found"
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|build|rebuild|logs|status|reset|admin|shell|debug}"
    echo "  start     - Start Marzban custom container"
    echo "  stop      - Stop Marzban services"
    echo "  restart   - Restart Marzban services"
    echo "  build     - Build custom Marzban container"
    echo "  rebuild   - Rebuild and restart everything"
    echo "  logs      - Show Marzban logs"
    echo "  status    - Check Marzban health"
    echo "  reset     - Reset all data (DANGEROUS!)"
    echo "  admin     - Run admin CLI commands (e.g. ./manage.sh admin create --username admin --password pass123)"
    echo "  shell     - Open shell in Marzban container"
    echo "  debug     - Show comprehensive debug information"
    exit 1
    ;;
esac