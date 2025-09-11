#!/bin/bash

# SSL Certificate Renewal Script for Thermalog
# Handles Let's Encrypt certificate renewal with Docker integration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/root/ssl-renewal.log"
DOMAIN="dashboard.thermalog.com.au"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
NGINX_CERT_DIR="/root/nginx"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     SSL CERTIFICATE RENEWAL - $(date)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

log "Starting SSL certificate renewal process"

# 1. Check current certificate expiry
echo -e "${YELLOW}Checking certificate expiry...${NC}"
DAYS_UNTIL_EXPIRY=$(certbot certificates | grep "VALID:" | grep -oP '\d+(?= days)' || echo "0")

log "Certificate expires in $DAYS_UNTIL_EXPIRY days"

if [ "$DAYS_UNTIL_EXPIRY" -gt 30 ]; then
    echo -e "${GREEN}✓ Certificate still valid for $DAYS_UNTIL_EXPIRY days (>30), no renewal needed${NC}"
    log "Certificate renewal skipped - still valid"
    exit 0
fi

echo -e "${YELLOW}Certificate expires in $DAYS_UNTIL_EXPIRY days, proceeding with renewal...${NC}"

# 2. Pre-renewal: Stop nginx container to free port 80
echo -e "${YELLOW}Stopping nginx for certificate renewal...${NC}"
NGINX_WAS_RUNNING=false
if docker ps | grep -q "nginx"; then
    docker compose stop nginx
    NGINX_WAS_RUNNING=true
    log "Nginx stopped for certificate renewal"
    sleep 5
fi

# 3. Renew certificate
echo -e "${YELLOW}Renewing SSL certificate...${NC}"
if certbot renew --standalone --non-interactive --agree-tos; then
    echo -e "${GREEN}✓ Certificate renewed successfully${NC}"
    log "Certificate renewal successful"
    
    # 4. Copy new certificates to nginx directory
    echo -e "${YELLOW}Copying certificates to nginx directory...${NC}"
    if [ -f "$CERT_PATH/fullchain.pem" ] && [ -f "$CERT_PATH/privkey.pem" ]; then
        cp "$CERT_PATH/fullchain.pem" "$NGINX_CERT_DIR/"
        cp "$CERT_PATH/privkey.pem" "$NGINX_CERT_DIR/"
        chmod 644 "$NGINX_CERT_DIR/fullchain.pem"
        chmod 600 "$NGINX_CERT_DIR/privkey.pem"
        echo -e "${GREEN}✓ Certificates copied to nginx directory${NC}"
        log "Certificates copied to nginx directory"
    else
        echo -e "${RED}✗ Certificate files not found at $CERT_PATH${NC}"
        log "ERROR: Certificate files not found"
    fi
    
else
    echo -e "${RED}✗ Certificate renewal failed${NC}"
    log "ERROR: Certificate renewal failed"
fi

# 5. Restart nginx container
if [ "$NGINX_WAS_RUNNING" = true ]; then
    echo -e "${YELLOW}Starting nginx with new certificates...${NC}"
    docker compose up -d nginx
    
    # Wait for nginx to start
    sleep 5
    
    # Verify nginx is running
    if docker ps | grep -q "nginx"; then
        echo -e "${GREEN}✓ Nginx restarted successfully${NC}"
        log "Nginx restarted with new certificates"
    else
        echo -e "${RED}✗ Failed to restart nginx${NC}"
        log "ERROR: Failed to restart nginx"
        
        # Try to start nginx again
        echo "Attempting to restart nginx again..."
        docker compose up -d nginx || true
    fi
fi

# 6. Verify SSL certificate
echo -e "${YELLOW}Verifying SSL certificate...${NC}"
if curl -f -s -I "https://$DOMAIN" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ SSL certificate is working correctly${NC}"
    log "SSL certificate verification successful"
    
    # Get certificate expiry info
    EXPIRY_DATE=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null | openssl x509 -noout -dates | grep notAfter | cut -d= -f2)
    echo -e "${GREEN}New certificate expires: $EXPIRY_DATE${NC}"
    log "New certificate expires: $EXPIRY_DATE"
    
else
    echo -e "${YELLOW}⚠ SSL certificate verification failed - check manually${NC}"
    log "WARNING: SSL certificate verification failed"
fi

# 7. Show final status
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}SSL Renewal Summary:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

certbot certificates | grep -A6 "$DOMAIN" | head -7

echo ""
echo "Container Status:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(nginx|NAMES)"

log "SSL certificate renewal process completed"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"