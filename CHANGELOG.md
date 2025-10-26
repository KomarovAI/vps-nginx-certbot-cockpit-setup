# Changelog

All notable changes to this VPS setup project will be documented in this file.

## [3.2.0] - 2025-10-26

### Fixed
- **Critical:** Fixed "no such table: users" error in Marzban deployment
- **Database initialization:** Added proper database initialization before application startup
- **Race conditions:** Eliminated race conditions between database creation and application startup

### Added
- Database initialization in `marzban/entrypoint.sh` with fallback mechanisms
- Alembic migration support with Python `Base.metadata.create_all()` fallback
- Enhanced error handling and logging for database initialization
- Improved health check timeouts (60 attempts for initial startup)
- Better admin user creation process with automatic retry logic

### Changed
- **Breaking:** Database initialization moved from `install.sh` to container entrypoint
- Extended health check timeout from 45 to 60 attempts for initial deployment
- Improved logging throughout the deployment process
- Enhanced `manage.sh` with build command and better error reporting
- Updated README.md with troubleshooting guide for database issues

### Technical Details
- Modified `marzban/entrypoint.sh` to initialize database before uvicorn startup
- Added database file existence and size checks before initialization
- Implemented proper error handling for both alembic and direct SQLAlchemy approaches
- Enhanced container startup sequence to ensure database readiness

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

### Migration Guide v3.1 → v3.2

If you're upgrading from v3.1 and experiencing the "no such table: users" error:

1. **Automatic fix (recommended):**
   ```bash
   cd /opt/marzban-deployment
   git pull origin main
   cd marzban
   ./manage.sh build
   ./manage.sh restart
   ```

2. **Manual verification:**
   ```bash
   cd /opt/marzban-deployment/marzban
   ./manage.sh logs  # Check for successful database initialization
   ./manage.sh status  # Verify panel is responding
   ```

3. **If issues persist:**
   ```bash
   cd /opt/marzban-deployment/marzban
   docker-compose down
   docker-compose build --no-cache
   ./manage.sh start
   ```

### What Changed in Database Handling:

**Before (v3.1):**
- Database initialization happened after container startup
- Race condition between app startup and DB creation
- Manual `docker exec` commands for migrations

**After (v3.2):**
- Database initialization happens in container entrypoint
- DB tables created before application starts
- Automatic fallback from alembic to SQLAlchemy if needed
- No race conditions, reliable startup every time