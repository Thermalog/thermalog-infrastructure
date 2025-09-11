#!/bin/bash

# Thermalog Infrastructure - Master Deployment Script
# One-click deployment for new servers or missing components
# This script detects what's missing and deploys everything automatically

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="/root"
LOG_FILE="/root/thermalog-deployment.log"
REQUIRED_PACKAGES=("docker" "docker-compose-plugin" "certbot" "git" "curl" "python3")

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}${BOLD}    THERMALOG INFRASTRUCTURE - MASTER DEPLOYMENT SCRIPT${NC}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}This script will:${NC}"
echo "  • Detect if this is a new server or has missing components"
echo "  • Install required packages and dependencies"
echo "  • Deploy all automation scripts and configurations"
echo "  • Set up systemd services and cron jobs"
echo "  • Configure SSL certificate auto-renewal"
echo "  • Enable complete server restart resilience"
echo ""

log "Starting master deployment script"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if service is enabled
service_enabled() {
    systemctl is-enabled "$1" >/dev/null 2>&1
}

# Function to check if file exists and is executable
file_executable() {
    [ -f "$1" ] && [ -x "$1" ]
}

# Function to detect server state
detect_server_state() {
    echo -e "${YELLOW}Detecting server state...${NC}"
    
    NEW_SERVER=false
    MISSING_COMPONENTS=false
    NEEDS_UPDATE=false
    
    # Check if this looks like a new server
    if [ ! -f "/root/auto-deploy.sh" ] && [ ! -f "/root/docker-compose.yml" ]; then
        NEW_SERVER=true
        echo -e "${BLUE}✓ Detected: New server (no existing Thermalog installation)${NC}"
    fi
    
    # Check for missing scripts
    REQUIRED_SCRIPTS=(
        "/root/auto-deploy.sh"
        "/root/docker-cleanup.sh"
        "/root/ssl-renew.sh"
        "/root/startup-thermalog.sh"
        "/root/setup-auto-deploy.sh"
    )
    
    for script in "${REQUIRED_SCRIPTS[@]}"; do
        if ! file_executable "$script"; then
            MISSING_COMPONENTS=true
            echo -e "${YELLOW}⚠ Missing: $script${NC}"
        fi
    done
    
    # Check for missing systemd services
    REQUIRED_SERVICES=(
        "thermalog.service"
        "thermalog-startup.service"
    )
    
    for service in "${REQUIRED_SERVICES[@]}"; do
        if [ ! -f "/etc/systemd/system/$service" ]; then
            MISSING_COMPONENTS=true
            echo -e "${YELLOW}⚠ Missing: /etc/systemd/system/$service${NC}"
        fi
    done
    
    # Check cron jobs
    if ! crontab -l 2>/dev/null | grep -q "auto-deploy.sh"; then
        MISSING_COMPONENTS=true
        echo -e "${YELLOW}⚠ Missing: Auto-deployment cron job${NC}"
    fi
    
    if [ "$NEW_SERVER" = true ]; then
        echo -e "${CYAN}📋 Deployment Plan: Complete new server setup${NC}"
    elif [ "$MISSING_COMPONENTS" = true ]; then
        echo -e "${CYAN}📋 Deployment Plan: Install missing components${NC}"
    else
        echo -e "${GREEN}✓ Server appears to be fully configured${NC}"
        echo -e "${BLUE}📋 Deployment Plan: Verify and update existing installation${NC}"
        NEEDS_UPDATE=true
    fi
    
    echo ""
}

# Function to install system packages
install_packages() {
    echo -e "${YELLOW}Installing system packages...${NC}"
    
    # Update package list
    apt update -q
    
    # Install required packages
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            echo "Installing $package..."
            case $package in
                "docker")
                    curl -fsSL https://get.docker.com -o get-docker.sh
                    sh get-docker.sh
                    rm get-docker.sh
                    ;;
                "docker-compose-plugin")
                    apt install -y docker-compose-plugin
                    ;;
                "certbot")
                    snap install --classic certbot
                    ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
                    ;;
                *)
                    apt install -y "$package"
                    ;;
            esac
        else
            echo "✓ $package already installed"
        fi
    done
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    # Enable and start cron
    systemctl enable cron
    systemctl start cron
    
    echo -e "${GREEN}✓ System packages installed${NC}"
}

# Function to deploy scripts
deploy_scripts() {
    echo -e "${YELLOW}Deploying automation scripts...${NC}"
    
    # Copy all scripts to target directory
    SCRIPTS=(
        "auto-deploy.sh"
        "docker-cleanup.sh"
        "ssl-renew.sh"
        "startup-thermalog.sh"
        "setup-auto-deploy.sh"
    )
    
    for script in "${SCRIPTS[@]}"; do
        if [ -f "$SCRIPT_DIR/scripts/$script" ]; then
            cp "$SCRIPT_DIR/scripts/$script" "$TARGET_DIR/"
            chmod +x "$TARGET_DIR/$script"
            echo "✓ Deployed $script"
        else
            echo -e "${RED}✗ Script not found: $script${NC}"
        fi
    done
    
    # Deploy server README
    if [ -f "$SCRIPT_DIR/server-README.md" ]; then
        cp "$SCRIPT_DIR/server-README.md" "$TARGET_DIR/README.md"
        echo "✓ Deployed server README.md"
    fi
    
    echo -e "${GREEN}✓ Scripts deployed${NC}"
}

# Function to deploy systemd services
deploy_systemd_services() {
    echo -e "${YELLOW}Deploying systemd services...${NC}"
    
    # Copy systemd service files
    if [ -d "$SCRIPT_DIR/configs/systemd" ]; then
        cp "$SCRIPT_DIR/configs/systemd"/*.service /etc/systemd/system/
        chmod 644 /etc/systemd/system/thermalog*.service
        
        # Reload systemd and enable services
        systemctl daemon-reload
        systemctl enable thermalog.service
        systemctl enable thermalog-startup.service
        
        echo "✓ Systemd services deployed and enabled"
    else
        echo -e "${YELLOW}⚠ Systemd configs not found, creating basic services${NC}"
        create_basic_systemd_services
    fi
    
    echo -e "${GREEN}✓ Systemd services configured${NC}"
}

# Function to create basic systemd services if configs are missing
create_basic_systemd_services() {
    # Create thermalog.service
    cat > /etc/systemd/system/thermalog.service << 'EOF'
[Unit]
Description=Thermalog Application Stack
Requires=docker.service
After=docker.service
Wants=network-online.target
After=network-online.target

[Service]
Type=forking
RemainAfterExit=yes
WorkingDirectory=/root
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
TimeoutStartSec=300
Restart=always
RestartSec=10
User=root
Group=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # Create thermalog-startup.service
    cat > /etc/systemd/system/thermalog-startup.service << 'EOF'
[Unit]
Description=Thermalog Startup Verification and Recovery
After=thermalog.service
Wants=thermalog.service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/root/startup-thermalog.sh
TimeoutStartSec=600
User=root
Group=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

# Function to setup cron jobs
setup_cron_jobs() {
    echo -e "${YELLOW}Setting up cron jobs...${NC}"
    
    # Get existing crontab or create empty one
    crontab -l 2>/dev/null > /tmp/current_cron || touch /tmp/current_cron
    
    # Define required cron jobs
    CRON_JOBS=(
        "*/5 * * * * /root/auto-deploy.sh >> /root/deployment-cron.log 2>&1"
        "0 2 * * * /root/docker-cleanup.sh >> /root/docker-cleanup-cron.log 2>&1"
        "15 3,15 * * * sleep \$((RANDOM \\% 3600)) && /root/ssl-renew.sh >> /root/ssl-renewal.log 2>&1"
        "@reboot sleep 60 && /root/startup-thermalog.sh >> /root/startup-thermalog.log 2>&1"
    )
    
    # Add missing cron jobs
    for job in "${CRON_JOBS[@]}"; do
        # Extract the command part for checking
        cmd_part=$(echo "$job" | sed 's/.*\(\/root\/[^>]*\).*/\1/')
        
        if ! grep -q "$cmd_part" /tmp/current_cron; then
            echo "$job" >> /tmp/current_cron
            echo "✓ Added cron job: $cmd_part"
        else
            echo "✓ Cron job already exists: $cmd_part"
        fi
    done
    
    # Install updated crontab
    crontab /tmp/current_cron
    rm /tmp/current_cron
    
    echo -e "${GREEN}✓ Cron jobs configured${NC}"
}

# Function to verify GitHub repositories
verify_repositories() {
    echo -e "${YELLOW}Verifying GitHub repositories...${NC}"
    
    REPOS=(
        "Thermalog-Backend"
        "Thermalog-frontend"
    )
    
    for repo in "${REPOS[@]}"; do
        if [ ! -d "/root/$repo" ]; then
            echo "Cloning $repo..."
            cd /root
            git clone "https://github.com/Thermalog/$repo.git"
        else
            echo "✓ Repository exists: $repo"
            # Update existing repo
            cd "/root/$repo"
            git fetch origin main >/dev/null 2>&1 || true
        fi
    done
    
    echo -e "${GREEN}✓ Repositories verified${NC}"
}

# Function to setup docker-compose
setup_docker_compose() {
    echo -e "${YELLOW}Setting up docker-compose.yml...${NC}"
    
    if [ ! -f "/root/docker-compose.yml" ]; then
        echo "Creating basic docker-compose.yml..."
        cat > /root/docker-compose.yml << 'EOF'
version: "3.8"

services:
  thermalog-backend:
    build:
      context: ./Thermalog-Backend
      dockerfile: Dockerfile
    container_name: thermalog-backend
    restart: always
    ports:
      - "3001:3001"
    env_file:
      - ./Thermalog-Backend/.env
    networks:
      - app-network
    command: >
      /bin/bash -c "
      npx prisma generate &&
      npx prisma migrate deploy &&
      pm2-runtime start dist/main.js --name 'Thermalog-Backend' --instances 1"

  thermalog-frontend:
    build:
      context: ./Thermalog-frontend
      dockerfile: Dockerfile
    container_name: thermalog-frontend
    env_file:
      - ./Thermalog-frontend/.env
    restart: always
    depends_on:
      - thermalog-backend
    networks:
      - app-network

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf
      - ./nginx/fullchain.pem:/etc/ssl/certs/fullchain.pem
      - ./nginx/privkey.pem:/etc/ssl/certs/privkey.pem
    depends_on:
      - thermalog-frontend
      - thermalog-backend
    networks:
      - app-network

networks:
  app-network:
    driver: bridge
EOF
        echo "✓ Created docker-compose.yml"
    else
        echo "✓ docker-compose.yml already exists"
    fi
    
    echo -e "${GREEN}✓ Docker Compose configured${NC}"
}

# Function to start services
start_services() {
    echo -e "${YELLOW}Starting services...${NC}"
    
    # Start systemd services
    systemctl start thermalog.service || true
    systemctl start thermalog-startup.service || true
    
    # Run startup verification
    if [ -f "/root/startup-thermalog.sh" ]; then
        echo "Running startup verification..."
        /root/startup-thermalog.sh || true
    fi
    
    echo -e "${GREEN}✓ Services started${NC}"
}

# Function to show final status
show_final_status() {
    echo ""
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}                        DEPLOYMENT COMPLETE!${NC}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Show service status
    echo -e "${BLUE}System Services Status:${NC}"
    systemctl is-active docker cron thermalog thermalog-startup | while read status; do
        if [ "$status" = "active" ]; then
            echo -e "  ${GREEN}✓ Service active${NC}"
        else
            echo -e "  ${YELLOW}⚠ Service: $status${NC}"
        fi
    done
    
    echo ""
    echo -e "${BLUE}Docker Containers:${NC}"
    if command_exists docker; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -10 || echo "  Containers starting up..."
    fi
    
    echo ""
    echo -e "${BLUE}Cron Jobs Configured:${NC}"
    crontab -l | grep -v "^#" | sed 's/^/  /'
    
    echo ""
    echo -e "${BLUE}Important Files Created:${NC}"
    ls -la /root/*.sh 2>/dev/null | awk '{print "  " $9}' | grep -v "^  $"
    
    echo ""
    echo -e "${GREEN}🎉 Your Thermalog server is now fully automated!${NC}"
    echo ""
    echo -e "${YELLOW}What happens now:${NC}"
    echo "  • Auto-deployment checks GitHub every 5 minutes"
    echo "  • Docker cleanup runs daily at 2 AM"
    echo "  • SSL certificates auto-renew twice daily"
    echo "  • Everything restarts automatically after server reboot"
    echo ""
    echo -e "${YELLOW}Quick commands to remember:${NC}"
    echo "  curl http://localhost:3001/api/health  # Check application health"
    echo "  docker ps                              # View running containers"
    echo "  tail -f /root/deployment.log           # Watch deployment activity"
    echo "  /root/startup-thermalog.sh             # Manual system verification"
    echo ""
    echo -e "${CYAN}For more help, check /root/README.md${NC}"
    
    log "Master deployment script completed successfully"
}

# Main execution flow
main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
    
    # Confirmation prompt
    echo -e "${RED}⚠️  WARNING: This script will modify system configuration${NC}"
    echo -e "${YELLOW}Do you want to proceed with the deployment? (y/N):${NC}"
    read -r confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
    
    echo ""
    log "Starting deployment with user confirmation"
    
    # Run deployment steps
    detect_server_state
    
    if [ "$NEW_SERVER" = true ] || [ "$MISSING_COMPONENTS" = true ]; then
        install_packages
        verify_repositories
        setup_docker_compose
        deploy_scripts
        deploy_systemd_services
        setup_cron_jobs
        start_services
    else
        # Just verify and update existing installation
        echo -e "${YELLOW}Verifying existing installation...${NC}"
        deploy_scripts
        deploy_systemd_services
        setup_cron_jobs
        echo -e "${GREEN}✓ Installation verified and updated${NC}"
    fi
    
    show_final_status
}

# Run main function
main "$@"