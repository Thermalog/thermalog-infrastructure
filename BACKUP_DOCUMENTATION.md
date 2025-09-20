# Thermalog Server Backup & Recovery System

## Overview

The Thermalog server backup system provides comprehensive backup and recovery capabilities for all critical server configuration files, environment variables, SSL certificates, and operational data. The system supports both regular and encrypted backups.

## Backup Components

### What's Included
- **Configuration Scripts**: All shell scripts, YAML files, JSON configs from `/root/`
- **Environment Variables**: `.env` files from all repositories (backend, frontend, infrastructure)
- **Nginx Configuration**: Complete nginx setup including SSL certificates
- **Systemd Services**: Service definitions for Thermalog components
- **SSL Certificates**: All SSL/TLS certificates and keys
- **Docker Volumes**: Uptime Kuma data and other persistent volumes
- **System Information**: Current system status, containers, resource usage
- **Network Configuration**: Host files, routing tables
- **Monitoring Scripts**: All monitoring and alerting infrastructure
- **Docker Configuration**: Docker daemon and compose configurations
- **Crontab**: Scheduled tasks and automation
- **Log Files**: Recent entries from critical log files (last 1000 lines)

### What's Excluded
- Source code repositories (can be cloned from Git)
- Large log files (only recent entries included)
- Temporary files and caches
- Git repositories (`.git` directories)

## Backup Scripts

### Regular Backup: `create-server-backup.sh`
Creates unencrypted compressed archive suitable for local storage or secure environments.

```bash
# Run backup
./create-server-backup.sh

# Output location
/root/thermalog_server_backup_YYYYMMDD_HHMMSS.tar.gz
```

### Encrypted Backup: `create-encrypted-backup.sh`
Creates AES-256-CBC encrypted archive for secure storage and transmission.

```bash
# Run encrypted backup
./create-encrypted-backup.sh

# Output location
/root/thermalog-infrastructure/backups/thermalog_server_backup_YYYYMMDD_HHMMSS_encrypted.tar.gz.enc
```

**Encryption Details:**
- Algorithm: AES-256-CBC with salt
- Key: `ThermalogDigital!@#$`
- Tool: OpenSSL

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

#### 6. Restore Docker Volumes
```bash
# For Uptime Kuma data
docker volume create uptime-kuma-data
docker run --rm -v uptime-kuma-data:/data -v $(pwd)/docker-volumes:/backup alpine tar xzf /backup/uptime-kuma-data.tar.gz -C /data
```

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

### Recommended Schedule
- **Daily encrypted backups** for production environments
- **Weekly verification** of backup integrity
- **Monthly backup rotation** (keep 12 monthly backups)
- **Immediate backup** before major changes

### Automation Setup
```bash
# Add to crontab for daily 2 AM backup
0 2 * * * /root/create-encrypted-backup.sh >> /root/backup.log 2>&1

# Weekly verification at 3 AM Sunday
0 3 * * 0 /root/thermalog-infrastructure/extract-backup.sh -v $(ls -t /root/thermalog-infrastructure/backups/*.enc | head -1) >> /root/backup-verify.log 2>&1
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