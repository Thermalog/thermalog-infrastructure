#!/bin/bash

# Automated Safe Deployment Script for Thermalog
# Checks GitHub for changes and automatically deploys with health verification
# Run this via cron for automatic deployments

set -e

# Load environment variables
[ -f /root/.env ] && source /root/.env

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
HEALTH_URL="https://localhost/api/health"
LOG_FILE="/root/thermalog-ops/logs/deployment/deployment.log"
DEPLOY_HISTORY_FILE="/root/thermalog-ops/logs/deployment/deployment-history.json"
SLACK_WEBHOOK_URL=""  # Optional: Add Slack webhook for notifications

# State file configuration
STATE_DIR="/root/thermalog-ops/deployment-state"
MAX_RECOVERY_ATTEMPTS=3
STATE_FILE_EXPIRY=3600  # 1 hour in seconds

# Email notification settings (HTTPS API)
EMAIL_ENABLED="true"  # Set to "true" to enable email notifications
EMAIL_FROM="notifications@thermalog.com.au"  # Sender email address
EMAIL_TO="abid148@gmail.com,work.alishan@gmail.com,tahahanif24@gmail.com"    # Recipient email addresses
EMAIL_API_KEY="${SENDGRID_API_KEY}"  # SendGrid API Key from environment variable
EMAIL_METHOD="sendgrid"  # Options: sendgrid, emailjs, webhook

# Email consolidation settings
EMAIL_SUMMARY=""  # Accumulates messages for consolidated email
EMAIL_FINAL_STATUS=""  # Tracks overall deployment status

# Ensure state directory exists
mkdir -p "$STATE_DIR" 2>/dev/null

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Email sending function
send_email() {
    local subject=$1
    local message=$2
    local priority=${3:-"normal"}  # normal, high, or low
    
    # Only send email if enabled and all required fields are set
    if [ "$EMAIL_ENABLED" != "true" ] || [ -z "$EMAIL_FROM" ] || [ -z "$EMAIL_TO" ]; then
        return 0
    fi
    
    # Log the notification regardless of sending method
    local log_message="EMAIL NOTIFICATION: [$subject] $message (To: $EMAIL_TO, Priority: $priority)"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $log_message" >> /root/thermalog-ops/logs/notifications/email-notifications.log
    
    # Send via HTTPS API if API key is configured
    if [ ! -z "$EMAIL_API_KEY" ]; then
        case "$EMAIL_METHOD" in
            "sendgrid")
                send_email_sendgrid "$subject" "$message" "$priority"
                ;;
            "emailjs")
                send_email_emailjs "$subject" "$message" "$priority"
                ;;
            "webhook")
                send_email_webhook "$subject" "$message" "$priority"
                ;;
            *)
                echo "Unknown email method: $EMAIL_METHOD" >> /root/thermalog-ops/logs/notifications/email-notifications.log
                ;;
        esac
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] EMAIL_API_KEY not set - email logged only" >> /root/thermalog-ops/logs/notifications/email-notifications.log
    fi
}

# SendGrid API email function
send_email_sendgrid() {
    local subject=$1
    local message=$2
    local priority=$3
    
    # Convert \n sequences to actual newlines for proper JSON formatting
    local formatted_message=$(echo -e "$message")
    
    # Create JSON payload with proper escaping using jq if available, otherwise manual escaping
    if command -v jq >/dev/null 2>&1; then
        # Convert comma-separated emails to array format
        local email_array=$(echo "$EMAIL_TO" | tr ',' '\n' | jq -R '{email: .}' | jq -s .)
        
        local json_payload=$(jq -n \
            --argjson to "$email_array" \
            --arg subject "$subject" \
            --arg from "$EMAIL_FROM" \
            --arg message "$formatted_message

---
Thermalog Auto-Deploy System
Server: $(hostname)
Time: $(date)" \
            '{
                personalizations: [{
                    to: $to,
                    subject: $subject
                }],
                from: {email: $from, name: "Thermalog Auto-Deploy"},
                content: [{
                    type: "text/plain",
                    value: $message
                }]
            }')
    else
        # Fallback: manual JSON escaping
        local escaped_message=$(echo -e "$message" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
        
        # Build recipients array manually
        local recipients_json=""
        IFS=',' read -ra ADDR <<< "$EMAIL_TO"
        for email in "${ADDR[@]}"; do
            email=$(echo "$email" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')  # trim whitespace
            if [ -z "$recipients_json" ]; then
                recipients_json="{\"email\": \"$email\"}"
            else
                recipients_json="$recipients_json, {\"email\": \"$email\"}"
            fi
        done
        
        local json_payload=$(cat << EOF
{
  "personalizations": [
    {
      "to": [$recipients_json],
      "subject": "$subject"
    }
  ],
  "from": {"email": "$EMAIL_FROM", "name": "Thermalog Auto-Deploy"},
  "content": [
    {
      "type": "text/plain",
      "value": "$escaped_message\\n\\n---\\nThermalog Auto-Deploy System\\nServer: $(hostname)\\nTime: $(date)"
    }
  ]
}
EOF
)
    fi
    
    curl -s -X POST \
        -H "Authorization: Bearer $EMAIL_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        "https://api.sendgrid.com/v3/mail/send" \
        > /dev/null 2>&1 && \
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Email sent via SendGrid API" >> /root/thermalog-ops/logs/notifications/email-notifications.log || \
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to send via SendGrid API" >> /root/thermalog-ops/logs/notifications/email-notifications.log
}

# Generic webhook email function
send_email_webhook() {
    local subject=$1
    local message=$2
    local priority=$3
    
    # Example webhook payload - customize for your webhook service
    local webhook_payload=$(cat << EOF
{
  "to": "$EMAIL_TO",
  "from": "$EMAIL_FROM",
  "subject": "$subject",
  "message": "$message",
  "priority": "$priority",
  "timestamp": "$(date -Iseconds)",
  "server": "$(hostname)"
}
EOF
)
    
    # Replace with your webhook URL
    if [ ! -z "$WEBHOOK_URL" ]; then
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$webhook_payload" \
            "$WEBHOOK_URL" \
            > /dev/null 2>&1 && \
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Email sent via webhook" >> /root/thermalog-ops/logs/notifications/email-notifications.log || \
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Failed to send via webhook" >> /root/thermalog-ops/logs/notifications/email-notifications.log
    fi
}

# EmailJS function (alternative service)
send_email_emailjs() {
    local subject=$1
    local message=$2
    local priority=$3
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] EmailJS integration not implemented yet" >> /root/thermalog-ops/logs/notifications/email-notifications.log
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
    
    # Accumulate messages for consolidated email
    if [ "$EMAIL_ENABLED" = "true" ]; then
        EMAIL_SUMMARY="${EMAIL_SUMMARY}$(date '+%H:%M:%S') - $message\n"
        
        # Track the most severe status for final email
        case "$status" in
            "error")
                EMAIL_FINAL_STATUS="error"
                ;;
            "warning")
                if [ "$EMAIL_FINAL_STATUS" != "error" ]; then
                    EMAIL_FINAL_STATUS="warning"
                fi
                ;;
            "success")
                if [ -z "$EMAIL_FINAL_STATUS" ]; then
                    EMAIL_FINAL_STATUS="success"
                fi
                ;;
        esac
    fi
}

# Send consolidated email summary
send_consolidated_email() {
    if [ "$EMAIL_ENABLED" = "true" ] && [ ! -z "$EMAIL_SUMMARY" ]; then
        local email_subject="Thermalog Deployment"
        local email_priority="normal"
        
        # Set subject and priority based on final status
        case "$EMAIL_FINAL_STATUS" in
            "success")
                email_subject="✅ Thermalog Deployment Complete"
                ;;
            "error")
                email_subject="❌ Thermalog Deployment Issues"
                email_priority="high"
                ;;
            "warning")
                email_subject="⚠️ Thermalog Deployment Completed with Warnings"
                ;;
            *)
                email_subject="ℹ️ Thermalog Deployment Summary"
                ;;
        esac
        
        local consolidated_message="Deployment Summary:\n\n${EMAIL_SUMMARY}"
        send_email "$email_subject" "$consolidated_message" "$email_priority"
        
        # Reset for next run
        EMAIL_SUMMARY=""
        EMAIL_FINAL_STATUS=""
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
        BACKUP_TAG=$(grep "BACKUP_TAG:" "$state_file" | cut -d: -f2 | tail -1)
        if [ ! -z "$BACKUP_TAG" ]; then
            send_notification "🔄 Restoring from backup: $BACKUP_TAG" "info"
            docker tag thermalog-thermalog-$service:$BACKUP_TAG thermalog-thermalog-$service:latest 2>/dev/null || true
            docker compose up -d thermalog-$service > /dev/null 2>&1
            
            # Verify restoration
            sleep 5
            if docker ps | grep -q thermalog-$service; then
                send_notification "✅ Service restored from backup" "success"
            else
                send_notification "⚠️ Service restoration may have failed" "warning"
            fi
        fi
    fi
    
    # Don't remove state file here - let check_interrupted_deployments handle it
    # This prevents the infinite loop issue
}

# Check for interrupted deployments on startup
check_interrupted_deployments() {
    # Check both old /tmp location and new state directory
    for state_file in /tmp/deploy-*-state "$STATE_DIR"/deploy-*-state; do
        if [ -f "$state_file" ]; then
            # Check if state file is expired (older than STATE_FILE_EXPIRY seconds)
            file_mod_time=$(stat -c %Y "$state_file" 2>/dev/null || echo "0")
            current_time=$(date +%s)
            if [ "$file_mod_time" != "0" ]; then
                file_age=$((current_time - file_mod_time))
            else
                file_age=0
            fi
            if [ $file_age -gt $STATE_FILE_EXPIRY ]; then
                send_notification "🗑️ Removing expired state file: $(basename $state_file)" "info"
                mv "$state_file" "/root/thermalog-ops/logs/deployment/failures/expired-deploy-$(date +%Y%m%d-%H%M%S).log"
                continue
            fi
            
            send_notification "🔍 Found interrupted deployment state file: $(basename $state_file)" "warning"
            
            # Extract service name
            service=$(basename "$state_file" | sed 's/deploy-\(.*\)-state/\1/')
            
            # Check recovery attempts
            recovery_attempts=$(grep -c "RECOVERY_ATTEMPT:" "$state_file" 2>/dev/null || echo 0)
            if [ $recovery_attempts -ge $MAX_RECOVERY_ATTEMPTS ]; then
                send_notification "❌ Max recovery attempts ($MAX_RECOVERY_ATTEMPTS) reached for $service - manual intervention required" "error"
                mv "$state_file" "/root/thermalog-ops/logs/deployment/failures/max-recovery-reached-$(date +%Y%m%d-%H%M%S).log"
                continue
            fi
            
            # Record recovery attempt
            echo "RECOVERY_ATTEMPT:$(date '+%Y-%m-%d %H:%M:%S')" >> "$state_file"
            
            # Check if deployment completed
            if ! grep -q "DEPLOY_COMPLETED:" "$state_file"; then
                send_notification "⚠️ Deployment of $service was interrupted - attempting recovery (attempt $((recovery_attempts + 1))/$MAX_RECOVERY_ATTEMPTS)" "warning"
                
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
                    mv "$state_file" "/root/thermalog-ops/logs/deployment/failures/unknown-service-$(date +%Y%m%d-%H%M%S).log"
                    continue
                fi
                
                # Attempt recovery
                if [ ! -z "$current_commit" ] && [ ! -z "$service_dir" ]; then
                    cleanup_failed_deployment "$service" "$service_dir" "$current_commit" "$state_file"
                    send_notification "✅ Recovery attempt completed for $service" "info"
                    # Remove state file after successful recovery
                    rm -f "$state_file"
                else
                    send_notification "❌ Insufficient data to recover $service deployment" "error"
                    mv "$state_file" "/root/thermalog-ops/logs/deployment/failures/unrecoverable-deploy-$(date +%Y%m%d-%H%M%S).log"
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
        HEALTH_RESPONSE=$(curl -s -k $HEALTH_URL 2>/dev/null || echo "{}")
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

# Check for GitHub updates with improved detection
check_github_updates() {
    local dir=$1
    local service=$2
    
    cd $dir
    
    # Store current state
    LOCAL_BEFORE=$(git rev-parse HEAD)
    
    # Fetch latest from GitHub
    git fetch origin main --quiet
    
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main)
    
    # Check deployment history to see if this commit was already deployed
    if [ -f "$DEPLOY_HISTORY_FILE" ]; then
        LAST_DEPLOYED=$(python3 -c "import sys, json; 
            data = json.load(open('$DEPLOY_HISTORY_FILE', 'r')) if sys.version_info >= (3,0) else {}; 
            deploys = data.get('$service', []); 
            print(deploys[-1]['commit'] if deploys else '')" 2>/dev/null || echo "")
        
        # If remote commit was already deployed, skip unless forced
        if [ "$REMOTE" = "$LAST_DEPLOYED" ] && [ "$FORCE_DEPLOY" != "true" ]; then
            echo "false"
            return 1
        fi
    fi
    
    # Check if local and remote differ OR if force deploy is set
    if [ "$LOCAL" != "$REMOTE" ] || [ "$FORCE_DEPLOY" = "true" ]; then
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
    
    # Create deployment state file in dedicated directory
    local DEPLOY_STATE_FILE="$STATE_DIR/deploy-$service-state"
    echo "STARTED:$(date '+%Y-%m-%d %H:%M:%S')" > $DEPLOY_STATE_FILE
    echo "PID:$$" >> $DEPLOY_STATE_FILE
    
    send_notification "🚀 Starting deployment of $service" "info"
    
    cd $dir
    
    # Store current commit for rollback
    CURRENT_COMMIT=$(git rev-parse HEAD)
    echo "CURRENT_COMMIT:$CURRENT_COMMIT" >> $DEPLOY_STATE_FILE
    
    # Create backup tag
    BACKUP_TAG="auto-backup-$(date +%Y%m%d-%H%M%S)"
    if docker tag thermalog-thermalog-$service:latest thermalog-thermalog-$service:$BACKUP_TAG 2>/dev/null; then
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
    if ! timeout 600 docker compose build thermalog-$service --no-cache 2>&1 | tee -a $DEPLOY_STATE_FILE; then
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
            
            # Record successful deployment
            record_deployment "$service" "$LATEST_COMMIT" "success" "$COMMIT_MESSAGE"
            
            # Mark deployment as fully completed
            echo "HEALTH_CHECK_PASSED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
            echo "DEPLOYMENT_SUCCESS:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
            
            # Cleanup old backups (keep last 3)
            docker images | grep "thermalog-thermalog-$service.*auto-backup" | tail -n +4 | awk '{print $3}' | xargs -r docker rmi 2>/dev/null || true
            
            # Remove state file on successful completion
            rm -f "$DEPLOY_STATE_FILE"
            
            return 0
        else
            send_notification "❌ Health check failed for $service - rolling back" "error"
            echo "HEALTH_CHECK_FAILED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
            
            # Record failed deployment
            record_deployment "$service" "$LATEST_COMMIT" "failed" "Health check failed"
            
            # Rollback
            docker compose stop thermalog-$service > /dev/null 2>&1
            if [ ! -z "$BACKUP_TAG" ]; then
                docker tag thermalog-thermalog-$service:$BACKUP_TAG thermalog-thermalog-$service:latest
            fi
            docker compose up -d thermalog-$service > /dev/null 2>&1
            
            cd $dir
            git reset --hard $CURRENT_COMMIT
            echo "ROLLBACK_COMPLETED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
            
            if check_health $service; then
                send_notification "✅ Rollback successful for $service" "success"
                echo "ROLLBACK_SUCCESS:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
                # Archive the failure state for analysis
                mv "$DEPLOY_STATE_FILE" "/root/thermalog-ops/logs/deployment/failures/failed-deploy-$(date +%Y%m%d-%H%M%S).log"
            else
                send_notification "🚨 CRITICAL: Rollback failed for $service" "error"
                echo "ROLLBACK_FAILED:$(date '+%Y-%m-%d %H:%M:%S')" >> $DEPLOY_STATE_FILE
                # Keep state file for manual intervention
                mv "$DEPLOY_STATE_FILE" "/root/thermalog-ops/logs/deployment/failures/critical-deploy-failure-$(date +%Y%m%d-%H%M%S).log"
            fi
            
            return 1
        fi
    else
        # For frontend, just wait a bit and check if container is running
        sleep 10
        if docker ps | grep -q thermalog-$service; then
            send_notification "✅ $service deployed successfully!" "success"
            send_notification "📝 Changes: $COMMIT_MESSAGE" "info"
            
            # Record successful deployment
            record_deployment "$service" "$LATEST_COMMIT" "success" "$COMMIT_MESSAGE"
            
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

# Record deployment in history
record_deployment() {
    local service=$1
    local commit=$2
    local status=$3
    local message=$4
    
    # Initialize history file if it doesn't exist
    if [ ! -f "$DEPLOY_HISTORY_FILE" ]; then
        echo '{}' > "$DEPLOY_HISTORY_FILE"
    fi
    
    # Add deployment record
    python3 -c "
import json
import datetime

with open('$DEPLOY_HISTORY_FILE', 'r') as f:
    data = json.load(f)

if '$service' not in data:
    data['$service'] = []

data['$service'].append({
    'timestamp': datetime.datetime.now().isoformat(),
    'commit': '$commit',
    'status': '$status',
    'message': '$message'
})

# Keep only last 50 deployments per service
data['$service'] = data['$service'][-50:]

with open('$DEPLOY_HISTORY_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || echo "Failed to record deployment"
}

# Main execution
main() {
    # Check for force deploy flag
    FORCE_DEPLOY="false"
    if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
        FORCE_DEPLOY="true"
        echo -e "${YELLOW}Force deploy mode activated${NC}"
    fi
    
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
        /root/thermalog-ops/scripts/maintenance/docker-cleanup.sh > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Docker cleanup completed${NC}"
        fi
    fi
    
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    log "Automated deployment check completed"
    
    # Send consolidated email summary if there were any notifications
    send_consolidated_email
}

# Create lock file to prevent multiple instances
LOCKFILE="/tmp/auto-deploy.lock"

if [ -e "${LOCKFILE}" ]; then
    LOCK_PID=$(cat "${LOCKFILE}" 2>/dev/null)
    if [ ! -z "$LOCK_PID" ] && kill -0 $LOCK_PID 2>/dev/null; then
        echo "Deployment script is already running (PID: $LOCK_PID)"
        exit 1
    else
        echo "Removing stale lock file"
        rm -f "${LOCKFILE}"
    fi
fi

echo $$ > "${LOCKFILE}"
trap "rm -f ${LOCKFILE}" EXIT INT TERM

# Run main function with arguments
main "$@"