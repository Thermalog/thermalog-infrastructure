#!/bin/bash
# Comprehensive backup script for Thermalog infrastructure
# Creates backups of configuration, SSL certificates, application data, databases, and Docker volumes
# Updated for EMQX Platform and dual-stack Docker architecture (Main App + EMQX IoT Platform)
# Scheduled: Daily at 3:00 AM Sydney time (17:00 UTC)

set -e

# Configuration
BACKUP_DIR="/var/backups/thermalog"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$DATE"
LOG_FILE="/root/thermalog-ops/logs/maintenance/backup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "[INFO] $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log "✓ $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "⚠ $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "✗ $1"
}

# Create backup directory
create_backup_dir() {
    print_status "Creating backup directory..."
    mkdir -p "$BACKUP_PATH"
    log "Created backup directory: $BACKUP_PATH"
    print_success "Backup directory created: $BACKUP_PATH"
}

# Backup PostgreSQL database (IoT Platform)
backup_postgres() {
    print_status "Backing up PostgreSQL/TimescaleDB database..."

    mkdir -p "$BACKUP_PATH/database"

    if docker ps | grep -q iot-postgres; then
        # Dump the entire database
        docker exec iot-postgres pg_dump -U iotadmin iot_platform > "$BACKUP_PATH/database/iot_platform.sql" 2>/dev/null || {
            print_error "Failed to dump PostgreSQL database"
            return 1
        }

        # Compress the dump
        gzip "$BACKUP_PATH/database/iot_platform.sql"

        DBSIZE=$(du -h "$BACKUP_PATH/database/iot_platform.sql.gz" | cut -f1)
        print_success "PostgreSQL database backed up (${DBSIZE})"
    else
        print_warning "PostgreSQL container not running, skipping database backup"
    fi
}

# Backup Docker volumes
backup_docker_volumes() {
    print_status "Backing up Docker volumes..."

    mkdir -p "$BACKUP_PATH/docker-volumes"

    # List of volumes to backup
    VOLUMES=(
        "thermalog_uptime-kuma-data"
        "emqx-platform_postgres-data"
        "emqx-platform_emqx-data"
        "emqx-platform_emqx-log"
    )

    for volume in "${VOLUMES[@]}"; do
        if docker volume ls | grep -q "$volume"; then
            print_status "  → Backing up volume: $volume"
            docker run --rm \
                -v "$volume:/data" \
                -v "$BACKUP_PATH/docker-volumes:/backup" \
                alpine tar czf "/backup/${volume}.tar.gz" -C /data . 2>/dev/null || {
                print_warning "Failed to backup volume: $volume"
                continue
            }
            VOLSIZE=$(du -h "$BACKUP_PATH/docker-volumes/${volume}.tar.gz" | cut -f1)
            print_success "  ✓ ${volume} backed up (${VOLSIZE})"
        else
            print_warning "  ✗ Volume not found: $volume"
        fi
    done
}

# Backup SSL certificates (full /etc/letsencrypt including dual certs)
backup_ssl() {
    print_status "Backing up SSL certificates..."

    if [ -d "/etc/letsencrypt" ]; then
        mkdir -p "$BACKUP_PATH/ssl"
        cp -r /etc/letsencrypt/* "$BACKUP_PATH/ssl/" 2>/dev/null || true

        # Count certificates
        CERT_COUNT=$(find "$BACKUP_PATH/ssl/live" -type d -mindepth 1 2>/dev/null | wc -l)
        print_success "SSL certificates backed up (${CERT_COUNT} certificates: ECDSA + RSA)"
    else
        print_warning "No SSL certificates found to backup"
    fi
}

# Backup Docker configurations
backup_docker_config() {
    print_status "Backing up Docker configurations..."

    mkdir -p "$BACKUP_PATH/docker-config"

    # Main docker-compose file
    if [ -f "/root/docker-compose.yml" ]; then
        cp /root/docker-compose.yml "$BACKUP_PATH/docker-config/"
        print_success "  ✓ Main docker-compose.yml"
    fi

    # EMQX Platform
    if [ -d "/root/emqx-platform" ]; then
        mkdir -p "$BACKUP_PATH/emqx-platform"
        cp -r /root/emqx-platform/* "$BACKUP_PATH/emqx-platform/" 2>/dev/null || true
        # Exclude large node_modules and data directories
        rm -rf "$BACKUP_PATH/emqx-platform/node_modules" 2>/dev/null || true
        rm -rf "$BACKUP_PATH/emqx-platform/emqx-data" 2>/dev/null || true
        rm -rf "$BACKUP_PATH/emqx-platform/emqx-log" 2>/dev/null || true
        rm -rf "$BACKUP_PATH/emqx-platform/postgres-data" 2>/dev/null || true
        print_success "  ✓ EMQX Platform configuration"
    fi

    # Thermalog-ops directory
    if [ -d "/root/thermalog-ops" ]; then
        mkdir -p "$BACKUP_PATH/thermalog-ops"
        # Copy scripts and config, exclude logs and large files
        cp -r /root/thermalog-ops/scripts "$BACKUP_PATH/thermalog-ops/" 2>/dev/null || true
        cp -r /root/thermalog-ops/config "$BACKUP_PATH/thermalog-ops/" 2>/dev/null || true
        cp -r /root/thermalog-ops/docs "$BACKUP_PATH/thermalog-ops/" 2>/dev/null || true
        print_success "  ✓ Thermalog-ops scripts and configuration"
    fi

    print_success "Docker configurations backed up"
}

# Backup environment files (FULL backup with sensitive data)
backup_env_files() {
    print_status "Backing up environment files..."

    mkdir -p "$BACKUP_PATH/env"

    # Backend .env (FULL backup - no sanitization for restore purposes)
    if [ -f "/root/Thermalog-Backend/.env" ]; then
        cp "/root/Thermalog-Backend/.env" "$BACKUP_PATH/env/backend.env"
        print_success "  ✓ Backend .env"
    fi

    # Frontend .env
    if [ -f "/root/Thermalog-frontend/.env" ]; then
        cp "/root/Thermalog-frontend/.env" "$BACKUP_PATH/env/frontend.env"
        print_success "  ✓ Frontend .env"
    fi

    # Infrastructure .env
    if [ -f "/root/thermalog-infrastructure/.env" ]; then
        cp "/root/thermalog-infrastructure/.env" "$BACKUP_PATH/env/infrastructure.env"
        print_success "  ✓ Infrastructure .env"
    fi

    # EMQX Platform .env
    if [ -f "/root/emqx-platform/.env" ]; then
        cp "/root/emqx-platform/.env" "$BACKUP_PATH/env/emqx-platform.env"
        print_success "  ✓ EMQX Platform .env"
    fi

    print_success "Environment files backed up (FULL - includes sensitive data)"
}

# Backup systemd services
backup_systemd() {
    print_status "Backing up systemd services..."

    mkdir -p "$BACKUP_PATH/systemd"

    # Copy all Thermalog-related services
    cp /etc/systemd/system/thermalog*.service "$BACKUP_PATH/systemd/" 2>/dev/null || true
    cp /etc/systemd/system/emqx-platform.service "$BACKUP_PATH/systemd/" 2>/dev/null || true

    SERVICE_COUNT=$(ls -1 "$BACKUP_PATH/systemd/" 2>/dev/null | wc -l)
    print_success "Systemd services backed up (${SERVICE_COUNT} services)"
}

# Backup nginx configuration
backup_nginx() {
    print_status "Backing up nginx configuration..."

    mkdir -p "$BACKUP_PATH/nginx"

    # Nginx config directory
    if [ -d "/root/nginx" ]; then
        cp -r /root/nginx/* "$BACKUP_PATH/nginx/" 2>/dev/null || true
        print_success "  ✓ Nginx configuration files"
    fi

    # Extract current nginx config from container
    if docker ps | grep -q nginx; then
        docker cp nginx:/etc/nginx/conf.d/default.conf "$BACKUP_PATH/nginx/container-default.conf" 2>/dev/null || true
        print_success "  ✓ Active nginx container config"
    else
        print_warning "Nginx container not running"
    fi
}

# Backup crontab
backup_crontab() {
    print_status "Backing up crontab..."

    crontab -l > "$BACKUP_PATH/crontab.txt" 2>/dev/null || echo "No crontab entries" > "$BACKUP_PATH/crontab.txt"
    print_success "Crontab backed up"
}

# Backup root scripts and configs
backup_root_files() {
    print_status "Backing up root directory files..."

    mkdir -p "$BACKUP_PATH/root"

    # Copy scripts and config files
    cp -p /root/*.sh "$BACKUP_PATH/root/" 2>/dev/null || true
    cp -p /root/*.yml "$BACKUP_PATH/root/" 2>/dev/null || true
    cp -p /root/*.json "$BACKUP_PATH/root/" 2>/dev/null || true
    cp -p /root/*.md "$BACKUP_PATH/root/" 2>/dev/null || true

    FILE_COUNT=$(ls -1 "$BACKUP_PATH/root/" 2>/dev/null | wc -l)
    print_success "Root files backed up (${FILE_COUNT} files)"
}

# Backup system information
backup_system_info() {
    print_status "Backing up system information..."

    mkdir -p "$BACKUP_PATH/system-info"

    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" > "$BACKUP_PATH/system-info/docker-containers.txt"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" > "$BACKUP_PATH/system-info/docker-images.txt"
    docker volume ls > "$BACKUP_PATH/system-info/docker-volumes.txt"
    df -h > "$BACKUP_PATH/system-info/disk-usage.txt"
    free -h > "$BACKUP_PATH/system-info/memory-usage.txt"
    uname -a > "$BACKUP_PATH/system-info/system-info.txt"
    systemctl list-units --type=service --state=running > "$BACKUP_PATH/system-info/running-services.txt" 2>/dev/null || true

    print_success "System information backed up"
}

# Create archive and cleanup
create_archive() {
    print_status "Creating backup archive..."

    cd "$BACKUP_DIR"
    tar -czf "${DATE}.tar.gz" "${DATE}/"
    rm -rf "${DATE}/"

    ARCHIVE_SIZE=$(du -h "${DATE}.tar.gz" | cut -f1)

    # Keep only last 5 backups
    ls -t *.tar.gz 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true

    print_success "Backup archive created: ${DATE}.tar.gz (${ARCHIVE_SIZE})"
}

# Generate backup manifest
generate_manifest() {
    print_status "Generating backup manifest..."

    MANIFEST_FILE="$BACKUP_DIR/${DATE}_manifest.txt"

    cat > "$MANIFEST_FILE" << EOF
THERMALOG SERVER BACKUP
=======================
Generated: $(date)
Server: $(hostname)
Backup File: ${DATE}.tar.gz

CONTENTS:
---------
✓ PostgreSQL/TimescaleDB database dump (iot_platform)
✓ Docker volumes (4):
  - thermalog_uptime-kuma-data
  - emqx-platform_postgres-data
  - emqx-platform_emqx-data
  - emqx-platform_emqx-log
✓ SSL/TLS Certificates (dual: ECDSA + RSA)
✓ Docker configurations:
  - Main docker-compose.yml
  - EMQX Platform configuration
  - Thermalog-ops scripts
✓ Environment files (FULL - with sensitive data):
  - Backend .env
  - Frontend .env
  - Infrastructure .env
  - EMQX Platform .env
✓ Systemd services (thermalog*.service, emqx-platform.service)
✓ Nginx configuration
✓ Crontab
✓ Root directory scripts and configs
✓ System information and status

DOCKER CONTAINERS:
------------------
$(docker ps --format "{{.Names}}: {{.Status}}")

DISK USAGE:
-----------
$(df -h / | tail -1)

RESTORATION NOTES:
------------------
1. Database: gunzip database/iot_platform.sql.gz && docker exec -i iot-postgres psql -U iotadmin iot_platform < database/iot_platform.sql
2. Docker volumes: Use tar to extract each volume back to its mount point
3. Environment files: Copy from env/ directory to respective repository locations
4. Systemd services: Copy to /etc/systemd/system/ and run daemon-reload
5. SSL certificates: Copy to /etc/letsencrypt/
6. Crontab: crontab crontab.txt
7. Scripts: Copy to /root/ and chmod +x

SECURITY WARNING:
-----------------
This backup contains SENSITIVE DATA including:
- Database credentials
- API keys and secrets
- SSL private keys
- Environment variables with passwords
Store this backup SECURELY and restrict access!

EOF

    print_success "Backup manifest generated: ${DATE}_manifest.txt"
}

# Main backup function
main() {
    log "========== Starting Thermalog Comprehensive Backup =========="
    print_status "Starting backup process..."

    create_backup_dir
    backup_postgres
    backup_docker_volumes
    backup_ssl
    backup_docker_config
    backup_env_files
    backup_systemd
    backup_nginx
    backup_crontab
    backup_root_files
    backup_system_info
    create_archive
    generate_manifest

    FINAL_SIZE=$(du -h "$BACKUP_DIR/${DATE}.tar.gz" | cut -f1)

    print_success "=========================================="
    print_success "Backup process completed!"
    print_success "Backup file: $BACKUP_DIR/${DATE}.tar.gz"
    print_success "Archive size: $FINAL_SIZE"
    print_success "Manifest: $BACKUP_DIR/${DATE}_manifest.txt"
    print_success "=========================================="

    log "Backup completed successfully. Size: $FINAL_SIZE"
    log "========== Backup Process Finished =========="
}

# Run main function
main "$@"
