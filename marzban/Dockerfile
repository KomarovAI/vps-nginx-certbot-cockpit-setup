# Marzban Custom v4.0 - Enhanced with Full Automation
# Based on stable gozargah/marzban:latest with improved automation

FROM gozargah/marzban:latest

# Metadata
LABEL maintainer="KomarovAI <artur.komarovv@gmail.com>"
LABEL version="4.0"
LABEL description="Enhanced Marzban with auto-admin, improved health checks, and XRAY Reality"

# Install additional tools for enhanced automation and health checks
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    gettext-base \
    python3-requests \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Copy initialization scripts
COPY init-scripts/ /opt/init-scripts/
COPY xray_config.json.tpl /opt/templates/

# Make scripts executable
RUN chmod +x /opt/init-scripts/*.sh

# Create entrypoint wrapper with enhanced automation
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Create directories for custom configs and automation
RUN mkdir -p /opt/marzban/custom-configs \
    && mkdir -p /var/lib/marzban \
    && chmod -R 755 /opt/marzban

# Set environment defaults for automation
ENV AUTO_INIT_DB=true
ENV AUTO_CREATE_ADMIN=true
ENV MARZBAN_DB_URL=sqlite:////var/lib/marzban/db.sqlite3
ENV XRAY_JSON=/etc/xray/config.json
ENV XRAY_VLESS_REALITY=true
ENV XRAY_GRPC_ENABLE=true

# Expose standard ports
EXPOSE 8000 2083

# Set custom entrypoint that handles full automation
ENTRYPOINT ["/opt/entrypoint.sh"]
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]