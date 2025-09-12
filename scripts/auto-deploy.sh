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

# Cleanup failed deployment function
cleanup_failed_deployment() {
    local service=$1
    local dir=$2
    local current_commit=$3
    local state_file=$4
    
    send_notification "🔄 Cleaning up failed deployment for $service" "warning"
    
    # Reset git to original state
    cd $dir
    if git reset --hard $current_commit 2>/dev/null; then
        send_notification "✅ Git reset to original commit: ${current_commit:0:7}" "info"
    else
        send_notification "❌ Failed to reset git - manual intervention needed" "error"
    fi
    
    # Try to restore from backup if available
    if [ -f "$state_file" ] && grep -q "BACKUP_TAG:" "$state_file"; then
        BACKUP_TAG=$(grep "BACKUP_TAG:" "$state_file" | cut -d: -f2)
        if [ ! -z "$BACKUP_TAG" ]; then
            send_notification "🔄 Restoring from backup: $BACKUP_TAG" "info"
            docker tag root-thermalog-$service:$BACKUP_TAG root-thermalog-$service:latest 2>/dev/null || true
            docker compose up -d thermalog-$service > /dev/null 2>&1
        fi
    fi
    
    # Archive the state file for debugging
    if [ -f "$state_file" ]; then
        mv "$state_file" "/root/failed-deploy-$(date +%Y%m%d-%H%M%S).log"
        send_notification "📋 Deployment state archived for debugging" "info"
    fi
}

# Check for interrupted deployments on startup
check_interrupted_deployments() {
    for state_file in /tmp/deploy-*-state; do
        if [ -f "$state_file" ]; then
            send_notification "🔍 Found interrupted deployment state file: $(basename $state_file)" "warning"
            
            # Extract service name
            service=$(basename "$state_file" | sed 's/deploy-\(.*\)-state/\1/')
            
            # Check if deployment completed
            if ! grep -q "DEPLOY_COMPLETED:" "$state_file"; then
                send_notification "⚠️ Deployment of $service was interrupted - attempting recovery" "warning"
                
                # Get stored values
                current_commit=$(grep "CURRENT_COMMIT:" "$state_file" 2>/dev/null | cut -d: -f2)
                backup_tag=$(grep "BACKUP_TAG:" "$state_file" 2>/dev/null | cut -d: -f2)
                
                # Determine service directory
                if [ "$service" = "backend" ]; then
                    service_dir="/root/Thermalog-Backend"
                elif [ "$service" = "frontend" ]; then
                    service_dir="/root/Thermalog-frontend"
                else
                    send_notification "❌ Unknown service in interrupted deployment: $service" "error"
                    continue
                fi
                
                # Attempt recovery
                if [ ! -z "$current_commit" ] && [ ! -z "$service_dir" ]; then
                    cleanup_failed_deployment "$service" "$service_dir" "$current_commit" "$state_file"
                    send_notification "✅ Recovery attempt completed for $service" "info"
                else
                    send_notification "❌ Insufficient data to recover $service deployment" "error"
                    mv "$state_file" "/root/unrecoverable-deploy-$(date +%Y%m%d-%H%M%S).log"
                fi
            else
                # Deployment completed successfully, remove state file
                rm -f "$state_file"
            fi
        fi
    done
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
    
    # Create deployment state file
    local DEPLOY_STATE_FILE="/tmp/deploy-$service-state"
    echo "STARTED:$(date '+%Y-%m-%d %H:%M:%S')" > $DEPLOY_STATE_FILE
    
    send_notification "🚀 Starting deployment of $service" "info"
    
    cd $dir
    
    # Store current commit for rollback
    CURRENT_COMMIT=$(git rev-parse HEAD)
    echo "CURRENT_COMMIT:$CURRENT_COMMIT" >> $DEPLOY_STATE_FILE
    
    # Create backup tag
    BACKUP_TAG="auto-backup-$(date +%Y%m%d-%H%M%S)"
    if docker tag root-thermalog-$service:latest root-thermalog-$service:$BACKUP_TAG 2>/dev/null; then
        echo "BACKUP_TAG:$BACKUP_TAG" >> $DEPLOY_STATE_FILE
        send_notification "📦 Created backup: $BACKUP_TAG" "info"
    else
        send_notification "⚠️ Warning: Could not create backup tag" "warning"
    fi
    
    # Pull latest code with timeout
    send_notification "📥 Pulling latest code..." "info"
    if ! timeout 60 git pull origin main --quiet; then
        send_notification "❌ Failed to pull code for $service (timeout or error)" "error"
        cleanup_failed_deployment "$service" "$dir" "$CURRENT_COMMIT" "$DEPLOY_STATE_FILE"
        return 1
    fi
    
    # Get commit info
    LATEST_COMMIT=$(git rev-parse HEAD)
    COMMIT_MESSAGE=$(git log -1 --pretty=%B)
    COMMIT_AUTHOR=$(git log -1 --pretty=%an)
    echo "LATEST_COMMIT:$LATEST_COMMIT" >> $DEPLOY_STATE_FILE
    
    send_notification "📦 Building $service (commit: ${LATEST_COMMIT:0:7} by $COMMIT_AUTHOR)" "info"
    
    # Build new image with timeout and detailed logging
    cd /root
    echo "BUILD_STARTED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
    
    # Build with timeout (10 minutes) and capture output
    if ! timeout 600 docker compose build thermalog-$service 2>&1 | tee -a $DEPLOY_STATE_FILE; then
        send_notification "❌ Build failed for $service (timeout or error)" "error"
        cleanup_failed_deployment "$service" "$dir" "$CURRENT_COMMIT" "$DEPLOY_STATE_FILE"
        return 1
    fi
    
    echo "BUILD_COMPLETED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
    send_notification "✅ Build completed successfully" "success"
    
    # Deploy new container with better error handling
    send_notification "🚀 Deploying new container..." "info"
    echo "DEPLOY_STARTED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
    
    if ! docker compose up -d thermalog-$service 2>&1 | tee -a $DEPLOY_STATE_FILE; then
        send_notification "❌ Container deployment failed for $service" "error"
        cleanup_failed_deployment "$service" "$dir" "$CURRENT_COMMIT" "$DEPLOY_STATE_FILE"
        return 1
    fi
    
    echo "DEPLOY_COMPLETED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
    
    # Health check (only for backend)
    if [ "$service" = "backend" ]; then
        echo "HEALTH_CHECK_STARTED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
        if check_health $service; then
            send_notification "✅ $service deployed successfully!" "success"
            send_notification "📝 Changes: $COMMIT_MESSAGE" "info"
            
            # Mark deployment as fully completed
            echo "HEALTH_CHECK_PASSED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
            echo "DEPLOYMENT_SUCCESS:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
            
            # Cleanup old backups (keep last 3)
            docker images | grep "root-thermalog-$service.*auto-backup" | tail -n +4 | awk '{print $3}' | xargs -r docker rmi 2>/dev/null || true
            
            # Remove state file on successful completion
            rm -f "$DEPLOY_STATE_FILE"
            
            return 0
        else
            send_notification "❌ Health check failed for $service - rolling back" "error"
            echo "HEALTH_CHECK_FAILED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
            
            # Rollback
            docker compose stop thermalog-$service > /dev/null 2>&1
            if [ ! -z "$BACKUP_TAG" ]; then
                docker tag root-thermalog-$service:$BACKUP_TAG root-thermalog-$service:latest
            fi
            docker compose up -d thermalog-$service > /dev/null 2>&1
            
            cd $dir
            git reset --hard $CURRENT_COMMIT
            echo "ROLLBACK_COMPLETED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
            
            if check_health $service; then
                send_notification "✅ Rollback successful for $service" "success"
                echo "ROLLBACK_SUCCESS:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
                # Archive the failure state for analysis
                mv "$DEPLOY_STATE_FILE" "/root/failed-deploy-$(date +%Y%m%d-%H%M%S).log"
            else
                send_notification "🚨 CRITICAL: Rollback failed for $service" "error"
                echo "ROLLBACK_FAILED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
                # Keep state file for manual intervention
                mv "$DEPLOY_STATE_FILE" "/root/critical-deploy-failure-$(date +%Y%m%d-%H%M%S).log"
            fi
            
            return 1
        fi
    else
        # For frontend, just wait a bit and check if container is running
        sleep 10
        if docker ps | grep -q thermalog-$service; then
            send_notification "✅ $service deployed successfully!" "success"
            send_notification "📝 Changes: $COMMIT_MESSAGE" "info"
            echo "DEPLOYMENT_SUCCESS:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
            # Remove state file on successful completion
            rm -f "$DEPLOY_STATE_FILE"
            return 0
        else
            send_notification "❌ Deployment failed for $service" "error"
            echo "DEPLOYMENT_FAILED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
            cleanup_failed_deployment "$service" "$dir" "$CURRENT_COMMIT" "$DEPLOY_STATE_FILE"
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
    
    # Check for interrupted deployments first
    check_interrupted_deployments
    
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