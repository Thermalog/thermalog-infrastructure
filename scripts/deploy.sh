#!/bin/bash
# Deployment script for Thermalog application
# Use this to deploy updates to an existing server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
APP_DIR="/root/thermalog-app"
BACKUP_DIR="/root/backups"

# Create backup before deployment
create_backup() {
    print_status "Creating backup before deployment..."
    
    mkdir -p $BACKUP_DIR
    DATE=$(date +%Y%m%d_%H%M%S)
    BACKUP_NAME="pre_deploy_backup_$DATE"
    
    # Backup current application state
    docker compose down
    cp -r $APP_DIR "$BACKUP_DIR/$BACKUP_NAME"
    
    print_success "Backup created: $BACKUP_DIR/$BACKUP_NAME"
}

# Update repositories
update_repos() {
    print_status "Updating repositories..."
    
    cd $APP_DIR
    
    # Update backend
    cd Thermalog-Backend
    git pull origin main
    cd ..
    
    # Update frontend
    cd Thermalog-frontend
    git pull origin main
    cd ..
    
    # Update infrastructure
    cd thermalog-infrastructure
    git pull origin main
    cd ..
    
    print_success "Repositories updated"
}

# Update configuration
update_config() {
    print_status "Updating configuration files..."
    
    # Update Docker configs if changed
    cp thermalog-infrastructure/docker/docker-compose.yml .
    cp thermalog-infrastructure/docker/docker-compose.prod.yml .
    
    # Update nginx config
    cp thermalog-infrastructure/nginx/default.conf nginx/
    
    # Update SSL hooks if changed
    cd thermalog-infrastructure
    ./scripts/install-ssl-hooks.sh
    cd ..
    
    print_success "Configuration updated"
}

# Deploy application
deploy_application() {
    print_status "Deploying application..."
    
    # Rebuild and restart containers
    docker compose -f docker-compose.yml -f docker-compose.prod.yml down
    docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
    
    # Wait for services to be ready
    print_status "Waiting for services to be ready..."
    sleep 30
    
    # Check if services are running
    if docker ps | grep -q thermalog-backend && docker ps | grep -q nginx; then
        print_success "Application deployed successfully"
    else
        print_error "Deployment may have failed. Check docker logs."
        docker ps
        exit 1
    fi
}

# Health check
health_check() {
    print_status "Performing health check..."
    
    # Check if containers are running
    BACKEND_STATUS=$(docker inspect --format='{{.State.Status}}' thermalog-backend)
    FRONTEND_STATUS=$(docker inspect --format='{{.State.Status}}' thermalog-frontend)
    NGINX_STATUS=$(docker inspect --format='{{.State.Status}}' nginx)
    
    echo "Backend: $BACKEND_STATUS"
    echo "Frontend: $FRONTEND_STATUS"
    echo "Nginx: $NGINX_STATUS"
    
    if [ "$BACKEND_STATUS" = "running" ] && [ "$NGINX_STATUS" = "running" ]; then
        print_success "Health check passed"
    else
        print_error "Health check failed"
        exit 1
    fi
}

# Main deployment
main() {
    print_status "Starting deployment..."
    
    create_backup
    update_repos
    update_config
    deploy_application
    health_check
    
    print_success "Deployment completed successfully!"
    print_status "Your application has been updated and is running."
}

# Run main function
main "$@"