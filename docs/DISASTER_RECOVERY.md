# Disaster Recovery Guide

Complete procedures for recovering the Thermalog production server from catastrophic failure.

## Overview

This guide provides step-by-step procedures for:
- **Complete server rebuild** from scratch
- **Backup restoration** (data, configurations, certificates)
- **Database recovery** (main application + IoT platform)
- **Service verification** and testing
- **Rollback procedures** if recovery fails

### When to Use This Guide

- **Server hardware failure** requiring new server
- **Data corruption** requiring restoration from backup
- **Security incident** requiring clean rebuild
- **Migration** to new hosting provider
- **Testing** disaster recovery procedures (recommended quarterly)

## Prerequisites

### Required Access
- Root access to new/replacement server
- GitHub repository access (all 5 repositories)
- DNS management access (for domain verification)
- Backup files (latest from `/var/backups/thermalog/`)
- Database credentials (main application external database)
- Email/communication credentials (SendGrid API key)

### Required Information
- Domain name: `dashboard.thermalog.com.au`
- Server IP address (for DNS configuration)
- External PostgreSQL database connection string
- All environment variable values
- SSL certificate contact email

### Recommended
- Encrypted off-site backup (if available)
- Documentation of custom configurations
- List of registered IoT devices
- Recent system state documentation

## Recovery Scenarios

### Scenario 1: Complete Server Rebuild (New Hardware)

**Situation**: Server hardware failed, deploying to completely new server.

**Recovery Path**:
1. [Server Setup](#phase-1-server-setup) (fresh OS installation)
2. [Deploy Infrastructure](#phase-2-infrastructure-deployment)
3. [Restore from Backup](#phase-3-backup-restoration)
4. [Verify All Services](#phase-4-service-verification)

**Estimated Time**: 2-4 hours
**Data Loss**: Since last backup (typically <24 hours)

### Scenario 2: Data Corruption (Server Still Accessible)

**Situation**: Application data corrupted but server is functional.

**Recovery Path**:
1. Stop affected services
2. [Restore from Backup](#phase-3-backup-restoration) (selective restoration)
3. [Verify Services](#phase-4-service-verification)

**Estimated Time**: 30 minutes - 1 hour
**Data Loss**: Since last backup (typically <24 hours)

### Scenario 3: Configuration Loss (Applications Running)

**Situation**: Configuration files lost/corrupted, applications need reconfiguration.

**Recovery Path**:
1. [Restore Configuration](#restore-configuration-files)
2. [Restore SSL Certificates](#restore-ssl-certificates)
3. Restart affected services

**Estimated Time**: 15-30 minutes
**Data Loss**: None (data intact)

## Phase 1: Server Setup

### 1.1 Fresh Ubuntu Installation

```bash
# Ensure server is running Ubuntu 20.04 or 22.04 LTS
lsb_release -a

# Update system packages
sudo apt update && sudo apt upgrade -y

# Set timezone to Sydney
sudo timedatectl set-timezone Australia/Sydney

# Verify time
date
```

### 1.2 Install Required Software

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo apt install docker-compose-plugin -y

# Verify Docker installation
docker --version
docker compose version

# Install Certbot for SSL
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot

# Install essential tools
sudo apt install -y git curl wget htop net-tools ufw jq
```

### 1.3 Configure Firewall

```bash
# Configure UFW firewall
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 8883/tcp  # MQTTS

# Enable firewall
sudo ufw --force enable

# Verify
sudo ufw status
```

### 1.4 Update DNS Configuration

**CRITICAL**: Before proceeding with SSL, ensure DNS is configured.

```bash
# Verify DNS propagation (from external machine or online tool)
nslookup dashboard.thermalog.com.au

# Should return your new server IP
# Wait for full propagation if needed (up to 24 hours)
```

## Phase 2: Infrastructure Deployment

### 2.1 Clone All Repositories

```bash
cd /root

# Clone infrastructure repository (contains deployment scripts)
git clone https://github.com/Thermalog/thermalog-infrastructure.git

# Clone operational scripts repository
git clone https://github.com/Thermalog/thermalog-ops.git

# Clone application repositories
git clone https://github.com/Thermalog/Thermalog-Backend.git
git clone https://github.com/Thermalog/Thermalog-frontend.git

# Clone EMQX IoT platform
git clone https://github.com/Thermalog/emqx-platform.git

# Verify all repositories
ls -la /root/ | grep -E "thermalog|emqx"
```

### 2.2 Create Directory Structure

```bash
# Create organizational directories
mkdir -p /root/Documentation
mkdir -p /root/Scripts
mkdir -p /root/Config
mkdir -p /root/Config/nginx

# Create backup directories
mkdir -p /var/backups/thermalog

# Create log directories
mkdir -p /root/thermalog-ops/logs/deployment
mkdir -p /root/thermalog-ops/logs/maintenance
mkdir -p /root/thermalog-ops/logs/monitoring

# Set permissions
chmod 755 /root/Documentation /root/Scripts /root/Config
chmod 700 /var/backups/thermalog
```

### 2.3 Generate Dual SSL Certificates

```bash
# IMPORTANT: Ensure nginx is not running (port 80 must be free)
docker ps | grep nginx && docker stop nginx

# Generate ECDSA certificate (modern browsers)
certbot certonly --standalone \
  -d dashboard.thermalog.com.au \
  --key-type ecdsa \
  --elliptic-curve secp384r1 \
  --non-interactive \
  --agree-tos \
  --email admin@thermalog.com.au

# Generate RSA certificate (legacy compatibility)
certbot certonly --standalone \
  -d dashboard.thermalog.com.au \
  --cert-name dashboard.thermalog.com.au-rsa \
  --key-type rsa \
  --rsa-key-size 4096 \
  --non-interactive \
  --agree-tos \
  --email admin@thermalog.com.au

# Deploy certificates to nginx directory
cp /etc/letsencrypt/live/dashboard.thermalog.com.au/fullchain.pem /root/Config/nginx/fullchain-ecdsa.pem
cp /etc/letsencrypt/live/dashboard.thermalog.com.au/privkey.pem /root/Config/nginx/privkey-ecdsa.pem
cp /etc/letsencrypt/live/dashboard.thermalog.com.au-rsa/fullchain.pem /root/Config/nginx/fullchain-rsa.pem
cp /etc/letsencrypt/live/dashboard.thermalog.com.au-rsa/privkey.pem /root/Config/nginx/privkey-rsa.pem

# Set proper permissions
chmod 644 /root/Config/nginx/fullchain-*.pem
chmod 600 /root/Config/nginx/privkey-*.pem

# Verify both certificates
certbot certificates
```

### 2.4 Configure Environment Files

Create environment files for all repositories:

**Backend** (`/root/Thermalog-Backend/.env`):
```bash
# Database connection (external PostgreSQL)
DATABASE_URL="postgresql://username:password@host:port/database?schema=public"

# Application settings
NODE_ENV=production
PORT=3001

# CORS settings
ALLOWED_ORIGIN=https://dashboard.thermalog.com.au

# Security
JWT_SECRET=your_jwt_secret_here

# Email notifications (SendGrid)
SENDGRID_API_KEY=your_sendgrid_api_key
EMAIL_FROM=noreply@thermalog.com.au
```

**Frontend** (`/root/Thermalog-frontend/.env`):
```bash
REACT_APP_API_URL=https://dashboard.thermalog.com.au/api
REACT_APP_WEB_SOCKET_URL=wss://dashboard.thermalog.com.au
```

**Infrastructure** (`/root/thermalog-infrastructure/.env`):
```bash
DOMAIN=dashboard.thermalog.com.au
ADMIN_EMAIL=admin@thermalog.com.au
```

**EMQX Platform** (`/root/emqx-platform/.env`):
```bash
# IoT PostgreSQL Database
POSTGRES_USER=iotadmin
POSTGRES_PASSWORD=your_secure_password_here
POSTGRES_DB=iot_platform

# EMQX Dashboard
EMQX_DASHBOARD_USERNAME=admin
EMQX_DASHBOARD_PASSWORD=your_emqx_admin_password

# Provisioning Service
DATABASE_URL=postgresql://iotadmin:your_secure_password_here@iot-postgres:5432/iot_platform
```

**Set Permissions**:
```bash
chmod 600 /root/Thermalog-Backend/.env
chmod 600 /root/Thermalog-frontend/.env
chmod 600 /root/thermalog-infrastructure/.env
chmod 600 /root/emqx-platform/.env
```

### 2.5 Deploy Systemd Services

```bash
# Copy service files from thermalog-ops repository
cp /root/thermalog-ops/systemd/thermalog.service /etc/systemd/system/
cp /root/thermalog-ops/systemd/thermalog-startup.service /etc/systemd/system/
cp /root/thermalog-ops/systemd/thermalog-shutdown.service /etc/systemd/system/
cp /root/thermalog-ops/systemd/emqx-platform.service /etc/systemd/system/

# Reload systemd
systemctl daemon-reload

# Enable services (auto-start on boot)
systemctl enable docker.service
systemctl enable cron.service
systemctl enable thermalog.service
systemctl enable thermalog-startup.service
systemctl enable thermalog-shutdown.service
systemctl enable emqx-platform.service

# Verify services are enabled
systemctl list-unit-files | grep -E "thermalog|emqx|docker|cron"
```

### 2.6 Configure Cron Jobs

```bash
# Edit root crontab
crontab -e

# Add the following cron jobs:
```

```cron
# Auto-deployment check every 5 minutes
*/5 * * * * /root/thermalog-ops/scripts/deployment/auto-deploy.sh >> /root/thermalog-ops/logs/deployment/auto-deploy-cron.log 2>&1

# Monitoring alerts every 2 minutes
*/2 * * * * /root/thermalog-ops/scripts/monitoring/uptime-kuma-alerts-improved.sh >> /root/thermalog-ops/logs/monitoring/uptime-alerts.log 2>&1

# Docker cleanup daily at 2 AM UTC
0 2 * * * /root/thermalog-ops/scripts/maintenance/docker-cleanup.sh >> /root/thermalog-ops/logs/maintenance/docker-cleanup-cron.log 2>&1

# Process cleanup every 12 hours
0 */12 * * * /root/thermalog-ops/scripts/deployment/cleanup_processes.sh >> /root/thermalog-ops/logs/maintenance/process-cleanup-cron.log 2>&1

# Dual SSL renewal twice daily
15 3,15 * * * /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh >> /root/thermalog-ops/logs/maintenance/ssl-renewal.log 2>&1

# Daily backup at 3 AM Sydney time (17:00 UTC)
0 17 * * * /root/thermalog-infrastructure/scripts/backup.sh >> /root/thermalog-ops/logs/maintenance/backup.log 2>&1

# Weekly backup verification Sunday 4 AM Sydney (18:00 UTC Saturday)
0 18 * * 6 /root/thermalog-infrastructure/scripts/verify-latest-backup.sh >> /root/thermalog-ops/logs/maintenance/backup-verify.log 2>&1
```

```bash
# Verify cron jobs
crontab -l
```

### 2.7 Start EMQX IoT Platform

```bash
# Start EMQX platform first (required for main app)
systemctl start emqx-platform.service

# Wait for services to initialize
sleep 30

# Verify EMQX platform status
systemctl status emqx-platform.service

# Check containers
docker ps | grep -E "emqx|iot-postgres|provisioning"

# Verify EMQX broker
docker exec emqx emqx ctl status

# Verify PostgreSQL
docker exec iot-postgres pg_isready -U iotadmin
```

### 2.8 Start Main Application Stack

```bash
# Start main application stack
systemctl start thermalog.service

# Wait for services to start
sleep 30

# Verify service status
systemctl status thermalog.service

# Check all containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Expected containers:
# - thermalog-backend
# - thermalog-frontend
# - nginx
# - uptime-kuma
# - emqx
# - iot-postgres
# - provisioning-service
```

## Phase 3: Backup Restoration

### 3.1 Locate Latest Backup

**If server is still accessible**:
```bash
# On old server, find latest backup
ls -lh /var/backups/thermalog/ | tail -5

# Copy to new server
scp /var/backups/thermalog/thermalog_backup_YYYYMMDD_HHMMSS.tar.gz root@NEW_SERVER_IP:/root/
```

**If using encrypted off-site backup**:
```bash
# Download encrypted backup
# Decrypt backup
openssl enc -d -aes-256-cbc -in backup.tar.gz.enc -out backup.tar.gz

# Move to restoration location
mv backup.tar.gz /root/
```

### 3.2 Extract Backup

```bash
cd /root

# Extract backup
tar -xzf thermalog_backup_YYYYMMDD_HHMMSS.tar.gz

# Navigate to extracted directory
cd thermalog_backup_YYYYMMDD_HHMMSS

# View contents
ls -la
```

### 3.3 Restore PostgreSQL Database (IoT Platform)

```bash
# Stop EMQX platform to avoid conflicts
systemctl stop emqx-platform.service

# Wait for clean shutdown
sleep 10

# Restore IoT database from backup
docker exec -i iot-postgres psql -U iotadmin -d iot_platform < database_dumps/iot_platform.sql

# If database doesn't exist, create it first:
docker exec -i iot-postgres psql -U iotadmin -c "CREATE DATABASE iot_platform;"
docker exec -i iot-postgres psql -U iotadmin -d iot_platform < database_dumps/iot_platform.sql

# Verify restoration
docker exec -i iot-postgres psql -U iotadmin -d iot_platform -c "\dt"
docker exec -i iot-postgres psql -U iotadmin -d iot_platform -c "SELECT COUNT(*) FROM device_credentials;"

# Restart EMQX platform
systemctl start emqx-platform.service
```

### 3.4 Restore Docker Volumes

```bash
# Stop services to restore volumes safely
systemctl stop thermalog.service
systemctl stop emqx-platform.service

# Restore Uptime Kuma data
docker run --rm -v thermalog_uptime-kuma-data:/data -v $(pwd):/backup alpine \
  sh -c "cd /data && tar -xzf /backup/volumes/uptime-kuma-data.tar.gz --strip-components=1"

# Restore EMQX data
docker run --rm -v emqx-platform_emqx-data:/data -v $(pwd):/backup alpine \
  sh -c "cd /data && tar -xzf /backup/volumes/emqx-data.tar.gz --strip-components=1"

# Restore EMQX logs
docker run --rm -v emqx-platform_emqx-log:/data -v $(pwd):/backup alpine \
  sh -c "cd /data && tar -xzf /backup/volumes/emqx-log.tar.gz --strip-components=1"

# Restore PostgreSQL data
docker run --rm -v emqx-platform_postgres-data:/data -v $(pwd):/backup alpine \
  sh -c "cd /data && tar -xzf /backup/volumes/postgres-data.tar.gz --strip-components=1"

# Verify volumes
docker volume ls
```

### 3.5 Restore SSL Certificates

```bash
# Restore to Let's Encrypt directories
mkdir -p /etc/letsencrypt/live/dashboard.thermalog.com.au
mkdir -p /etc/letsencrypt/live/dashboard.thermalog.com.au-rsa

# Restore ECDSA certificate
cp ssl_certificates/ecdsa/fullchain.pem /etc/letsencrypt/live/dashboard.thermalog.com.au/
cp ssl_certificates/ecdsa/privkey.pem /etc/letsencrypt/live/dashboard.thermalog.com.au/

# Restore RSA certificate
cp ssl_certificates/rsa/fullchain.pem /etc/letsencrypt/live/dashboard.thermalog.com.au-rsa/
cp ssl_certificates/rsa/privkey.pem /etc/letsencrypt/live/dashboard.thermalog.com.au-rsa/

# Deploy to nginx directory
cp ssl_certificates/ecdsa/fullchain.pem /root/Config/nginx/fullchain-ecdsa.pem
cp ssl_certificates/ecdsa/privkey.pem /root/Config/nginx/privkey-ecdsa.pem
cp ssl_certificates/rsa/fullchain.pem /root/Config/nginx/fullchain-rsa.pem
cp ssl_certificates/rsa/privkey.pem /root/Config/nginx/privkey-rsa.pem

# Set proper permissions
chmod 644 /root/Config/nginx/fullchain-*.pem
chmod 600 /root/Config/nginx/privkey-*.pem
chmod 644 /etc/letsencrypt/live/*/fullchain.pem
chmod 600 /etc/letsencrypt/live/*/privkey.pem

# Verify certificates
openssl x509 -in /root/Config/nginx/fullchain-ecdsa.pem -noout -enddate
openssl x509 -in /root/Config/nginx/fullchain-rsa.pem -noout -enddate
```

### 3.6 Restore Configuration Files

```bash
# Restore environment files
cp environment_files/backend.env /root/Thermalog-Backend/.env
cp environment_files/frontend.env /root/Thermalog-frontend/.env
cp environment_files/infrastructure.env /root/thermalog-infrastructure/.env
cp environment_files/emqx.env /root/emqx-platform/.env

# Set proper permissions
chmod 600 /root/Thermalog-Backend/.env
chmod 600 /root/Thermalog-frontend/.env
chmod 600 /root/thermalog-infrastructure/.env
chmod 600 /root/emqx-platform/.env

# Restore nginx configuration (if customized)
# Note: Usually nginx config comes from repository, only restore if custom changes exist
# cp nginx_config/default.conf /root/Config/nginx/

# Restore systemd services (already done in Phase 2.5, but verify)
diff systemd_services/thermalog.service /etc/systemd/system/thermalog.service
```

### 3.7 Restart All Services

```bash
# Reload systemd (in case service files were updated)
systemctl daemon-reload

# Start EMQX platform first
systemctl start emqx-platform.service
sleep 30

# Start main application stack
systemctl start thermalog.service
sleep 30

# Verify all services are running
systemctl status thermalog.service
systemctl status emqx-platform.service
systemctl status docker.service
systemctl status cron.service
```

## Phase 4: Service Verification

### 4.1 Verify Docker Containers

```bash
# Check all containers are running
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Expected output: 7 containers, all "Up"
# - thermalog-backend (Up)
# - thermalog-frontend (Up)
# - nginx (Up)
# - uptime-kuma (Up)
# - emqx (Up)
# - iot-postgres (Up)
# - provisioning-service (Up)

# Check for any errors in logs
docker logs thermalog-backend --tail=50
docker logs nginx --tail=50
docker logs emqx --tail=50
```

### 4.2 Verify SSL/HTTPS

```bash
# Test HTTPS connectivity
curl -I https://dashboard.thermalog.com.au

# Expected: HTTP/2 200

# Verify dual certificates
openssl s_client -connect dashboard.thermalog.com.au:443 -servername dashboard.thermalog.com.au < /dev/null 2>/dev/null | openssl x509 -noout -text | grep "Public Key Algorithm"

# Test certificate expiry
openssl x509 -in /root/Config/nginx/fullchain-ecdsa.pem -noout -enddate
openssl x509 -in /root/Config/nginx/fullchain-rsa.pem -noout -enddate
```

### 4.3 Verify Backend API

```bash
# Test backend health endpoint
curl https://dashboard.thermalog.com.au/api/health

# Expected: {"status": "ok"} or similar

# Check backend logs for errors
docker logs thermalog-backend --tail=100 | grep -i error
```

### 4.4 Verify EMQX Platform

```bash
# Check EMQX status
docker exec emqx emqx ctl status

# Expected: Node is running

# Check IoT database
docker exec -i iot-postgres psql -U iotadmin -d iot_platform -c "SELECT COUNT(*) FROM device_credentials;"

# Test EMQX dashboard access
curl http://localhost:18083/api/v5/status

# Test MQTT connection (requires mosquitto-clients)
# apt install mosquitto-clients -y
mosquitto_pub -h localhost -p 1883 -t test -m "hello"
```

### 4.5 Verify Uptime Kuma

```bash
# Access Uptime Kuma dashboard
curl -I https://dashboard.thermalog.com.au/monitoring/

# Expected: HTTP/2 200

# Check all monitors are configured
# Manual verification required: visit https://dashboard.thermalog.com.au/monitoring/
```

### 4.6 Verify Cron Jobs

```bash
# List cron jobs
crontab -l

# Check recent cron executions
grep CRON /var/log/syslog | tail -20

# Manually trigger auto-deployment to test
/root/thermalog-ops/scripts/deployment/auto-deploy.sh

# Check deployment log
tail -20 /root/thermalog-ops/logs/deployment/auto-deploy-cron.log
```

### 4.7 Verify Monitoring Alerts

```bash
# Manually trigger monitoring script
/root/thermalog-ops/scripts/monitoring/uptime-kuma-alerts-improved.sh

# Check alert logs
tail -20 /root/thermalog-ops/logs/monitoring/uptime-alerts.log

# Verify SendGrid integration (check for email delivery)
```

### 4.8 End-to-End Testing

**Frontend Access**:
1. Navigate to `https://dashboard.thermalog.com.au`
2. Verify page loads without SSL warnings
3. Test user authentication
4. Verify dashboard displays data

**Backend API**:
1. Test API endpoints via frontend
2. Verify database connectivity
3. Check WebSocket connections

**IoT Platform**:
1. Test device authentication
2. Verify MQTT message publishing
3. Check temperature data storage
4. Confirm provisioning service API

## Phase 5: Post-Recovery Cleanup

### 5.1 Verify Backup System

```bash
# Run manual backup to ensure backup system works
/root/thermalog-infrastructure/scripts/backup.sh

# Verify backup was created
ls -lh /var/backups/thermalog/ | tail -1

# Test backup verification script
/root/thermalog-infrastructure/scripts/verify-latest-backup.sh
```

### 5.2 Security Audit

```bash
# Check file permissions
ls -la /root/Thermalog-Backend/.env
ls -la /root/Config/nginx/*.pem

# Verify firewall
sudo ufw status

# Check for exposed ports
netstat -tulpn | grep LISTEN

# Review Docker security
docker ps --format "{{.Names}}" | xargs -I {} docker inspect {} | grep -i "Privileged"
```

### 5.3 Document Recovery

```bash
# Create recovery report
cat > /root/recovery_report_$(date +%Y%m%d_%H%M%S).txt <<EOF
Thermalog Disaster Recovery Report
==================================
Date: $(date)
Backup Used: [backup filename]
Recovery Time: [X hours]
Services Restored: All services operational
Data Loss: [estimated data loss period]
Issues Encountered: [any issues and resolutions]

Service Status:
$(systemctl status thermalog.service | grep Active)
$(systemctl status emqx-platform.service | grep Active)

Container Status:
$(docker ps --format "table {{.Names}}\t{{.Status}}")

Verification Results:
- HTTPS: [Pass/Fail]
- Backend API: [Pass/Fail]
- EMQX Platform: [Pass/Fail]
- Monitoring: [Pass/Fail]
- Backups: [Pass/Fail]

Notes:
[Any additional notes]
EOF

# Review report
cat /root/recovery_report_*.txt
```

## Rollback Procedures

### If Recovery Fails

**Option 1: Retry from Different Backup**
```bash
# Stop all services
systemctl stop thermalog.service
systemctl stop emqx-platform.service

# Use previous backup
cd /root
tar -xzf thermalog_backup_[PREVIOUS_DATE].tar.gz

# Repeat Phase 3 restoration steps
```

**Option 2: Fresh Deployment (No Backup Restoration)**
```bash
# If backups are corrupted, deploy fresh
# WARNING: This loses all data

# Keep services running from Phase 2 deployment
# Manually reconfigure:
# - Uptime Kuma monitors
# - IoT device credentials
# - User accounts (if stored locally)
```

**Option 3: Revert to Old Server**
```bash
# If old server is still accessible
# Update DNS to point back to old server IP
# Allow 24h for DNS propagation
# Investigate issues before next recovery attempt
```

### Common Recovery Failures

**SSL Certificate Issues**:
```bash
# If certificates fail validation
# Re-generate fresh certificates
docker stop nginx
certbot delete --cert-name dashboard.thermalog.com.au
certbot delete --cert-name dashboard.thermalog.com.au-rsa

# Follow Phase 2.3 to regenerate
```

**Database Connection Failures**:
```bash
# Verify external database is accessible
docker exec thermalog-backend ping -c 3 [DATABASE_HOST]

# Test database credentials
docker exec thermalog-backend npx prisma db pull

# Check environment variables
docker exec thermalog-backend env | grep DATABASE_URL
```

**Container Start Failures**:
```bash
# Check Docker logs
docker logs [container_name] --tail=100

# Rebuild containers if needed
cd /root/thermalog-ops
docker compose -f config/docker-compose.yml up -d --build --force-recreate
```

## Recovery Time Objectives

### RTO (Recovery Time Objective)

| Scenario | Target RTO | Achievable With |
|----------|------------|-----------------|
| Complete server rebuild | 4 hours | This guide + daily backup |
| Data corruption recovery | 1 hour | Daily backup + running server |
| Configuration restoration | 30 minutes | Daily backup |
| Service restart | 10 minutes | Systemd automation |

### RPO (Recovery Point Objective)

| Data Type | Target RPO | Backup Frequency |
|-----------|------------|------------------|
| IoT temperature data | 24 hours | Daily backup |
| Device credentials | 24 hours | Daily backup |
| User data | Depends on external DB | External DB backup schedule |
| Configuration | 24 hours | Daily backup |
| SSL certificates | 90 days | Let's Encrypt validity |

## Testing Disaster Recovery

### Recommended Testing Schedule

**Quarterly** (Every 3 months):
```bash
# Test backup restoration in staging environment
# Verify backup integrity
/root/thermalog-infrastructure/scripts/verify-latest-backup.sh

# Document any issues
```

**Annually**:
```bash
# Full disaster recovery drill
# Deploy to test server using this guide
# Measure actual RTO
# Update documentation based on findings
```

## Additional Resources

- [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md) - Complete system architecture
- [BACKUP_DOCUMENTATION.md](BACKUP_DOCUMENTATION.md) - Backup procedures
- [DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md) - Deployment reference
- [troubleshooting.md](troubleshooting.md) - Troubleshooting guide
- [EMQX_PLATFORM.md](EMQX_PLATFORM.md) - EMQX IoT platform details
- [DUAL_SSL_CERTIFICATES.md](DUAL_SSL_CERTIFICATES.md) - SSL certificate system

## Emergency Contacts

**Critical Information Checklist**:
- [ ] GitHub access credentials
- [ ] Server root password/SSH keys
- [ ] Database connection strings
- [ ] SendGrid API key
- [ ] DNS management access
- [ ] SSL certificate contact email
- [ ] Latest backup location
- [ ] External database backup access

---

**Last Updated**: October 2025
**Document Version**: 1.0
**Tested**: [Add last test date]

For updates and improvements to this guide, submit pull requests to the thermalog-infrastructure repository.
