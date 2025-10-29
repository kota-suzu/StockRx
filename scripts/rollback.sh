#!/bin/bash
set -euo pipefail

# ================================================================================
# StockRx Rollback Script
# Quickly rollback to previous version in case of deployment failure
# ================================================================================

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

# Get the previous image tag
get_previous_tag() {
    # Get the second most recent tag from docker images
    docker images --format "{{.Tag}}" | grep -v latest | head -2 | tail -1
}

# Rollback to previous version
rollback() {
    local previous_tag=$(get_previous_tag)
    
    if [ -z "$previous_tag" ]; then
        log_error "No previous version found to rollback to"
        exit 1
    fi
    
    log_info "Rolling back to version: $previous_tag"
    
    # Update docker-compose to use previous tag
    export IMAGE_TAG="$previous_tag"
    
    # Restart services with previous version
    docker-compose up -d --no-deps web sidekiq
    
    # Wait for services to be healthy
    sleep 10
    
    # Run health check
    if docker-compose exec -T web curl -f http://localhost:3000/health > /dev/null 2>&1; then
        log_info "Rollback completed successfully"
        
        # Clear cache
        docker-compose exec -T web bundle exec rails tmp:clear
        docker-compose exec -T web bundle exec rails cache:clear
        
        return 0
    else
        log_error "Rollback failed - services not healthy"
        return 1
    fi
}

# Send notification
send_notification() {
    local status=$1
    local message="Rollback $status for StockRx deployment"
    
    # Send to monitoring system
    curl -X POST "${MONITORING_WEBHOOK_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"text\": \"$message\", \"status\": \"$status\"}" \
        || log_warn "Failed to send notification"
}

# Main rollback process
main() {
    log_warn "Starting emergency rollback procedure..."
    
    if rollback; then
        send_notification "completed"
        log_info "Rollback completed. Please investigate the deployment failure."
    else
        send_notification "failed"
        log_error "Rollback failed! Manual intervention required!"
        exit 1
    fi
}

# Run main function
main "$@"