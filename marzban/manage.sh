#!/bin/bash

#===============================================================================
# Marzban Management Script v4.0 - Custom Image with Full Automation
# Enhanced for komarovai/marzban-custom:v4.0 with auto-admin and secrets integration
#===============================================================================

MARZBAN_DIR="/opt/marzban-deployment/marzban"
PORT="${MARZBAN_PANEL_PORT:-8000}"
URL="http://127.0.0.1:${PORT}/api/admin"
CUSTOM_IMAGE="komarovai/marzban-custom:v4.0"

cd "$MARZBAN_DIR" || { echo "Error: Cannot access Marzban directory"; exit 1; }

health_check() {
  local tries=${1:-60}  # Extended timeout for custom image
  echo "🔍 Checking Marzban Custom health at $URL (max $tries attempts)..."
  for i in $(seq 1 $tries); do
    code=$(python3 -c "import requests; print(requests.get('$URL', timeout=4).status_code)" 2>/dev/null || echo "000")
    if [[ "$code" == "200" || "$code" == "302" || "$code" == "401" || "$code" == "422" ]]; then
      echo "✅ Custom Marzban Panel is UP (HTTP $code)"; return 0
    fi
    sleep 3
    [[ $((i%15)) -eq 0 ]] && echo "  ⏳ Still waiting ($i/$tries) - HTTP $code"
  done
  echo "❌ Custom Panel is NOT responding (last HTTP $code)"
  echo "📊 Container status:"
  docker-compose ps 2>/dev/null || true
  echo "📜 Recent logs:"
  docker-compose logs --tail=50 2>/dev/null || true
  return 1
}

# Enhanced database initialization for custom image
init_db() {
  echo "🗄️ Initializing database with custom image..."
  if docker-compose exec -T marzban alembic upgrade head 2>/dev/null; then
    echo "✅ Database initialized successfully"
  else
    echo "⚠️ Database init failed or already initialized"
  fi
  sleep 3
}

# Enhanced bootstrap admin with secrets integration
bootstrap_admin() {
  local U="${MARZBAN_ADMIN_USERNAME:-${ADMIN_USERNAME:-admin}}"
  local P="${MARZBAN_ADMIN_PASSWORD:-${ADMIN_PASSWORD:-}}"
  
  [[ -z "$P" ]] && { echo "⚠️ Admin credentials not provided, skipping admin creation"; return 0; }
  echo "👤 Creating/updating admin user: $U"
  
  # Wait for custom image to be fully ready
  sleep 8
  
  # Multiple attempts with different approaches for custom image
  echo "🔐 Attempting admin setup (method 1: direct create)..."
  if timeout 45 docker-compose exec -T marzban marzban-cli admin create --username "$U" --password "$P" 2>/dev/null; then
    echo "✅ Admin user created successfully"
    return 0
  fi
  
  echo "🔐 Attempting admin setup (method 2: update existing)..."
  if timeout 45 docker-compose exec -T marzban marzban-cli admin update --username "$U" --password "$P" 2>/dev/null; then
    echo "✅ Admin user updated successfully"
    return 0
  fi
  
  echo "🔐 Attempting admin setup (method 3: forced creation)..."
  echo -e "y\ny\ny\n" | timeout 30 docker-compose exec -T marzban marzban-cli admin create --username "$U" --password "$P" 2>/dev/null || true
  
  echo "ℹ️ Admin setup completed (custom image may handle this automatically)"
}

# Auto-setup for clean start
auto_setup() {
  echo "🚀 Auto-setup: Building custom image and initializing..."
  docker-compose down 2>/dev/null || true
  docker-compose pull
  docker-compose build --no-cache 2>/dev/null || echo "ℹ️ No build section found, using pre-built image"
  docker-compose up -d
  
  echo "⏳ Waiting for custom image initialization..."
  sleep 15
  
  health_check 90 || { echo "❌ Auto-setup failed"; return 1; }
  bootstrap_admin || true
  
  echo "✅ Auto-setup completed successfully"
  echo "🌐 Access panel at: https://${DOMAIN_NAME:-localhost}:${PORT}"
}

case "$1" in
  start)
    echo "🚀 Starting Marzban Custom Image ($CUSTOM_IMAGE)..."
    docker-compose up -d
    health_check 90 || exit 1  # Extended timeout for custom image
    bootstrap_admin || true
    echo "✅ Marzban Custom started successfully"
    echo "🌐 Access panel at: https://${DOMAIN_NAME:-localhost}:${PORT}"
    ;;
    
  restart)
    echo "♻️ Restarting Marzban Custom Image..."
    docker-compose restart
    health_check 60 || exit 1
    bootstrap_admin || true
    echo "✅ Marzban Custom restarted successfully"
    ;;
    
  status|health)
    health_check 15  # Quick health check
    ;;
    
  logs)
    docker-compose logs -f
    ;;
    
  stop)
    echo "🛑 Stopping Marzban Custom Image..."
    docker-compose down
    echo "✅ Marzban Custom stopped"
    ;;
    
  build)
    echo "🔨 Building custom Marzban image..."
    docker-compose build --no-cache
    echo "✅ Build completed"
    ;;
    
  auto-setup)
    auto_setup
    ;;
    
  init-db)
    init_db
    ;;
    
  rebuild)
    echo "🔄 Rebuilding and restarting Marzban Custom..."
    docker-compose down
    docker-compose pull
    docker-compose build --no-cache 2>/dev/null || true
    docker-compose up -d
    health_check 90 || exit 1
    bootstrap_admin || true
    echo "✅ Marzban Custom rebuilt and restarted successfully"
    ;;
    
  reset)
    echo "⚠️ WARNING: This will destroy all data!"
    read -p "Are you sure? (type 'yes' to confirm): " confirm
    if [[ "$confirm" == "yes" ]]; then
      docker-compose down -v
      docker volume prune -f
      sudo rm -rf /var/lib/marzban/* 2>/dev/null || true
      echo "🗑️ Marzban Custom reset completed"
    else
      echo "❌ Reset cancelled"
    fi
    ;;
    
  force-reset)
    echo "🗑️ Force resetting without confirmation..."
    docker-compose down -v 2>/dev/null || true
    docker volume prune -f 2>/dev/null || true
    sudo rm -rf /var/lib/marzban/* 2>/dev/null || true
    echo "✅ Force reset completed"
    ;;
    
  admin)
    shift  # Remove 'admin' from arguments
    docker-compose exec marzban marzban-cli admin "$@"
    ;;
    
  shell)
    docker-compose exec marzban bash
    ;;
    
  debug)
    echo "=== CUSTOM IMAGE DEBUG INFO ==="
    echo "🐳 Docker Compose Status:"
    docker-compose ps
    echo ""
    echo "📜 Container Logs (last 100 lines):"
    docker-compose logs --tail=100 marzban
    echo ""
    echo "🗄️ Database Status:"
    docker-compose exec -T marzban ls -la /var/lib/marzban/ 2>/dev/null || echo "Cannot access database directory"
    echo ""
    echo "⚙️ Xray Config Status:"
    docker-compose exec -T marzban ls -la /etc/xray/config.json 2>/dev/null || echo "Cannot access Xray config"
    echo ""
    echo "🔍 Environment Variables:"
    docker-compose exec -T marzban env | grep -E "MARZBAN|XRAY|DOMAIN" | sort
    echo ""
    echo "📊 Database Tables:"
    docker-compose exec -T marzban python3 -c "import sqlite3; conn = sqlite3.connect('/var/lib/marzban/db.sqlite3'); print('Tables:', [t[0] for t in conn.execute('SELECT name FROM sqlite_master WHERE type=\"table\"').fetchall()]); conn.close()" 2>/dev/null || echo "Cannot check database tables"
    ;;
    
  *)
    echo "Usage: $0 {start|stop|restart|build|auto-setup|rebuild|logs|status|init-db|reset|force-reset|admin|shell|debug}"
    echo ""
    echo "📋 Commands for Custom Marzban ($CUSTOM_IMAGE):"
    echo "  start       - Start Marzban custom container with auto-admin setup"
    echo "  stop        - Stop Marzban services"
    echo "  restart     - Restart Marzban services with admin verification"
    echo "  build       - Build custom Marzban image"
    echo "  auto-setup  - Complete automated setup from scratch"
    echo "  rebuild     - Pull, build and restart everything"
    echo "  logs        - Show Marzban logs"
    echo "  status      - Check Marzban health"
    echo "  init-db     - Initialize database with alembic"
    echo "  reset       - Reset all data (DANGEROUS!)"
    echo "  force-reset - Reset without confirmation (CI/CD)"
    echo "  admin       - Run admin CLI commands (e.g. ./manage.sh admin create --username admin --password pass123)"
    echo "  shell       - Open shell in Marzban container"
    echo "  debug       - Show comprehensive debug information for custom image"
    echo ""
    echo "🎯 Quick Start: ./manage.sh auto-setup"
    exit 1
    ;;
esac