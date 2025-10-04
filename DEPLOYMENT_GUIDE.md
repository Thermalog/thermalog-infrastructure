# 🚀 Thermalog Infrastructure - Master Deployment Guide

## Overview

The `deploy-everything.sh` script is a **one-click solution** that can:
- Set up a completely new server with all Thermalog infrastructure
- Detect and install missing components on existing servers  
- Update and verify existing installations

## Quick Start

### For New Servers
```bash
# 1. Install minimal prerequisites  
sudo apt update && sudo apt install -y git curl

# 2. Clone ONLY the infrastructure repository
git clone https://github.com/Thermalog/thermalog-infrastructure.git
cd thermalog-infrastructure

# 3. Run the master deployment script (clones other repos automatically)
sudo ./deploy-everything.sh
```

**Note**: You only need to clone the `thermalog-infrastructure` repository manually. The script automatically clones `Thermalog-Backend` and `Thermalog-frontend` for you!

### For Existing Servers (Missing Components)
```bash
# 1. Update the infrastructure repository
cd /root/thermalog-infrastructure
git pull origin main

# 2. Run the deployment script to fix missing components
sudo ./deploy-everything.sh
```

## What The Script Does

### 🔍 Server Detection
The script automatically detects:
- **New Server**: No existing Thermalog installation found
- **Missing Components**: Some automation scripts or services are missing
- **Fully Configured**: Everything is present, just needs verification

### 📦 Package Installation (New Servers Only)
Installs required system packages:
- Docker and Docker Compose plugin
- Certbot for SSL certificates
- Git, curl, python3
- Enables Docker and cron services

### 📋 Script Deployment
Copies all automation scripts to `/root/thermalog-ops/scripts/`:
- `deployment/auto-deploy.sh` - GitHub monitoring and deployment every 5 minutes
- `maintenance/docker-cleanup.sh` - Docker maintenance and cleanup
- `maintenance/ssl-renew-dual.sh` - Dual SSL certificate renewal via cron
- `deployment/startup-thermalog.sh` - Server restart verification and recovery
- `deployment/setup-auto-deploy.sh` - Auto-deployment configuration
- `backup/create-encrypted-backup.sh` - Encrypted backup creation
- `monitoring/uptime-kuma-alerts-improved.sh` - Enhanced monitoring alerts

### 🔧 Service Configuration
Sets up systemd services:
- `thermalog.service` - Main application stack (Backend, Frontend, Nginx)
- `thermalog-startup.service` - Boot-time verification and recovery
- `thermalog-shutdown.service` - Graceful shutdown handler
- `emqx-platform.service` - EMQX IoT platform (MQTT broker + PostgreSQL/TimescaleDB)

### ⏰ Automation Setup
Configures cron jobs (Sydney Time = UTC+10/11):
- **Every 5 minutes**: Auto-deployment from GitHub
- **Every 2 minutes**: Uptime Kuma monitoring alerts
- **Daily at 2 AM UTC**: Docker cleanup and maintenance
- **Every 12 hours**: Process cleanup
- **Twice daily (3:15 AM & 3:15 PM UTC)**: Dual SSL certificate renewal
- **Daily at 3 AM Sydney (17:00 UTC)**: Comprehensive backup
- **Weekly Sunday 4 AM Sydney (18:00 UTC Sat)**: Backup verification
- **After boot**: Startup verification and recovery

### 📁 Repository Management
- **Automatically clones** Thermalog-Backend and Thermalog-frontend to `/root/`
- Updates existing repositories if they already exist
- Creates basic docker-compose.yml if missing
- Verifies all required files are present

**Important**: You don't need to manually clone the application repositories - the script does this automatically!

## Usage Examples

### Example 1: Brand New Ubuntu Server
```bash
# Fresh Ubuntu 20.04/22.04 server - install prerequisites
sudo apt update && sudo apt install -y git curl

# Clone ONLY the infrastructure repo (script clones the rest)
git clone https://github.com/Thermalog/thermalog-infrastructure.git
cd thermalog-infrastructure
sudo ./deploy-everything.sh
```

**What happens:**
- Detects new server
- Installs Docker, certbot, and other packages  
- **Automatically clones** Thermalog-Backend and Thermalog-frontend repositories to `/root/`
- Sets up all automation scripts
- Configures systemd services
- Sets up cron jobs
- Starts all services

### Example 2: Server Missing Some Components
```bash
# Server has some Thermalog components but missing automation
cd /root/thermalog-infrastructure
git pull origin main
sudo ./deploy-everything.sh
```

**What happens:**
- Detects missing components
- Deploys missing scripts
- Updates systemd services
- Fixes cron jobs
- Verifies everything works

### Example 3: Fully Configured Server (Verification)
```bash
# Server appears complete, just verify and update
cd /root/thermalog-infrastructure
sudo ./deploy-everything.sh
```

**What happens:**
- Skips package installation
- Updates all scripts to latest versions
- Verifies systemd services
- Updates cron jobs
- Reports current status

## Script Options

### Interactive Confirmation
The script always asks for confirmation before making changes:
```
⚠️  WARNING: This script will modify system configuration
Do you want to proceed with the deployment? (y/N):
```

### Logging
All actions are logged to `/root/thermalog-deployment.log`:
```bash
# View deployment log
tail -f /root/thermalog-deployment.log

# Search for errors
grep -i error /root/thermalog-deployment.log
```

## Final Status Report

After deployment, the script shows:

### Service Status
```
System Services Status:
  ✓ Service active (docker)
  ✓ Service active (cron)  
  ✓ Service active (thermalog)
  ✓ Service active (thermalog-startup)
```

### Container Status
```
Docker Containers:
NAMES               STATUS              PORTS
thermalog-backend   Up 2 minutes        0.0.0.0:3001->3001/tcp
thermalog-frontend  Up 2 minutes        80/tcp
```

### Automation Status
```
Cron Jobs Configured:
  */5 * * * * /root/thermalog-ops/scripts/deployment/auto-deploy.sh >> /root/thermalog-ops/logs/deployment/auto-deploy-cron.log 2>&1
  */2 * * * * /root/thermalog-ops/scripts/monitoring/uptime-kuma-alerts-improved.sh >> /root/thermalog-ops/logs/monitoring/uptime-alerts.log 2>&1
  0 2 * * * /root/thermalog-ops/scripts/maintenance/docker-cleanup.sh >> /root/thermalog-ops/logs/maintenance/docker-cleanup-cron.log 2>&1
  0 */12 * * * /root/thermalog-ops/scripts/deployment/cleanup_processes.sh >> /root/thermalog-ops/logs/maintenance/process-cleanup-cron.log 2>&1
  15 3,15 * * * /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh >> /root/thermalog-ops/logs/maintenance/ssl-renewal.log 2>&1
  0 17 * * * /root/thermalog-infrastructure/scripts/backup.sh >> /root/thermalog-ops/logs/maintenance/backup.log 2>&1
  0 18 * * 6 /root/thermalog-infrastructure/scripts/verify-latest-backup.sh >> /root/thermalog-ops/logs/maintenance/backup-verify.log 2>&1
```

## Troubleshooting

### Script Fails with Permission Error
```bash
# Make sure you're running as root
sudo ./deploy-everything.sh
```

### Docker Installation Fails
```bash
# Check if Docker was partially installed
docker --version

# If needed, manually clean up and re-run
sudo apt remove docker docker-engine docker.io containerd runc
sudo ./deploy-everything.sh
```

### Services Don't Start
```bash
# Check service status
systemctl status thermalog thermalog-startup

# View service logs
journalctl -u thermalog.service -f
```

### Missing Application Code
```bash
# The script clones repositories automatically
# If they exist but are outdated, run:
cd /root/Thermalog-Backend && git pull origin main
cd /root/Thermalog-frontend && git pull origin main

# Then restart services
docker compose restart
```

## Security Notes

### Script Requirements
- **Must run as root** - Modifies system configuration, installs packages, creates services
- **Modifies system files** - Creates systemd services, cron jobs, installs packages
- **Network access required** - Downloads packages, clones repositories

### What Gets Modified
- `/etc/systemd/system/` - Service files
- Root crontab - Automation schedule  
- `/root/` - Application code and scripts
- System packages - Docker, certbot, etc.

## Manual Verification

After deployment, verify everything works:

```bash
# Check application health
curl http://localhost:3001/api/health

# Verify containers are running
docker ps

# Check automation is working
crontab -l

# Test manual deployment
/root/auto-deploy.sh

# Test startup recovery
/root/startup-thermalog.sh
```

## Success Indicators

✅ **Deployment Successful When:**
- All containers are running (`docker ps`)
- Health check returns successful (`curl http://localhost:3001/api/health`)
- Cron jobs are configured (`crontab -l`)
- Services are enabled (`systemctl is-enabled thermalog`)
- Log files show successful operations

## Next Steps

After successful deployment:

1. **Configure domain and SSL** - Set up your domain DNS to point to the server
2. **Set up environment files** - Configure `.env` files in Backend/Frontend
3. **Monitor automation** - Watch log files to ensure automation works
4. **Test server restart** - Reboot server and verify everything comes back up

Your server is now **fully automated** and **self-healing**! 🎉