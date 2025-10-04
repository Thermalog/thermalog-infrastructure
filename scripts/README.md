# Thermalog Infrastructure Scripts

This directory contains deployment, backup, and reference scripts for the Thermalog production server.

## Purpose

The `thermalog-infrastructure` repository serves as a **deployment guide and reference repository**. Scripts in this directory fall into three categories:

1. **Active Infrastructure Scripts** - Run by cron or systemd, specific to this repository
2. **Deployment Scripts** - Used during initial server setup
3. **Reference Scripts** - Examples/documentation (active versions live in `/root/thermalog-ops/scripts/`)

## Script Inventory

### Active Infrastructure Scripts

These scripts are **actively used** and run from this repository:

| Script | Purpose | Execution | Location |
|--------|---------|-----------|----------|
| `backup.sh` | Daily unencrypted server backup | Cron: `0 17 * * *` (3 AM Sydney) | This repo |
| `verify-latest-backup.sh` | Weekly backup verification | Cron: `0 18 * * 6` (4 AM Sunday Sydney) | This repo |

**Why in this repo?**
- These scripts are infrastructure-level (backup/verification)
- They backup multiple repositories and system components
- Logically belong with infrastructure documentation

### Deployment Scripts

These scripts are used **during initial server setup**:

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `setup-server.sh` | Initial server configuration | New server deployment |
| `deploy.sh` | Deploy application stack | Manual deployment |
| `setup-auto-deploy.sh` | Configure auto-deployment | Initial setup |
| `install-ssl-hooks.sh` | Install SSL renewal hooks | Initial SSL setup |
| `ssl-hooks/` | SSL renewal hook scripts | Used by install-ssl-hooks.sh |

**Usage:**
```bash
# On fresh server
cd /root/thermalog-infrastructure
./scripts/setup-server.sh

# Deploy application
./scripts/deploy.sh
```

### Reference Scripts

These scripts exist here for **reference and documentation**. Active versions run from `/root/thermalog-ops/scripts/`:

| Script | Active Location | Purpose |
|--------|-----------------|---------|
| `auto-deploy.sh` | `/root/thermalog-ops/scripts/deployment/` | Auto-deployment from GitHub |
| `docker-cleanup.sh` | `/root/thermalog-ops/scripts/maintenance/` | Docker image/container cleanup |
| `startup-thermalog.sh` | `/root/thermalog-ops/scripts/deployment/` | Application startup procedures |
| `uptime-kuma-alerts-improved.sh` | `/root/thermalog-ops/scripts/monitoring/` | SendGrid email alerts |
| `uptime-kuma-alerts.sh` | `/root/thermalog-ops/scripts/monitoring/` | Basic monitoring alerts |

**Why reference copies?**
- Historical documentation
- Deployment examples for new servers
- Version comparison during troubleshooting
- May be needed if thermalog-ops is unavailable

### Deprecated Scripts

| Script | Status | Replacement |
|--------|--------|-------------|
| `ssl-renew.sh` | ⚠️ **Deprecated** | `/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh` |

**Reason:** `ssl-renew.sh` handles only single SSL certificates. The system now uses **dual SSL certificates** (ECDSA + RSA) managed by `ssl-renew-dual.sh`.

**Do not use** `ssl-renew.sh` in production. See [DUAL_SSL_CERTIFICATES.md](../docs/DUAL_SSL_CERTIFICATES.md).

## Script Organization Comparison

### This Repository (`/root/thermalog-infrastructure/scripts/`)
```
thermalog-infrastructure/scripts/
├── backup.sh                          # ACTIVE: Daily backups
├── verify-latest-backup.sh            # ACTIVE: Backup verification
├── setup-server.sh                    # DEPLOYMENT: Initial setup
├── deploy.sh                          # DEPLOYMENT: Manual deploy
├── setup-auto-deploy.sh               # DEPLOYMENT: Auto-deploy setup
├── install-ssl-hooks.sh               # DEPLOYMENT: SSL hooks
├── ssl-hooks/                         # DEPLOYMENT: Renewal hooks
├── auto-deploy.sh                     # REFERENCE
├── docker-cleanup.sh                  # REFERENCE
├── startup-thermalog.sh               # REFERENCE
├── uptime-kuma-alerts-improved.sh     # REFERENCE
├── uptime-kuma-alerts.sh              # REFERENCE
└── ssl-renew.sh                       # DEPRECATED
```

### Thermalog-Ops Repository (`/root/thermalog-ops/scripts/`)
```
thermalog-ops/scripts/
├── deployment/
│   ├── auto-deploy.sh                 # ACTIVE: Cron every 5 min
│   ├── cleanup_processes.sh           # ACTIVE: Cron every 12h
│   ├── setup-auto-deploy.sh           # Setup script
│   ├── startup-thermalog.sh           # ACTIVE: Systemd startup
│   └── shutdown-thermalog.sh          # ACTIVE: Systemd shutdown
├── maintenance/
│   ├── docker-cleanup.sh              # ACTIVE: Cron daily 2 AM UTC
│   └── ssl-renew-dual.sh              # ACTIVE: Cron twice daily
├── monitoring/
│   ├── uptime-kuma-alerts-improved.sh # ACTIVE: Cron every 2 min
│   ├── uptime-kuma-alerts.sh          # Backup monitoring
│   └── configure-monitors.sh          # Uptime Kuma setup
├── backup/
│   ├── create-encrypted-backup.sh     # Manual encrypted backups
│   └── create-server-backup.sh        # Backup utilities
└── security/
    └── load-secrets.sh                # Secrets management
```

## Cron Job Mapping

Current cron jobs and which repository they execute from:

| Schedule | Script | Repository | Purpose |
|----------|--------|------------|---------|
| `*/5 * * * *` | `auto-deploy.sh` | thermalog-ops | Auto-deployment |
| `*/2 * * * *` | `uptime-kuma-alerts-improved.sh` | thermalog-ops | Monitoring alerts |
| `0 2 * * *` | `docker-cleanup.sh` | thermalog-ops | Docker maintenance |
| `0 */12 * * *` | `cleanup_processes.sh` | thermalog-ops | Process cleanup |
| `15 3,15 * * *` | `ssl-renew-dual.sh` | thermalog-ops | Dual SSL renewal |
| `0 17 * * *` | `backup.sh` | **thermalog-infrastructure** | Daily backup |
| `0 18 * * 6` | `verify-latest-backup.sh` | **thermalog-infrastructure** | Backup verify |

View active cron jobs:
```bash
crontab -l
```

## Usage Guidelines

### During New Server Deployment

1. **Clone this repository first**:
   ```bash
   git clone https://github.com/Thermalog/thermalog-infrastructure.git
   cd thermalog-infrastructure
   ```

2. **Run deployment scripts**:
   ```bash
   # Initial server setup
   ./scripts/setup-server.sh

   # Deploy application
   ./scripts/deploy.sh
   ```

3. **Configure automation** (sets up cron jobs):
   ```bash
   ./scripts/setup-auto-deploy.sh
   ```

### For Daily Operations

**Use scripts from `/root/thermalog-ops/scripts/`**:
```bash
# Deployment operations
/root/thermalog-ops/scripts/deployment/auto-deploy.sh

# Maintenance
/root/thermalog-ops/scripts/maintenance/docker-cleanup.sh
/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh

# Monitoring
/root/thermalog-ops/scripts/monitoring/uptime-kuma-alerts-improved.sh
```

**Exception - Backup operations** (use infrastructure scripts):
```bash
# Daily backups (automated via cron)
/root/thermalog-infrastructure/scripts/backup.sh

# Verify backups
/root/thermalog-infrastructure/scripts/verify-latest-backup.sh
```

## Script Details

### Active Infrastructure Scripts

#### backup.sh
**Purpose**: Creates daily unencrypted backup of entire system
**Includes**:
- PostgreSQL database dumps (iot_platform)
- Docker volumes (4 volumes)
- SSL certificates (ECDSA + RSA)
- Environment files (.env from all repos)
- Systemd service files
- Nginx configuration
- Crontab
- System information

**Location**: `/var/backups/thermalog/`
**Retention**: Last 10 backups
**Schedule**: Daily at 3 AM Sydney (17:00 UTC)

**Manual execution**:
```bash
/root/thermalog-infrastructure/scripts/backup.sh
```

See [BACKUP_DOCUMENTATION.md](../docs/BACKUP_DOCUMENTATION.md) for details.

#### verify-latest-backup.sh
**Purpose**: Validates integrity and completeness of latest backup
**Checks**:
- Backup file exists and is not empty
- Archive integrity (tar -tzf)
- Reasonable file size (>10MB)
- Contains all expected components
- Database dump is valid SQL
- SSL certificates are present
- Environment files exist

**Schedule**: Weekly Sunday 4 AM Sydney (18:00 UTC Saturday)

**Manual execution**:
```bash
/root/thermalog-infrastructure/scripts/verify-latest-backup.sh
```

### Deployment Scripts

#### setup-server.sh
**Purpose**: Complete initial server configuration
**Actions**:
- Installs Docker and Docker Compose
- Configures firewall (UFW)
- Sets up directory structure
- Installs Certbot for SSL
- Configures timezone (Sydney)
- Clones all required repositories

**Usage**:
```bash
# On fresh Ubuntu server
cd /root/thermalog-infrastructure
./scripts/setup-server.sh
```

#### deploy.sh
**Purpose**: Deploy or update application stack
**Actions**:
- Pulls latest code from GitHub
- Builds Docker containers
- Restarts services
- Verifies deployment

**Usage**:
```bash
./scripts/deploy.sh
```

#### setup-auto-deploy.sh
**Purpose**: Configure automated deployment
**Actions**:
- Sets up cron job for auto-deploy.sh
- Configures deployment logs
- Tests initial deployment

**Usage**:
```bash
./scripts/setup-auto-deploy.sh
```

#### install-ssl-hooks.sh
**Purpose**: Install Let's Encrypt renewal hooks
**Actions**:
- Copies renewal hooks to `/etc/letsencrypt/renewal-hooks/`
- Sets proper permissions
- Links hooks for both ECDSA and RSA certificates

**Usage**:
```bash
./scripts/install-ssl-hooks.sh
```

## Directory Structure

```
/root/thermalog-infrastructure/
├── scripts/                          # This directory
│   ├── README.md                     # This file
│   ├── backup.sh                     # ACTIVE
│   ├── verify-latest-backup.sh       # ACTIVE
│   ├── setup-server.sh               # DEPLOYMENT
│   ├── deploy.sh                     # DEPLOYMENT
│   ├── setup-auto-deploy.sh          # DEPLOYMENT
│   ├── install-ssl-hooks.sh          # DEPLOYMENT
│   ├── ssl-hooks/                    # SSL renewal hooks
│   │   ├── deploy/
│   │   ├── post/
│   │   └── pre/
│   ├── auto-deploy.sh                # REFERENCE
│   ├── docker-cleanup.sh             # REFERENCE
│   ├── startup-thermalog.sh          # REFERENCE
│   ├── uptime-kuma-alerts-improved.sh # REFERENCE
│   ├── uptime-kuma-alerts.sh         # REFERENCE
│   └── ssl-renew.sh                  # DEPRECATED
└── docs/                             # Documentation
    ├── DEPLOYMENT_GUIDE.md
    ├── BACKUP_DOCUMENTATION.md
    ├── DISASTER_RECOVERY.md
    └── ...
```

## Logs

### Infrastructure Script Logs

| Script | Log Location |
|--------|--------------|
| `backup.sh` | `/root/thermalog-ops/logs/maintenance/backup.log` |
| `verify-latest-backup.sh` | `/root/thermalog-ops/logs/maintenance/backup-verify.log` |

### Operational Script Logs

All operational scripts from thermalog-ops log to:
```
/root/thermalog-ops/logs/
├── deployment/
│   └── auto-deploy-cron.log
├── maintenance/
│   ├── docker-cleanup-cron.log
│   ├── process-cleanup-cron.log
│   ├── ssl-renewal.log
│   ├── backup.log
│   └── backup-verify.log
└── monitoring/
    └── uptime-alerts.log
```

View recent logs:
```bash
# Backup logs
tail -f /root/thermalog-ops/logs/maintenance/backup.log

# All recent activity
tail -f /root/thermalog-ops/logs/**/*.log
```

## Troubleshooting

### Script Execution Issues

**Permission denied**:
```bash
# Fix permissions
chmod +x /root/thermalog-infrastructure/scripts/*.sh
```

**Script not found**:
```bash
# Verify script location
ls -la /root/thermalog-infrastructure/scripts/

# Use absolute path
/root/thermalog-infrastructure/scripts/backup.sh
```

**Cron job not running**:
```bash
# Check cron is active
systemctl status cron

# View cron logs
grep CRON /var/log/syslog | tail -20

# Verify crontab
crontab -l
```

### Which Script to Use?

**Decision Tree**:

1. **Backup/restore operations?**
   → Use `/root/thermalog-infrastructure/scripts/backup.sh` or `verify-latest-backup.sh`

2. **New server setup?**
   → Use `/root/thermalog-infrastructure/scripts/setup-server.sh` and `deploy.sh`

3. **Daily operations (deployment, maintenance, monitoring)?**
   → Use scripts from `/root/thermalog-ops/scripts/`

4. **Unsure which version to use?**
   → Check cron jobs (`crontab -l`) to see which scripts are actively running

## Migration from Old Scripts

If you have old scripts or are migrating to the current architecture:

### SSL Renewal Migration
```bash
# OLD (deprecated)
/root/thermalog-infrastructure/scripts/ssl-renew.sh

# NEW (dual certificates)
/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh
```

### Update Cron Jobs
```bash
# Edit crontab
crontab -e

# Replace old paths with new paths from thermalog-ops
# Example:
# OLD: */5 * * * * /root/auto-deploy.sh
# NEW: */5 * * * * /root/thermalog-ops/scripts/deployment/auto-deploy.sh
```

See [MIGRATION_NOTES.md](../MIGRATION_NOTES.md) for complete migration guide.

## Best Practices

1. **Always use absolute paths** in cron jobs
2. **Test scripts manually** before adding to cron
3. **Monitor logs** regularly for errors
4. **Keep reference scripts** for documentation
5. **Document custom modifications** in comments
6. **Version control all changes** via Git

## Related Documentation

- [DEPLOYMENT_GUIDE.md](../docs/DEPLOYMENT_GUIDE.md) - Complete deployment procedures
- [BACKUP_DOCUMENTATION.md](../docs/BACKUP_DOCUMENTATION.md) - Backup system details
- [DISASTER_RECOVERY.md](../docs/DISASTER_RECOVERY.md) - Recovery procedures
- [AUTOMATED_DEPLOYMENT.md](../docs/AUTOMATED_DEPLOYMENT.md) - Auto-deployment system
- [CURRENT_ARCHITECTURE.md](../docs/CURRENT_ARCHITECTURE.md) - System architecture

## Questions?

- Check the documentation in `/root/thermalog-infrastructure/docs/`
- Review [troubleshooting.md](../docs/troubleshooting.md)
- See [CURRENT_ARCHITECTURE.md](../docs/CURRENT_ARCHITECTURE.md) for complete system reference

---

**Last Updated**: October 2025
**Repository**: [thermalog-infrastructure](https://github.com/Thermalog/thermalog-infrastructure)
