# Thermalog Server Backup & Recovery System

## Overview

The Thermalog server backup system provides comprehensive backup and recovery capabilities for all critical server configuration files, environment variables, SSL certificates, and operational data. The system supports both unencrypted (for fast local recovery) and encrypted backups (for secure off-site storage).

**Two Backup Scripts:**
- **`/root/thermalog-infrastructure/scripts/backup.sh`** - Creates unencrypted backups (automated daily)
- **`/root/thermalog-ops/scripts/backup/create-encrypted-backup.sh`** - Creates encrypted backups (manual, for off-site storage)

## Backup Components

### What's Included (UPDATED for EMQX Platform)
- **PostgreSQL/TimescaleDB Database**: Complete dump of `iot_platform` database (compressed with gzip)
- **Docker Volumes** (4 volumes - full backup):
  - `thermalog_uptime-kuma-data` - Monitoring configuration and history
  - `emqx-platform_postgres-data` - PostgreSQL/TimescaleDB database files
  - `emqx-platform_emqx-data` - EMQX broker data and configuration
  - `emqx-platform_emqx-log` - EMQX broker logs
- **Configuration Scripts**: All shell scripts, YAML files, JSON configs from `/root/`
- **Environment Variables**: `.env` files from ALL repositories - **FULL backup including sensitive data**:
  - Backend .env (`/root/Thermalog-Backend/.env`)
  - Frontend .env (`/root/Thermalog-frontend/.env`)
  - Infrastructure .env (`/root/thermalog-infrastructure/.env`)
  - EMQX Platform .env (`/root/emqx-platform/.env`)
- **Nginx Configuration**: Complete nginx setup from `/root/nginx/` plus active container config
- **EMQX Platform**: Complete configuration (docker-compose.yml, config files, provisioning service)
- **Thermalog-ops Directory**: All operational scripts (`/root/thermalog-ops/scripts/`, config, docs)
- **Systemd Services**: ALL service definitions:
  - thermalog.service
  - thermalog-startup.service
  - thermalog-shutdown.service
  - emqx-platform.service
- **SSL Certificates**: Complete `/etc/letsencrypt/` directory (dual certificates: ECDSA + RSA)
- **Docker Configurations**: Main docker-compose.yml (`/root/docker-compose.yml`) and all configs
- **System Information**: Docker containers, images, volumes, resource usage, running services
- **Network Configuration**: Hosts file, routing tables
- **Crontab**: ALL scheduled tasks and automation
- **Root Files**: All scripts, configs, and markdown files from `/root/`

### What's Excluded
- Source code repositories (can be cloned from Git)
- Large log files (only recent entries included)
- Temporary files and caches
- Git repositories (`.git` directories)

## Backup Scripts

### Main Backup Script: `/root/thermalog-infrastructure/scripts/backup.sh`
**Primary backup script** - Creates comprehensive unencrypted backup for production use.

```bash
# Run backup manually
/root/thermalog-infrastructure/scripts/backup.sh

# Output location
/var/backups/thermalog/YYYYMMDD_HHMMSS.tar.gz

# Manifest file
/var/backups/thermalog/YYYYMMDD_HHMMSS_manifest.txt
```

**Automated Schedule:** Daily at 3:00 AM via cron
**Log File:** `/root/thermalog-ops/logs/maintenance/backup.log`
**Retention:** Last 5 backups kept automatically

**What it backs up:**
- PostgreSQL database (pg_dump + gzip)
- All 4 Docker volumes
- Complete system configuration
- SSL certificates (both ECDSA and RSA)
- Environment files with secrets
- EMQX platform configuration
- All systemd services

### Encrypted Backup: `/root/thermalog-ops/scripts/backup/create-encrypted-backup.sh`
Creates AES-256-CBC encrypted archive for secure off-site storage and transmission.

```bash
# Run encrypted backup
/root/thermalog-ops/scripts/backup/create-encrypted-backup.sh

# Output location
/root/thermalog-infrastructure/backups/thermalog_server_backup_YYYYMMDD_HHMMSS_encrypted.tar.gz.enc
```

**Encryption Details:**
- Algorithm: AES-256-CBC with salt
- Key: `ThermalogDigital!@#$`
- Tool: OpenSSL
- **Use for off-site backups only**

**Note:** Contains identical data to main backup but encrypted. Keep encryption key separate from backup!

### Backup Verification: `/root/thermalog-infrastructure/scripts/verify-latest-backup.sh`
Verifies integrity of the latest backup archive.

```bash
# Run verification
/root/thermalog-infrastructure/scripts/verify-latest-backup.sh

# Verification report
/var/backups/thermalog/YYYYMMDD_HHMMSS_verification.txt
```

**Automated Schedule:** Weekly at 4:00 AM on Sundays
**Log File:** `/root/thermalog-ops/logs/maintenance/backup-verify.log`

**Verification checks:**
- Archive integrity (tar test)
- File size within expected range (10MB - 500MB)
- Database dump present and valid
- All required components present
- Backup age (warns if > 48 hours old)

## Backup Extraction

### Using the Extraction Script

The `extract-backup.sh` script provides a user-friendly interface for decrypting and extracting backup archives.

#### Basic Usage
```bash
# Extract to default location (/tmp/thermalog_backup_extraction)
./extract-backup.sh backup_file.tar.gz.enc

# Extract to specific directory
./extract-backup.sh -o /path/to/extract backup_file.tar.gz.enc

# List available backups
./extract-backup.sh -l

# Verify backup integrity without extracting
./extract-backup.sh -v backup_file.tar.gz.enc

# Show help
./extract-backup.sh -h
```

#### Script Features
- **Automatic decryption** using stored encryption key
- **Integrity verification** before extraction
- **Colorized output** for better readability
- **Detailed progress reporting** with file counts and sizes
- **Backup listing** to show available archives
- **Manifest display** showing backup contents and restoration instructions

### Manual Extraction

#### For Encrypted Backups
```bash
# Decrypt the archive
openssl enc -aes-256-cbc -d -in backup_encrypted.tar.gz.enc -out backup.tar.gz -pass pass:ThermalogDigital!@#$

# Extract the archive
tar -xzf backup.tar.gz
```

#### For Regular Backups
```bash
# Extract directly
tar -xzf backup.tar.gz
```

## Restoration Process

### Pre-Restoration Checklist
1. **Stop all services** to prevent conflicts
2. **Backup current state** if needed
3. **Verify backup integrity** using verification mode
4. **Review backup manifest** for contents and instructions

### Step-by-Step Restoration

#### 1. Extract the Backup
```bash
./extract-backup.sh -o /tmp/restore backup_file.tar.gz.enc
cd /tmp/restore/thermalog_server_backup_YYYYMMDD_HHMMSS
```

#### 2. Restore Environment Files
```bash
# Backend environment
cp env/backend.env /root/Thermalog-Backend/.env

# Frontend environment
cp env/frontend.env /root/Thermalog-frontend/.env

# Infrastructure environment
cp env/infrastructure.env /root/thermalog-infrastructure/.env

# EMQX Platform environment (CRITICAL for IoT platform)
cp env/emqx-platform.env /root/emqx-platform/.env
```

**Note:** Environment files contain sensitive credentials. Ensure proper file permissions:
```bash
chmod 600 /root/Thermalog-Backend/.env
chmod 600 /root/Thermalog-frontend/.env
chmod 600 /root/thermalog-infrastructure/.env
chmod 600 /root/emqx-platform/.env
```

#### 3. Restore System Configuration
```bash
# Copy root scripts and configurations
cp root/* /root/
chmod +x /root/*.sh

# Restore nginx configuration
cp -r nginx/* /root/nginx/

# Restore SSL certificates
cp ssl/* /root/nginx/
```

#### 4. Restore System Services
```bash
# Copy systemd service files
sudo cp systemd/* /etc/systemd/system/

# Reload systemd
sudo systemctl daemon-reload

# Enable services
sudo systemctl enable thermalog-*.service
```

#### 5. Restore Crontab
```bash
# Review crontab entries
cat crontab.txt

# Restore crontab (be careful not to overwrite existing entries)
crontab crontab.txt
```

#### 6. Restore PostgreSQL/TimescaleDB Database
```bash
# Ensure PostgreSQL container is running
cd /root/emqx-platform && docker-compose up -d iot-postgres
sleep 10  # Wait for PostgreSQL to start

# Decompress the backup
gunzip database/iot_platform.sql.gz

# Drop existing database (CAUTION: This deletes all current data!)
docker exec iot-postgres psql -U iotadmin -c "DROP DATABASE IF EXISTS iot_platform;"

# Create fresh database
docker exec iot-postgres psql -U iotadmin -c "CREATE DATABASE iot_platform;"

# Restore database from backup
docker exec -i iot-postgres psql -U iotadmin iot_platform < database/iot_platform.sql

# Verify restoration
docker exec iot-postgres psql -U iotadmin iot_platform -c "SELECT COUNT(*) FROM device_credentials;"
```

**Important:** Database restoration will overwrite ALL existing data. Make sure you have a current backup before restoring!

#### 7. Restore Docker Volumes
```bash
# Stop all containers first
docker-compose -f /root/docker-compose.yml down
cd /root/emqx-platform && docker-compose down

# Restore Uptime Kuma volume
docker volume create thermalog_uptime-kuma-data 2>/dev/null || true
docker run --rm \
  -v thermalog_uptime-kuma-data:/data \
  -v $(pwd)/docker-volumes:/backup \
  alpine tar xzf /backup/thermalog_uptime-kuma-data.tar.gz -C /data

# Restore PostgreSQL data volume
docker volume create emqx-platform_postgres-data 2>/dev/null || true
docker run --rm \
  -v emqx-platform_postgres-data:/data \
  -v $(pwd)/docker-volumes:/backup \
  alpine tar xzf /backup/emqx-platform_postgres-data.tar.gz -C /data

# Restore EMQX data volume
docker volume create emqx-platform_emqx-data 2>/dev/null || true
docker run --rm \
  -v emqx-platform_emqx-data:/data \
  -v $(pwd)/docker-volumes:/backup \
  alpine tar xzf /backup/emqx-platform_emqx-data.tar.gz -C /data

# Restore EMQX log volume
docker volume create emqx-platform_emqx-log 2>/dev/null || true
docker run --rm \
  -v emqx-platform_emqx-log:/data \
  -v $(pwd)/docker-volumes:/backup \
  alpine tar xzf /backup/emqx-platform_emqx-log.tar.gz -C /data
```

**Note:** Docker volumes contain persistent data. Choose either database dump restoration (step 6) OR volume restoration, not both!
- **Use database dump**: If you want clean restoration with just data
- **Use volume restoration**: If you want exact replica including all PostgreSQL internals

#### 7. Restart Services
```bash
# Restart all containers
docker compose down
docker compose up -d

# Verify services are running
docker ps
systemctl status thermalog-*
```

#### 8. Verification
```bash
# Check service health
curl -f http://localhost:3001/api/health
curl -f http://localhost:80
curl -f https://dashboard.thermalog.com.au

# Check logs for errors
docker logs thermalog-backend
docker logs thermalog-frontend
```

## Backup Schedule

### Current Automated Schedule (Production)
- ✅ **Daily Backup**: 3:00 AM Sydney time - Comprehensive backup of all components
- ✅ **Weekly Verification**: 4:00 AM Sunday Sydney time - Integrity check of latest backup
- ✅ **Automatic Retention**: Last 5 backups kept (older backups auto-deleted)
- 📋 **Manual Backup**: Run anytime before major changes

### Active Cron Jobs
```bash
# Daily comprehensive backup at 3 AM Sydney time (17:00 UTC)
0 17 * * * /root/thermalog-infrastructure/scripts/backup.sh >> /root/thermalog-ops/logs/maintenance/backup.log 2>&1

# Weekly backup verification at 4 AM Sunday Sydney time (18:00 UTC Saturday)
0 18 * * 6 /root/thermalog-infrastructure/scripts/verify-latest-backup.sh >> /root/thermalog-ops/logs/maintenance/backup-verify.log 2>&1
```

**Note:** Server timezone is UTC, but cron jobs are scheduled for Sydney time (UTC+10/+11).

### Backup Locations
- **Main backups**: `/var/backups/thermalog/` (unencrypted, for fast local restoration)
- **Encrypted backups**: `/root/thermalog-infrastructure/backups/` (for off-site storage)
- **Logs**: `/root/thermalog-ops/logs/maintenance/backup.log`
- **Verification logs**: `/root/thermalog-ops/logs/maintenance/backup-verify.log`

### Manual Backup Commands
```bash
# Run daily backup manually
/root/thermalog-infrastructure/scripts/backup.sh

# Create encrypted backup for off-site storage
/root/thermalog-ops/scripts/backup/create-encrypted-backup.sh

# Verify latest backup
/root/thermalog-infrastructure/scripts/verify-latest-backup.sh
```

## Security Considerations

### Encryption
- Backups use AES-256-CBC encryption with OpenSSL
- Encryption key should be stored securely and separately from backups
- Consider using key management solutions for production

### Storage
- Store encrypted backups in secure, off-site locations
- Regular integrity checks to detect corruption
- Access control to backup storage locations
- Consider backup versioning and retention policies

### Sensitive Data
- Environment files contain sensitive credentials
- SSL private keys included in backups
- Database connection strings and API keys present
- Ensure backup storage has appropriate security measures

## Troubleshooting

### Common Issues

#### Decryption Fails
```bash
# Verify file integrity
file backup.tar.gz.enc

# Check if file is corrupted
ls -la backup.tar.gz.enc

# Verify encryption key
./extract-backup.sh -v backup.tar.gz.enc
```

#### Extraction Fails
```bash
# Check available disk space
df -h

# Verify tar archive integrity
tar -tzf decrypted_backup.tar.gz

# Check permissions
ls -la /tmp/
```

#### Service Startup Issues
```bash
# Check environment file syntax
cat /root/Thermalog-Backend/.env

# Verify Docker Compose syntax
docker compose config

# Check systemd service status
systemctl status thermalog-backend
journalctl -u thermalog-backend -f
```

### Recovery from Corruption

If backup archives are corrupted:
1. Try alternative backup files from different dates
2. Verify backup integrity before restoration
3. Use partial restoration for specific components
4. Rebuild from source repositories if necessary

## Backup File Locations

### Default Locations
- **Regular backups**: `/root/thermalog_server_backup_*.tar.gz`
- **Encrypted backups**: `/root/thermalog-infrastructure/backups/`
- **Extraction script**: `/root/thermalog-infrastructure/extract-backup.sh`
- **Backup logs**: `/root/backup.log`

### Archive Naming Convention
```
Regular: thermalog_server_backup_YYYYMMDD_HHMMSS.tar.gz
Encrypted: thermalog_server_backup_YYYYMMDD_HHMMSS_encrypted.tar.gz.enc
```

## Monitoring and Alerts

### Backup Monitoring
- Monitor backup script execution success/failure
- Alert on backup size anomalies
- Verify backup creation timestamps
- Monitor available storage space

### Integration with Uptime Kuma
- Add backup health checks to monitoring
- Set up alerts for backup failures
- Monitor backup storage location accessibility

## Best Practices

1. **Test restores regularly** - Verify backup integrity through test restorations
2. **Document changes** - Keep restoration notes for environment-specific modifications
3. **Secure key management** - Store encryption keys separately from backups
4. **Monitor backup sizes** - Detect issues through size anomalies
5. **Automate verification** - Regularly verify backup integrity automatically
6. **Retention policies** - Implement appropriate backup retention and rotation
7. **Off-site storage** - Store backups in geographically separate locations
8. **Access controls** - Limit backup access to authorized personnel only

## Support

For issues with the backup system:
1. Check backup logs in `/root/backup.log`
2. Verify system resources (disk space, memory)
3. Test backup extraction with verification mode
4. Review this documentation for troubleshooting steps
5. Contact system administrators for complex issues