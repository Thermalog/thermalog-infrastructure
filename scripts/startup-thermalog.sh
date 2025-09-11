#!/bin/bash

# Thermalog Startup Script - Ensures all services start properly after server restart
# This script runs after system boot to verify and start all required services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/root/startup-thermalog.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     THERMALOG STARTUP VERIFICATION - $(date)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

log "Starting Thermalog startup verification"

# 1. Wait for Docker to be fully ready
echo -e "${YELLOW}Waiting for Docker service...${NC}"
for i in {1..30}; do
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✓ Docker service is active${NC}"
        break
    fi
    echo "Waiting for Docker... ($i/30)"
    sleep 2
done

# 2. Wait a bit more for Docker daemon to be fully ready
sleep 5

# 3. Start Docker Compose stack
echo -e "${YELLOW}Starting Thermalog application stack...${NC}"
cd /root

# Check if containers are already running
RUNNING_CONTAINERS=$(docker ps --format "{{.Names}}" | grep -E "(thermalog|nginx)" | wc -l)

if [ "$RUNNING_CONTAINERS" -ge 3 ]; then
    echo -e "${GREEN}✓ Application stack already running${NC}"
else
    echo "Starting application stack..."
    docker compose up -d
    
    # Wait for containers to start
    sleep 10
fi

# 4. Verify all containers are running
echo -e "${YELLOW}Verifying container status...${NC}"
EXPECTED_CONTAINERS=("thermalog-backend" "thermalog-frontend" "nginx")

for container in "${EXPECTED_CONTAINERS[@]}"; do
    if docker ps | grep -q "$container"; then
        echo -e "${GREEN}✓ $container is running${NC}"
    else
        echo -e "${RED}✗ $container is not running${NC}"
        log "ERROR: $container failed to start"
        
        # Try to start the specific container
        echo "Attempting to start $container..."
        docker compose up -d "$container" || true
    fi
done

# 5. Wait for backend to be ready and verify health
echo -e "${YELLOW}Verifying backend health...${NC}"
for i in {1..30}; do
    HEALTH_STATUS=$(curl -s http://localhost:3001/api/health 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('status', 'unknown'))" 2>/dev/null || echo "error")
    
    if [ "$HEALTH_STATUS" = "healthy" ]; then
        echo -e "${GREEN}✓ Backend is healthy and database is connected${NC}"
        break
    fi
    
    echo "Waiting for backend health... ($i/30)"
    sleep 2
done

# 6. Verify cron service and jobs
echo -e "${YELLOW}Verifying cron service...${NC}"
if systemctl is-active --quiet cron; then
    echo -e "${GREEN}✓ Cron service is active${NC}"
    
    # Check if our cron jobs exist
    if crontab -l | grep -q "auto-deploy.sh"; then
        echo -e "${GREEN}✓ Auto-deployment cron job is configured${NC}"
    else
        echo -e "${YELLOW}⚠ Auto-deployment cron job missing - run setup-auto-deploy.sh${NC}"
    fi
else
    echo -e "${RED}✗ Cron service is not running${NC}"
    systemctl start cron || true
fi

# 7. Show final status
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Final System Status:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

echo ""
echo "Docker Containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(thermalog|nginx|NAMES)"

echo ""
echo "System Services:"
systemctl is-active docker cron | while read status; do
    if [ "$status" = "active" ]; then
        echo -e "  ${GREEN}✓ Service active${NC}"
    else
        echo -e "  ${RED}✗ Service inactive${NC}"
    fi
done

echo ""
if curl -s http://localhost:3001/api/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Application is accessible and healthy${NC}"
else
    echo -e "${YELLOW}⚠ Application health check failed${NC}"
fi

log "Thermalog startup verification completed"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"