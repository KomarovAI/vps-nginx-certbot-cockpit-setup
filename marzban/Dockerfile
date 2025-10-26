FROM gozargah/marzban:latest

# Install additional tools for initialization
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Copy initialization scripts
COPY init-scripts/ /opt/init-scripts/
COPY xray_config.json.tpl /opt/templates/

# Make scripts executable
RUN chmod +x /opt/init-scripts/*.sh

# Create entrypoint wrapper
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Set custom entrypoint that handles initialization
ENTRYPOINT ["/opt/entrypoint.sh"]
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]