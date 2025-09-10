#!/bin/bash
# Comprehensive backup script for Thermalog infrastructure
# Creates backups of configuration, SSL certificates, and application data

set -e

# Configuration
BACKUP_DIR="/root/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/thermalog_backup_$DATE"

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

# Create backup directory
create_backup_dir() {
    print_status "Creating backup directory..."
    mkdir -p "$BACKUP_PATH"
    print_success "Backup directory created: $BACKUP_PATH"
}

# Backup SSL certificates
backup_ssl() {
    print_status "Backing up SSL certificates..."
    if [ -d "/etc/letsencrypt" ]; then
        cp -r /etc/letsencrypt "$BACKUP_PATH/"
        print_success "SSL certificates backed up"
    else
        print_warning "No SSL certificates found to backup"
    fi
}

# Backup Docker configurations
backup_docker_config() {
    print_status "Backing up Docker configurations..."
    
    # Main docker-compose file
    if [ -f "/root/docker-compose.yml" ]; then
        cp /root/docker-compose.yml "$BACKUP_PATH/"
    fi
    
    # Application directory
    if [ -d "/root/thermalog-app" ]; then
        cp -r /root/thermalog-app "$BACKUP_PATH/"
    fi
    
    print_success "Docker configurations backed up"
}

# Backup environment files
backup_env_files() {
    print_status "Backing up environment files..."
    
    mkdir -p "$BACKUP_PATH/env"
    
    # Backend .env (sanitized)
    if [ -f "/root/Thermalog-Backend/.env" ]; then
        # Remove sensitive data for backup
        grep -v "DATABASE_URL\|SECRET\|PASSWORD\|TOKEN" /root/Thermalog-Backend/.env > "$BACKUP_PATH/env/backend.env" 2>/dev/null || true
    fi
    
    # Frontend .env
    if [ -f "/root/Thermalog-frontend/.env" ]; then
        # Remove sensitive data for backup
        grep -v "SECRET\|PASSWORD\|TOKEN\|AUTH_TOKEN" /root/Thermalog-frontend/.env > "$BACKUP_PATH/env/frontend.env" 2>/dev/null || true
    fi
    
    print_success "Environment files backed up (sensitive data excluded)"
}

# Backup nginx configuration
backup_nginx() {
    print_status "Backing up nginx configuration..."
    
    mkdir -p "$BACKUP_PATH/nginx"
    
    # Extract current nginx config from container
    if docker ps | grep -q nginx; then
        docker cp nginx:/etc/nginx/conf.d/default.conf "$BACKUP_PATH/nginx/" 2>/dev/null || true
        print_success "Nginx configuration backed up"
    else
        print_warning "Nginx container not running, skipping nginx config backup"
    fi
}

# Backup application logs
backup_logs() {
    print_status "Backing up recent application logs..."
    
    mkdir -p "$BACKUP_PATH/logs"
    
    # Docker logs
    if docker ps | grep -q thermalog-backend; then
        docker logs thermalog-backend --tail 1000 > "$BACKUP_PATH/logs/backend.log" 2>&1 || true
    fi
    
    if docker ps | grep -q nginx; then
        docker logs nginx --tail 1000 > "$BACKUP_PATH/logs/nginx.log" 2>&1 || true
    fi
    
    # System logs
    if [ -f "/var/log/cert-deploy.log" ]; then
        cp /var/log/cert-deploy.log "$BACKUP_PATH/logs/"
    fi
    
    print_success "Application logs backed up"
}

# Create archive and cleanup
create_archive() {
    print_status "Creating backup archive..."
    
    cd "$BACKUP_DIR"
    tar -czf "thermalog_backup_$DATE.tar.gz" "thermalog_backup_$DATE/"
    rm -rf "thermalog_backup_$DATE/"
    
    # Keep only last 10 backups
    ls -t thermalog_backup_*.tar.gz | tail -n +11 | xargs rm -f 2>/dev/null || true
    
    print_success "Backup archive created: thermalog_backup_$DATE.tar.gz"
}

# Generate backup report
generate_report() {
    print_status "Generating backup report..."
    
    REPORT_FILE="$BACKUP_DIR/backup_report_$DATE.txt"
    
    cat > "$REPORT_FILE" << EOF
Thermalog Backup Report
Generated: $(date)
Backup File: thermalog_backup_$DATE.tar.gz

Components Backed Up:
- SSL Certificates: $([ -d "/etc/letsencrypt" ] && echo "✓" || echo "✗")
- Docker Configurations: ✓
- Environment Files: ✓ (sanitized)
- Nginx Configuration: $(docker ps | grep -q nginx && echo "✓" || echo "✗")
- Application Logs: ✓

Docker Container Status:
$(docker ps --format "table {{.Names}}\t{{.Status}}")

System Information:
Hostname: $(hostname)
Uptime: $(uptime)
Disk Usage: $(df -h / | tail -1 | awk '{print $5}')

Notes:
- Environment files have been sanitized (secrets removed)
- Only recent logs (last 1000 lines) are included
- SSL certificates are backed up in full
EOF
    
    print_success "Backup report generated: $REPORT_FILE"
}

# Main backup function
main() {
    print_status "Starting Thermalog backup process..."
    
    create_backup_dir
    backup_ssl
    backup_docker_config
    backup_env_files
    backup_nginx
    backup_logs
    create_archive
    generate_report
    
    print_success "Backup process completed!"
    print_status "Backup location: $BACKUP_DIR/thermalog_backup_$DATE.tar.gz"
    print_status "Backup report: $BACKUP_DIR/backup_report_$DATE.txt"
}

# Run main function
main "$@"