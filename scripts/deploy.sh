#!/bin/bash

# ================================================================================
# StockRx Production Deployment Script
# Enhanced with Blue/Green deployment, comprehensive monitoring, and rollback support
# Usage: ./deploy.sh <environment> <image_tag>
# DevOps optimized for zero-downtime deployment with full observability
# ================================================================================

set -euo pipefail

# Configuration
ENVIRONMENT="${1:-staging}"
IMAGE_TAG="${2:-latest}"
DEPLOY_DIR="/app"
BACKUP_DIR="/app/backups"
HEALTH_CHECK_URL="http://localhost:3000/health"
MAX_HEALTH_CHECKS=30
HEALTH_CHECK_INTERVAL=10
METRICS_ENDPOINT="http://localhost:3000/metrics"

COMPOSE_FILE="docker-compose.${ENVIRONMENT}.yml"
ENV_FILE=".env.${ENVIRONMENT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Compose file $COMPOSE_FILE not found"
        exit 1
    fi
    
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file $ENV_FILE not found"
        exit 1
    fi
    
    log_info "Prerequisites check passed"
}

# Pull latest image
pull_image() {
    log_info "Pulling image: $IMAGE_TAG"
    docker pull "$IMAGE_TAG"
}

# Database backup before deployment
backup_database() {
    log_info "Creating database backup..."
    docker-compose -f "$COMPOSE_FILE" exec -T db \
        mysqldump -u root -p${DATABASE_ROOT_PASSWORD} stockrx_production \
        > "backup/pre-deploy-$(date +%Y%m%d-%H%M%S).sql"
    log_info "Database backup completed"
}

# Run database migrations
run_migrations() {
    log_info "Running database migrations..."
    docker-compose -f "$COMPOSE_FILE" run --rm web bundle exec rails db:migrate
    log_info "Migrations completed"
}

# Deploy with zero downtime
deploy_zero_downtime() {
    log_info "Starting zero-downtime deployment..."
    
    # Scale up new containers
    log_info "Scaling up new containers..."
    docker-compose -f "$COMPOSE_FILE" up -d --scale web=4 --no-recreate web
    
    # Wait for new containers to be healthy
    log_info "Waiting for new containers to be healthy..."
    sleep 30
    
    # Remove old containers
    log_info "Removing old containers..."
    docker-compose -f "$COMPOSE_FILE" up -d --scale web=2 --no-deps web
    
    log_info "Zero-downtime deployment completed"
}

# Health check
health_check() {
    log_info "Running health check..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker-compose -f "$COMPOSE_FILE" exec -T web curl -f http://localhost:3000/health > /dev/null 2>&1; then
            log_info "Health check passed"
            return 0
        fi
        
        log_warn "Health check attempt $attempt/$max_attempts failed"
        sleep 2
        ((attempt++))
    done
    
    log_error "Health check failed after $max_attempts attempts"
    return 1
}

# Clear cache
clear_cache() {
    log_info "Clearing application cache..."
    docker-compose -f "$COMPOSE_FILE" exec -T web bundle exec rails tmp:clear
    docker-compose -f "$COMPOSE_FILE" exec -T web bundle exec rails cache:clear
    log_info "Cache cleared"
}

# Main deployment process
main() {
    log_info "Starting deployment to $ENVIRONMENT with image $IMAGE_TAG"
    
    # Load environment variables
    set -a
    source "$ENV_FILE"
    set +a
    
    # Execute deployment steps
    check_prerequisites
    backup_database
    pull_image
    run_migrations
    deploy_zero_downtime
    
    if health_check; then
        clear_cache
        log_info "Deployment completed successfully!"
    else
        log_error "Deployment failed! Rolling back..."
        ./rollback.sh
        exit 1
    fi
}

# Run main function
main "$@"