#!/bin/bash

# Automated Safe Deployment Script for Thermalog
# Checks GitHub for changes and automatically deploys with health verification
# Run this via cron for automatic deployments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
BACKEND_DIR="/root/Thermalog-Backend"
FRONTEND_DIR="/root/Thermalog-frontend"
COMPOSE_FILE="/root/docker-compose.yml"
HEALTH_URL="http://localhost:3001/api/health"
LOG_FILE="/root/deployment.log"
SLACK_WEBHOOK_URL=""  # Optional: Add Slack webhook for notifications

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Send notification (optional)
send_notification() {
    local message=$1
    local status=$2
    
    # Console output
    if [ "$status" = "success" ]; then
        echo -e "${GREEN}$message${NC}"
    elif [ "$status" = "error" ]; then
        echo -e "${RED}$message${NC}"
    else
        echo -e "${YELLOW}$message${NC}"
    fi
    
    # Log to file
    log "$message"
    
    # Optional: Send to Slack
    if [ ! -z "$SLACK_WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$message\"}" \
            $SLACK_WEBHOOK_URL 2>/dev/null || true
    fi
}

# Health check function
check_health() {
    local service=$1
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        HEALTH_RESPONSE=$(curl -s $HEALTH_URL 2>/dev/null || echo "{}")
        HEALTH_STATUS=$(echo $HEALTH_RESPONSE | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('status', 'unknown'))" 2>/dev/null || echo "error")
        DB_STATUS=$(echo $HEALTH_RESPONSE | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('database', {}).get('status', 'unknown'))" 2>/dev/null || echo "error")
        
        if [ "$HEALTH_STATUS" = "healthy" ] && [ "$DB_STATUS" = "connected" ]; then
            return 0
        fi
        
        sleep 2
        ((attempt++))
    done
    
    return 1
}

# Check for GitHub updates
check_github_updates() {
    local dir=$1
    local service=$2
    
    cd $dir
    
    # Fetch latest from GitHub
    git fetch origin main --quiet
    
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main)
    
    if [ "$LOCAL" != "$REMOTE" ]; then
        echo "true"
        return 0
    else
        echo "false"
        return 1
    fi
}

# Deploy service
deploy_service() {
    local service=$1
    local dir=$2
    
    send_notification "🚀 Starting deployment of $service" "info"
    
    cd $dir
    
    # Store current commit for rollback
    CURRENT_COMMIT=$(git rev-parse HEAD)
    
    # Create backup tag
    BACKUP_TAG="auto-backup-$(date +%Y%m%d-%H%M%S)"
    docker tag root-thermalog-$service:latest root-thermalog-$service:$BACKUP_TAG 2>/dev/null || true
    
    # Pull latest code
    if ! git pull origin main --quiet; then
        send_notification "❌ Failed to pull code for $service" "error"
        return 1
    fi
    
    # Get commit info
    LATEST_COMMIT=$(git rev-parse HEAD)
    COMMIT_MESSAGE=$(git log -1 --pretty=%B)
    COMMIT_AUTHOR=$(git log -1 --pretty=%an)
    
    send_notification "📦 Building $service (commit: ${LATEST_COMMIT:0:7} by $COMMIT_AUTHOR)" "info"
    
    # Build new image
    cd /root
    if ! docker compose build thermalog-$service > /dev/null 2>&1; then
        send_notification "❌ Build failed for $service" "error"
        cd $dir
        git reset --hard $CURRENT_COMMIT
        return 1
    fi
    
    # Deploy new container
    docker compose up -d thermalog-$service > /dev/null 2>&1
    
    # Health check (only for backend)
    if [ "$service" = "backend" ]; then
        if check_health $service; then
            send_notification "✅ $service deployed successfully!" "success"
            send_notification "📝 Changes: $COMMIT_MESSAGE" "info"
            
            # Cleanup old backups (keep last 3)
            docker images | grep "root-thermalog-$service.*auto-backup" | tail -n +4 | awk '{print $3}' | xargs -r docker rmi 2>/dev/null || true
            
            return 0
        else
            send_notification "❌ Health check failed for $service - rolling back" "error"
            
            # Rollback
            docker compose stop thermalog-$service > /dev/null 2>&1
            docker tag root-thermalog-$service:$BACKUP_TAG root-thermalog-$service:latest
            docker compose up -d thermalog-$service > /dev/null 2>&1
            
            cd $dir
            git reset --hard $CURRENT_COMMIT
            
            if check_health $service; then
                send_notification "✅ Rollback successful for $service" "success"
            else
                send_notification "🚨 CRITICAL: Rollback failed for $service" "error"
            fi
            
            return 1
        fi
    else
        # For frontend, just wait a bit and check if container is running
        sleep 10
        if docker ps | grep -q thermalog-$service; then
            send_notification "✅ $service deployed successfully!" "success"
            send_notification "📝 Changes: $COMMIT_MESSAGE" "info"
            return 0
        else
            send_notification "❌ Deployment failed for $service" "error"
            return 1
        fi
    fi
}

# Main execution
main() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}     AUTOMATED DEPLOYMENT CHECK - $(date)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    
    log "Starting automated deployment check"
    
    UPDATES_FOUND=false
    DEPLOYMENT_NEEDED=false
    
    # Check backend for updates
    if check_github_updates "$BACKEND_DIR" "backend"; then
        send_notification "📊 New backend changes detected on GitHub" "info"
        UPDATES_FOUND=true
        
        # Show what will be deployed
        cd $BACKEND_DIR
        echo -e "${BLUE}Backend changes to deploy:${NC}"
        git log HEAD..origin/main --oneline
        echo ""
        
        # Auto-deploy backend
        if deploy_service "backend" "$BACKEND_DIR"; then
            send_notification "✅ Backend auto-deployment completed" "success"
        else
            send_notification "❌ Backend auto-deployment failed" "error"
        fi
    fi
    
    # Check frontend for updates
    if check_github_updates "$FRONTEND_DIR" "frontend"; then
        send_notification "📊 New frontend changes detected on GitHub" "info"
        UPDATES_FOUND=true
        
        # Show what will be deployed
        cd $FRONTEND_DIR
        echo -e "${BLUE}Frontend changes to deploy:${NC}"
        git log HEAD..origin/main --oneline
        echo ""
        
        # Auto-deploy frontend
        if deploy_service "frontend" "$FRONTEND_DIR"; then
            send_notification "✅ Frontend auto-deployment completed" "success"
        else
            send_notification "❌ Frontend auto-deployment failed" "error"
        fi
    fi
    
    if [ "$UPDATES_FOUND" = false ]; then
        echo -e "${GREEN}✓ All services are up to date${NC}"
        log "No updates found - all services up to date"
    fi
    
    # Show current status
    echo ""
    echo -e "${BLUE}Current System Status:${NC}"
    echo "═══════════════════════════════════════"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep thermalog
    
    # Run cleanup if any deployments were successful
    if [ "$UPDATES_FOUND" = true ]; then
        echo ""
        echo -e "${YELLOW}Running Docker cleanup...${NC}"
        /root/docker-cleanup.sh > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Docker cleanup completed${NC}"
        fi
    fi
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    log "Automated deployment check completed"
}

# Create lock file to prevent multiple instances
LOCKFILE="/tmp/auto-deploy.lock"

if [ -e "${LOCKFILE}" ] && kill -0 $(cat "${LOCKFILE}") 2>/dev/null; then
    echo "Deployment script is already running"
    exit 1
fi

echo $$ > "${LOCKFILE}"
trap "rm -f ${LOCKFILE}" EXIT

# Run main function
main