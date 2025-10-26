.PHONY: build up down restart logs shell clean health

# Docker Compose commands
build:
	@echo "Building Marzban custom container..."
	docker-compose build --no-cache

up:
	@echo "Starting Marzban services..."
	docker-compose up -d

down:
	@echo "Stopping Marzban services..."
	docker-compose down

restart: down up
	@echo "Marzban services restarted"

logs:
	@echo "Showing Marzban logs..."
	docker-compose logs -f marzban

shell:
	@echo "Opening shell in Marzban container..."
	docker-compose exec marzban bash

health:
	@echo "Checking Marzban health status..."
	docker-compose ps
	docker-compose exec marzban curl -f http://localhost:8000/api/admin || echo "Health check failed"

clean:
	@echo "Cleaning up Marzban containers and images..."
	docker-compose down -v --remove-orphans
	docker image prune -f

# Development commands
dev-build: build
	@echo "Development build completed"

dev-up: dev-build up
	@echo "Development environment started"

# Generate Reality keys
gen-keys:
	@echo "Generating Reality keys..."
	@docker run --rm gozargah/marzban:latest xray x25519

# Setup environment
setup-env:
	@echo "Setting up environment file..."
	@cp .env.example .env || echo "Please create .env file manually"
	@echo "Please edit .env file with your configuration"

# Full deployment
deploy: setup-env dev-build up
	@echo "Marzban deployed successfully"
	@echo "Access panel at: https://$$DOMAIN_NAME:$$MARZBAN_PANEL_PORT"

help:
	@echo "Available commands:"
	@echo "  build      - Build the custom Marzban container"
	@echo "  up         - Start Marzban services"
	@echo "  down       - Stop Marzban services"
	@echo "  restart    - Restart Marzban services"
	@echo "  logs       - Show container logs"
	@echo "  shell      - Open shell in container"
	@echo "  health     - Check service health"
	@echo "  clean      - Clean containers and images"
	@echo "  gen-keys   - Generate Reality keys"
	@echo "  setup-env  - Setup environment file"
	@echo "  deploy     - Full deployment"
	@echo "  help       - Show this help"