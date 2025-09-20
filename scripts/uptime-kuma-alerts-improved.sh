#!/bin/bash

# Improved Uptime Kuma Alert Integration Script
# Monitors Uptime Kuma database and sends accurate email alerts

set -e

# Source the existing email function
source /root/auto-deploy.sh

# Configuration
KUMA_DB="/var/lib/docker/volumes/root_uptime-kuma-data/_data/kuma.db"
ALERT_LOG="/root/uptime-alerts.log"
STATE_FILE="/tmp/uptime-kuma-state"
HEALTH_CHECK_RETRIES=3
HEALTH_CHECK_DELAY=5

log_alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $ALERT_LOG
}

# Improved health check with retries
check_service_health() {
    local service=$1
    local url=$2
    local retries=${3:-$HEALTH_CHECK_RETRIES}
    
    for i in $(seq 1 $retries); do
        if curl -s -f -o /dev/null -m 5 "$url" 2>/dev/null; then
            echo "✅ Online"
            return 0
        fi
        [ $i -lt $retries ] && sleep $HEALTH_CHECK_DELAY
    done
    echo "❌ Offline"
    return 1
}

# Get detailed system status
get_system_status() {
    local backend_health=$(check_service_health "Backend" "http://localhost:3001/api/health")
    local frontend_health=$(check_service_health "Frontend" "http://localhost:80")
    local dashboard_health=$(check_service_health "Dashboard" "https://dashboard.thermalog.com.au")
    
    # Get container info
    local container_status=$(docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'thermalog|nginx' || echo "No containers found")
    
    # Check database connection
    local db_status="Unknown"
    if docker exec thermalog-backend npm run db:check 2>/dev/null; then
        db_status="✅ Connected"
    else
        db_status="❌ Disconnected"
    fi
    
    echo "
🏥 SYSTEM HEALTH REPORT:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Service Status:
• Backend API: $backend_health
• Frontend: $frontend_health
• Dashboard: $dashboard_health
• Database: $db_status

🐳 Container Status:
$container_status

💾 System Resources:
$(df -h / | tail -1 | awk '{print "• Disk Usage: "$3"/"$2" ("$5")"}')
$(free -h | grep Mem | awk '{print "• Memory: "$3"/"$2}')
$(uptime | awk -F'load average:' '{print "• Load Average:"$2}')
━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Check if Uptime Kuma container is running
if ! docker ps | grep -q uptime-kuma; then
    log_alert "❌ Uptime Kuma container is not running"
    exit 1
fi

# Get current monitor status
CURRENT_STATUS=$(docker exec uptime-kuma sqlite3 /app/data/kuma.db "
SELECT m.id, m.name, m.type, 
       CASE 
         WHEN h.status = 0 THEN 'DOWN'
         WHEN h.status = 1 THEN 'UP' 
         WHEN h.status = 2 THEN 'PENDING'
         ELSE 'UNKNOWN'
       END as status,
       h.msg, h.time
FROM monitor m 
LEFT JOIN heartbeat h ON m.id = h.monitor_id 
WHERE h.time = (SELECT MAX(time) FROM heartbeat WHERE monitor_id = m.id)
ORDER BY m.id;
" 2>/dev/null)

# Create current state file
echo "$CURRENT_STATUS" > "${STATE_FILE}.new"

# Check if this is first run
if [ ! -f "$STATE_FILE" ]; then
    log_alert "🔄 First run - initializing monitor state tracking"
    mv "${STATE_FILE}.new" "$STATE_FILE"
    exit 0
fi

# Compare with previous state
if ! diff -q "$STATE_FILE" "${STATE_FILE}.new" >/dev/null 2>&1; then
    log_alert "📊 Monitor status changes detected"
    
    # Find changes
    while IFS='|' read -r id name type status msg time; do
        # Get previous status for this monitor
        PREV_STATUS=$(grep "^$id|" "$STATE_FILE" 2>/dev/null | cut -d'|' -f4 || echo "UNKNOWN")
        
        if [ "$status" != "$PREV_STATUS" ] && [ "$PREV_STATUS" != "UNKNOWN" ]; then
            
            # For recovery alerts, wait for services to fully initialize
            if [ "$status" = "UP" ] && [ "$PREV_STATUS" = "DOWN" ]; then
                log_alert "⏳ Waiting for services to fully initialize before sending recovery alert..."
                sleep 10
            fi
            
            # Get detailed system status
            SYSTEM_STATUS=$(get_system_status)
            
            # Determine alert type and create appropriate message
            case "$status" in
                "DOWN")
                    EMOJI="🚨"
                    PRIORITY="high"
                    ACTION="FAILURE DETECTED"
                    COLOR="#FF0000"
                    ALERT_TYPE="⚠️ SERVICE DOWN ALERT ⚠️"
                    RECOMMENDATION="
🔧 RECOMMENDED ACTIONS:
1. Check container logs: docker logs thermalog-backend
2. Verify database connection: docker exec thermalog-backend npm run db:check
3. Check system resources: df -h && free -h
4. Review recent deployments: git log --oneline -5"
                    ;;
                "UP")
                    EMOJI="✅"
                    PRIORITY="normal"
                    ACTION="SERVICE RECOVERED"
                    COLOR="#00FF00"
                    ALERT_TYPE="🎉 RECOVERY NOTIFICATION 🎉"
                    RECOMMENDATION="
✨ RECOVERY CONFIRMED:
• Service is back online and operational
• Monitoring will continue as normal
• Review logs to identify root cause if needed"
                    ;;
                "PENDING")
                    EMOJI="⚠️"
                    PRIORITY="normal"
                    ACTION="STATUS PENDING"
                    COLOR="#FFA500"
                    ALERT_TYPE="⏳ PENDING STATUS ALERT"
                    RECOMMENDATION="
📝 NOTES:
• Service status is being evaluated
• This may indicate initialization or restart
• Monitor will update status shortly"
                    ;;
                *)
                    EMOJI="❓"
                    PRIORITY="normal"
                    ACTION="UNKNOWN STATUS"
                    COLOR="#808080"
                    ALERT_TYPE="❓ STATUS UNKNOWN"
                    RECOMMENDATION="
🔍 INVESTIGATION NEEDED:
• Manual verification required
• Check Uptime Kuma dashboard
• Verify monitoring configuration"
                    ;;
            esac
            
            # Create detailed alert message
            ALERT_SUBJECT="$EMOJI Thermalog: $name $ACTION"
            ALERT_MESSAGE="$ALERT_TYPE

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🖥️  Monitor: $name
📊 Status Change: $PREV_STATUS → $status
⏰ Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')
💬 Monitor Message: ${msg:-'OK'}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 MONITOR INFORMATION:
• Monitor ID: $id
• Monitor Type: $type
• Previous Status: $PREV_STATUS
• Current Status: $status
• Detection Time: $time

$SYSTEM_STATUS

$RECOMMENDATION

━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Uptime Kuma Dashboard: http://$(curl -s ipinfo.io/ip 2>/dev/null):3002
🌐 Production Site: https://dashboard.thermalog.com.au
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Generated by Thermalog Monitoring System
Server: $(hostname)
"

            # Send email using existing system
            send_email "$ALERT_SUBJECT" "$ALERT_MESSAGE" "$PRIORITY"
            
            log_alert "$EMOJI Monitor '$name' changed: $PREV_STATUS → $status"
            
            # Log to monitoring history
            echo "$(date '+%Y-%m-%d %H:%M:%S'),${name},${PREV_STATUS},${status},${msg}" >> /root/monitoring-history.csv
        fi
    done <<< "$CURRENT_STATUS"
    
    # Update state file
    mv "${STATE_FILE}.new" "$STATE_FILE"
else
    # No changes - clean up
    rm -f "${STATE_FILE}.new"
fi

log_alert "✅ Monitor check completed"