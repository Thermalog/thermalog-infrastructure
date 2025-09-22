#!/bin/bash

# Improved Uptime Kuma Alert Integration Script with Batched Notifications
# Sends consolidated email alerts instead of individual emails per monitor

set -e

# Source the existing email function
source /root/auto-deploy.sh

# Configuration
KUMA_DB="/var/lib/docker/volumes/root_uptime-kuma-data/_data/kuma.db"
ALERT_LOG="/root/uptime-alerts.log"
STATE_FILE="/tmp/uptime-kuma-state"
COOLDOWN_FILE="/tmp/monitor-cooldown.state"
HEALTH_CHECK_RETRIES=3
HEALTH_CHECK_DELAY=5

# Batching configuration
BATCH_EMAILS=true
MIN_NOTIFICATION_INTERVAL=300  # 5 minutes cooldown per monitor
SKIP_PENDING_ALERTS=true      # Don't send emails for PENDING status
SUMMARY_ONLY_MODE=false        # Set to true for brief emails

log_alert() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $ALERT_LOG
}

# Check if cooldown period has passed for a monitor
check_cooldown() {
    local monitor_id=$1
    local current_time=$(date +%s)
    
    if [ -f "$COOLDOWN_FILE" ]; then
        local last_notification=$(grep "^$monitor_id|" "$COOLDOWN_FILE" 2>/dev/null | cut -d'|' -f2)
        if [ -n "$last_notification" ]; then
            local time_diff=$((current_time - last_notification))
            if [ $time_diff -lt $MIN_NOTIFICATION_INTERVAL ]; then
                return 1  # Still in cooldown
            fi
        fi
    fi
    return 0  # No cooldown or cooldown expired
}

# Update cooldown timestamp for a monitor
update_cooldown() {
    local monitor_id=$1
    local current_time=$(date +%s)
    
    # Remove old entry if exists
    if [ -f "$COOLDOWN_FILE" ]; then
        grep -v "^$monitor_id|" "$COOLDOWN_FILE" > "${COOLDOWN_FILE}.tmp" 2>/dev/null || true
        mv "${COOLDOWN_FILE}.tmp" "$COOLDOWN_FILE"
    fi
    
    # Add new entry
    echo "$monitor_id|$current_time" >> "$COOLDOWN_FILE"
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
    # Use -k flag to ignore SSL certificate warnings for localhost
    local backend_health=$(curl -s -o /dev/null -w "%{http_code}" -k https://localhost/api/health 2>/dev/null | grep -q "200" && echo "✅ Online" || echo "❌ Offline")
    local frontend_health=$(check_service_health "Frontend" "http://localhost:80")
    local dashboard_health=$(check_service_health "Dashboard" "https://dashboard.thermalog.com.au")
    local mqtt_health=$(nc -zv localhost 1883 2>/dev/null && echo "✅ Online" || echo "❌ Offline")
    local mqtt_tls_health=$(nc -zv localhost 8883 2>/dev/null && echo "✅ Online" || echo "❌ Offline")
    local mqtt_ws_health=$(nc -zv localhost 9001 2>/dev/null && echo "✅ Online" || echo "❌ Offline")
    local provisioning_health=$(check_service_health "Provisioning" "http://localhost:3003/health")
    local tasmota_health=$(check_service_health "Tasmota API" "http://localhost:3003/api/provisioning/tasmota/discover.json")
    local nginx_health=$(curl -s -o /dev/null -w "%{http_code}" -k https://localhost 2>/dev/null | grep -q "200" && echo "✅ Online" || echo "❌ Offline")
    local uptime_health=$(check_service_health "Uptime Kuma" "http://localhost:3002")
    
    # Get container info - include ALL containers
    local container_status=$(docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'thermalog|nginx|mqtt|provisioning|uptime' || echo "No containers found")
    
    # Check database connection - simplified approach
    local db_status="❌ Disconnected"
    if docker exec thermalog-backend sh -c "echo 'SELECT 1;' | npx prisma db execute --stdin --schema=/app/prisma/schema/schema.prisma 2>&1" | grep -q "Script executed successfully"; then
        db_status="✅ Connected"
    fi
    
    echo "
🏥 SYSTEM HEALTH REPORT:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Service Status:
• Backend API: $backend_health
• Frontend: $frontend_health
• Dashboard: $dashboard_health
• Database: $db_status
• HTTPS/Nginx: $nginx_health
• MQTT Broker (1883): $mqtt_health
• MQTT TLS (8883): $mqtt_tls_health
• MQTT WebSocket (9001): $mqtt_ws_health
• Provisioning Service: $provisioning_health
• Tasmota API: $tasmota_health
• Uptime Kuma: $uptime_health

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

# Compare with previous state and collect changes
if ! diff -q "$STATE_FILE" "${STATE_FILE}.new" >/dev/null 2>&1; then
    log_alert "📊 Monitor status changes detected"
    
    # Arrays to collect changes by type
    declare -a DOWN_MONITORS=()
    declare -a UP_MONITORS=()
    declare -a PENDING_MONITORS=()
    declare -a ALL_CHANGES=()
    SEND_NOTIFICATION=false
    
    # Find changes
    while IFS='|' read -r id name type status msg time; do
        # Get previous status for this monitor
        PREV_STATUS=$(grep "^$id|" "$STATE_FILE" 2>/dev/null | cut -d'|' -f4 || echo "UNKNOWN")
        
        if [ "$status" != "$PREV_STATUS" ] && [ "$PREV_STATUS" != "UNKNOWN" ]; then
            
            # Skip certain transitions if configured
            if [ "$SKIP_PENDING_ALERTS" = true ]; then
                # Skip PENDING transitions that aren't critical
                if [ "$status" = "PENDING" ] || [ "$PREV_STATUS" = "PENDING" ]; then
                    if [ "$status" != "DOWN" ] && [ "$PREV_STATUS" != "DOWN" ]; then
                        log_alert "⏩ Skipping non-critical transition: $name ($PREV_STATUS → $status)"
                        continue
                    fi
                fi
            fi
            
            # Check cooldown
            if ! check_cooldown "$id"; then
                log_alert "⏰ Monitor '$name' still in cooldown period, skipping notification"
                continue
            fi
            
            # Categorize the change
            case "$status" in
                "DOWN")
                    DOWN_MONITORS+=("• $name - ${msg:-'Service unreachable'}")
                    ALL_CHANGES+=("🚨 $name: $PREV_STATUS → DOWN")
                    SEND_NOTIFICATION=true
                    update_cooldown "$id"
                    ;;
                "UP")
                    if [ "$PREV_STATUS" = "DOWN" ]; then
                        UP_MONITORS+=("• $name - Service recovered")
                        ALL_CHANGES+=("✅ $name: DOWN → UP")
                        SEND_NOTIFICATION=true
                        update_cooldown "$id"
                    fi
                    ;;
                "PENDING")
                    if [ "$SKIP_PENDING_ALERTS" = false ]; then
                        PENDING_MONITORS+=("• $name - Status being evaluated")
                        ALL_CHANGES+=("⏳ $name: $PREV_STATUS → PENDING")
                    fi
                    ;;
            esac
            
            log_alert "$EMOJI Monitor '$name' changed: $PREV_STATUS → $status"
            
            # Log to monitoring history
            echo "$(date '+%Y-%m-%d %H:%M:%S'),${name},${PREV_STATUS},${status},${msg}" >> /root/monitoring-history.csv
        fi
    done <<< "$CURRENT_STATUS"
    
    # Send batched notification if there are significant changes
    if [ "$SEND_NOTIFICATION" = true ]; then
        
        # Count total changes
        TOTAL_CHANGES=$((${#DOWN_MONITORS[@]} + ${#UP_MONITORS[@]} + ${#PENDING_MONITORS[@]}))
        
        # Determine priority
        if [ ${#DOWN_MONITORS[@]} -gt 0 ]; then
            PRIORITY="high"
            EMOJI="🚨"
            STATUS_TEXT="ALERT"
        else
            PRIORITY="normal"
            EMOJI="📊"
            STATUS_TEXT="UPDATE"
        fi
        
        # Build subject
        ALERT_SUBJECT="$EMOJI Thermalog $STATUS_TEXT: $TOTAL_CHANGES monitor(s) changed"
        
        # Build message body
        ALERT_MESSAGE="📊 MONITORING SYSTEM UPDATE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⏰ Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')
📈 Total Changes: $TOTAL_CHANGES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"
        
        # Add sections for each status type
        if [ ${#DOWN_MONITORS[@]} -gt 0 ]; then
            ALERT_MESSAGE+="
🚨 SERVICES DOWN (${#DOWN_MONITORS[@]}):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$(printf '%s\n' "${DOWN_MONITORS[@]}")

🔧 IMMEDIATE ACTIONS REQUIRED:
• Check container logs for errors
• Verify network connectivity
• Review recent configuration changes
"
        fi
        
        if [ ${#UP_MONITORS[@]} -gt 0 ]; then
            ALERT_MESSAGE+="
✅ SERVICES RECOVERED (${#UP_MONITORS[@]}):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$(printf '%s\n' "${UP_MONITORS[@]}")
"
        fi
        
        if [ ${#PENDING_MONITORS[@]} -gt 0 ] && [ "$SKIP_PENDING_ALERTS" = false ]; then
            ALERT_MESSAGE+="
⏳ PENDING CHECKS (${#PENDING_MONITORS[@]}):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$(printf '%s\n' "${PENDING_MONITORS[@]}")
"
        fi
        
        # Add system health report unless in summary mode
        if [ "$SUMMARY_ONLY_MODE" = false ]; then
            ALERT_MESSAGE+="
$(get_system_status)
"
        fi
        
        # Add footer
        ALERT_MESSAGE+="
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Uptime Kuma Dashboard: http://$(curl -s ipinfo.io/ip 2>/dev/null):3002
🌐 Production Site: https://dashboard.thermalog.com.au
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Generated by Thermalog Monitoring System
Server: $(hostname)
Next check in: 2 minutes
"
        
        # Send the consolidated email
        send_email "$ALERT_SUBJECT" "$ALERT_MESSAGE" "$PRIORITY"
        
        log_alert "✉️ Sent consolidated alert for $TOTAL_CHANGES monitor changes"
    else
        log_alert "ℹ️ Changes detected but no critical alerts to send"
    fi
    
    # Update state file
    mv "${STATE_FILE}.new" "$STATE_FILE"
else
    # No changes - clean up
    rm -f "${STATE_FILE}.new"
fi

# Clean up old cooldown entries (older than 1 hour)
if [ -f "$COOLDOWN_FILE" ]; then
    current_time=$(date +%s)
    while IFS='|' read -r monitor_id timestamp; do
        if [ $((current_time - timestamp)) -gt 3600 ]; then
            grep -v "^$monitor_id|" "$COOLDOWN_FILE" > "${COOLDOWN_FILE}.tmp" 2>/dev/null || true
        fi
    done < "$COOLDOWN_FILE"
    if [ -f "${COOLDOWN_FILE}.tmp" ]; then
        mv "${COOLDOWN_FILE}.tmp" "$COOLDOWN_FILE"
    fi
fi

log_alert "✅ Monitor check completed"