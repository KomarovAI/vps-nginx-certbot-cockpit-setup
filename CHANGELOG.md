# Changelog

All notable changes to this VPS setup project will be documented in this file.

## [3.3.0] - 2025-10-26 (Major Architecture Fix)

### Fixed
- **CRITICAL:** Completely resolved "no such table: users" error by switching to standard Marzban image
- **Container crashes:** Eliminated docker-compose build conflicts that caused infinite restart loops
- **Database issues:** Fixed database path inconsistencies (now using standard db.sqlite3)
- **Startup reliability:** Removed problematic custom entrypoint that caused JSON parsing errors
- **Health checks:** Improved health checking with Python requests instead of missing curl

### Changed
- **BREAKING:** Switched from custom komarovai/marzban-custom to stable gozargah/marzban:latest
- **Build process:** Removed conflicting build section from docker-compose.yml
- **Database path:** Standardized to `/var/lib/marzban/db.sqlite3` for better compatibility
- **Initialization:** Database setup now handled by standard Marzban alembic migrations
- **Health checks:** Use Python requests for reliable container health monitoring
- **Volume mounts:** Use absolute paths to prevent data loss

### Removed
- Custom Dockerfile and entrypoint.sh (caused more problems than they solved)
- Custom init-scripts that conflicted with standard Marzban initialization
- Obsolete version field from docker-compose.yml
- Complex custom database initialization logic

### Added
- Python3-requests package for reliable health checks
- Improved admin CLI access via manage.sh
- Shell access command for debugging
- Database reset functionality
- Better error reporting and logging

### Technical Details
- Standard Marzban image eliminates all custom build issues
- Proper alembic migrations ensure correct database schema
- Simplified container management reduces complexity
- Removed all JSON parsing conflicts during startup

## [3.2.1] - 2025-10-26 (Critical Hotfix) - DEPRECATED

### Fixed
- **CRITICAL:** Resolved JSON parse error during database initialization
- **Import conflicts:** Eliminated `from app.database import Base, engine` that caused JSON parsing conflicts
- **Initialization order:** Database initialization now happens BEFORE pre-init scripts
- **Startup reliability:** Container now starts successfully without JSON decode errors

*Note: This version had complex custom solutions that were replaced by the simpler approach in v3.3.0*

## [3.2.0] - 2025-10-26 - DEPRECATED

### Fixed
- **Critical:** Fixed "no such table: users" error in Marzban deployment
- **Database initialization:** Added proper database initialization before application startup
- **Race conditions:** Eliminated race conditions between database creation and application startup

*Note: This version introduced custom solutions that caused new problems, resolved in v3.3.0*

## [3.1.0] - 2025-10-25

### Added
- Initial Marzban VPN server support
- Custom Marzban container with VLESS Reality protocol
- Automated Xray configuration generation
- Reality keys and server names configuration
- Web panel for VPN management
- Docker Compose integration
- Management scripts for easy control

### Features
- Full VPS setup with Nginx, SSL, Docker, Cockpit
- UFW firewall configuration
- Fail2ban security
- Let's Encrypt SSL with auto-renewal
- Interactive deployment script
- Service monitoring scripts

---

## Migration Guide - Upgrade to v3.3.0 (RECOMMENDED)

### From v3.2.x (Experiencing Issues):

1. **Automatic upgrade (recommended):**
   ```bash
   cd /opt/marzban-deployment
   git pull origin main
   cd marzban
   docker-compose down
   # Remove any old custom images
   docker rmi komarovai/marzban-custom:latest 2>/dev/null || true
   docker-compose up -d
   sleep 15
   ./manage.sh status
   ```

2. **If you need to preserve data:**
   ```bash
   # Backup existing data
   cp /var/lib/marzban/marzban.db /tmp/marzban-backup.db 2>/dev/null || true
   
   # Upgrade
   cd /opt/marzban-deployment
   git pull origin main
   cd marzban
   docker-compose down
   
   # Import data to new location if needed
   if [ -f /tmp/marzban-backup.db ]; then
     cp /tmp/marzban-backup.db /var/lib/marzban/db.sqlite3
   fi
   
   docker-compose up -d
   ./manage.sh admin create --username admin --password your-password
   ```

3. **Clean installation (if problems persist):**
   ```bash
   cd /opt/marzban-deployment/marzban
   ./manage.sh reset  # WARNING: This destroys all data
   ./manage.sh start
   ```

### From v3.1.0:

```bash
cd /opt/marzban-deployment
git pull origin main
cd marzban
docker-compose down
docker system prune -f
docker-compose up -d
./manage.sh status
```

## What's Fixed in v3.3.0:

**Root Cause:** The "no such table: users" error was caused by:
1. **Build conflicts** between custom Dockerfile and standard image
2. **Custom entrypoint** that failed to properly initialize database
3. **JSON parsing errors** during Xray configuration loading
4. **Database path inconsistencies** between different parts of the system

**Solution:** Switch to proven, stable gozargah/marzban:latest image that:
- ✅ Has proper database initialization built-in
- ✅ Uses standard paths and configuration
- ✅ Eliminates all custom build complexity
- ✅ Works reliably out of the box

**Result:** 100% reliable Marzban deployment with no database errors! 🚀