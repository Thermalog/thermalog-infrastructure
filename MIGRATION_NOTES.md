# Migration Notes

Historical record of major architecture changes, migrations, and system updates for the Thermalog production server.

## Overview

This document tracks significant migrations and changes to the Thermalog infrastructure. Use this as a reference for:
- Understanding why current architecture decisions were made
- Troubleshooting legacy issues
- Planning future migrations
- Onboarding new team members

## Timeline of Major Migrations

| Date | Migration | Status | Impact |
|------|-----------|--------|--------|
| Sept 2025 | Mosquitto → EMQX Platform 5.8.8 | ✅ Complete | High |
| Sept 2025 | Single SSL → Dual SSL (ECDSA + RSA) | ✅ Complete | Medium |
| Sept 2025 | Script consolidation to thermalog-ops | ✅ Complete | Medium |
| Sept 2025 | SSL renewal: systemd timer → cron | ✅ Complete | Low |
| Sept 2025 | /root directory reorganization | ✅ Complete | Low |
| Sept 2025 | New systemd services added | ✅ Complete | Medium |
| Oct 2025 | Documentation modernization | ✅ Complete | Low |

---

## Migration 1: Mosquitto → EMQX Platform 5.8.8

### Overview
**Date**: September 2025
**Reason**: Need for enterprise-grade IoT platform with better scalability, monitoring, and TimescaleDB integration

### What Changed

#### Before (Mosquitto)
```
IoT Devices
    ↓ MQTT
Mosquitto Broker (basic)
    ↓
Simple authentication
    ↓
Limited data storage
```

#### After (EMQX Platform)
```
IoT Devices
    ↓ MQTT (TLS 8883)
EMQX Broker 5.8.8
    ↓
PostgreSQL 15 + TimescaleDB
    ↓
Provisioning Service (Node.js)
    ↓
Rule engine + Advanced monitoring
```

### New Components

| Component | Purpose | Port |
|-----------|---------|------|
| EMQX Broker 5.8.8 | MQTT message broker | 1883, 8883, 18083 |
| PostgreSQL 15 + TimescaleDB | Device credentials + time-series data | 5432 |
| Provisioning Service | Device registration API | 3002 |

### New Docker Containers

**Added to production**:
```yaml
# /root/emqx-platform/docker-compose.yml
services:
  iot-postgres:      # PostgreSQL 15 + TimescaleDB
  emqx:              # EMQX Broker 5.8.8
  provisioning-service:  # Device provisioning API
```

### New Systemd Service

**File**: `/etc/systemd/system/emqx-platform.service`

```bash
# Enable EMQX platform
systemctl enable emqx-platform.service
systemctl start emqx-platform.service
```

### Database Changes

**New Database**: `iot_platform` (PostgreSQL 15 + TimescaleDB)

**Key Tables**:
- `device_credentials` - MQTT authentication
- `temperature_readings` - TimescaleDB hypertable for sensor data
- `device_metadata` - Device information

### Migration Steps Performed

1. **Installed EMQX Platform**:
   ```bash
   cd /root
   git clone https://github.com/Thermalog/emqx-platform.git
   cd emqx-platform
   docker compose up -d
   ```

2. **Migrated device credentials** from Mosquitto to PostgreSQL

3. **Updated firewall**:
   ```bash
   ufw allow 8883/tcp  # MQTTS
   ufw allow 18083/tcp # EMQX Dashboard (restricted)
   ```

4. **Created systemd service** for EMQX platform

5. **Migrated IoT devices** to new MQTT endpoint with new credentials

6. **Added EMQX monitoring** to Uptime Kuma

### Impact

**Benefits**:
- ✅ Better scalability (100,000+ messages/second)
- ✅ TimescaleDB for efficient time-series data
- ✅ Built-in monitoring dashboard
- ✅ Rule engine for data processing
- ✅ PostgreSQL-based authentication

**Breaking Changes**:
- ⚠️ Device credentials changed (all devices needed re-provisioning)
- ⚠️ MQTT port changed: 8883 (was 1883 with Mosquitto)
- ⚠️ New provisioning workflow required

**Rollback Plan** (if needed):
- Keep Mosquitto container available (disabled)
- Database backup before migration
- Documented rollback procedure

### Current Status
✅ **Production** - All IoT devices migrated and operational

### Documentation
- [EMQX_PLATFORM.md](docs/EMQX_PLATFORM.md) - Complete platform guide
- [CURRENT_ARCHITECTURE.md](docs/CURRENT_ARCHITECTURE.md) - System architecture

---

## Migration 2: Single SSL → Dual SSL Certificates

### Overview
**Date**: September 2025
**Reason**: Improve browser compatibility while maintaining modern security (ECDSA for modern browsers, RSA for legacy)

### What Changed

#### Before (Single SSL)
```nginx
# Single certificate (RSA or ECDSA)
ssl_certificate /path/to/fullchain.pem;
ssl_certificate_key /path/to/privkey.pem;
```

#### After (Dual SSL)
```nginx
# Dual certificates (ECDSA + RSA)
ssl_certificate /etc/ssl/certs/fullchain-ecdsa.pem;
ssl_certificate_key /etc/ssl/certs/privkey-ecdsa.pem;
ssl_certificate /etc/ssl/certs/fullchain-rsa.pem;
ssl_certificate_key /etc/ssl/certs/privkey-rsa.pem;
```

### New Certificate Structure

| Type | Key Size | Domain Name | Purpose |
|------|----------|-------------|---------|
| ECDSA | P-384 | `dashboard.thermalog.com.au` | Modern browsers |
| RSA | 4096-bit | `dashboard.thermalog.com.au-rsa` | Legacy compatibility |

### Certificate Locations

```
/etc/letsencrypt/live/
├── dashboard.thermalog.com.au/           # ECDSA
│   ├── fullchain.pem
│   └── privkey.pem
└── dashboard.thermalog.com.au-rsa/       # RSA
    ├── fullchain.pem
    └── privkey.pem

/root/Config/nginx/                       # Deployed certificates
├── fullchain-ecdsa.pem
├── privkey-ecdsa.pem
├── fullchain-rsa.pem
└── privkey-rsa.pem
```

### Migration Steps Performed

1. **Generated ECDSA certificate**:
   ```bash
   certbot certonly --standalone -d dashboard.thermalog.com.au \
     --key-type ecdsa --elliptic-curve secp384r1
   ```

2. **Generated RSA certificate**:
   ```bash
   certbot certonly --standalone -d dashboard.thermalog.com.au \
     --cert-name dashboard.thermalog.com.au-rsa \
     --key-type rsa --rsa-key-size 4096
   ```

3. **Updated nginx configuration** to use both certificates

4. **Created new renewal script**: `ssl-renew-dual.sh`

5. **Updated cron job** to use dual renewal script

6. **Deployed certificates** to nginx directory with proper naming

### Renewal Changes

**Old**:
```bash
# Single certificate renewal
15 3,15 * * * /root/thermalog-infrastructure/scripts/ssl-renew.sh
```

**New**:
```bash
# Dual certificate renewal
15 3,15 * * * /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh
```

### Nginx Configuration Updates

**Added to nginx config**:
```nginx
# Cipher suites supporting both ECDSA and RSA
ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';

# Let client choose (modern approach)
ssl_prefer_server_ciphers off;
```

### Performance Benefits

| Metric | ECDSA P-384 | RSA 4096 | Improvement |
|--------|-------------|----------|-------------|
| Certificate Size | ~500 bytes | ~1600 bytes | 68% smaller |
| Handshake Speed | Fast | Moderate | 30-40% faster |
| CPU Usage | Low | Higher | 30% less CPU |

### Impact

**Benefits**:
- ✅ 30-40% faster TLS handshake for modern browsers
- ✅ 100% browser compatibility (ECDSA + RSA fallback)
- ✅ Lower CPU usage
- ✅ Better mobile performance

**No Breaking Changes**:
- ✅ Backwards compatible (old browsers get RSA)
- ✅ Automatic certificate selection by nginx

### Current Status
✅ **Production** - Both certificates active and auto-renewing

### Documentation
- [DUAL_SSL_CERTIFICATES.md](docs/DUAL_SSL_CERTIFICATES.md) - Complete dual SSL guide
- [SSL_RENEWAL.md](docs/SSL_RENEWAL.md) - Renewal automation

---

## Migration 3: Script Consolidation to thermalog-ops

### Overview
**Date**: September 2025
**Reason**: Organize operational scripts separately from infrastructure/deployment scripts

### What Changed

#### Before
```
/root/
├── auto-deploy.sh
├── docker-cleanup.sh
├── uptime-kuma-alerts-improved.sh
├── startup-thermalog.sh
└── [scattered scripts in multiple locations]
```

#### After
```
/root/thermalog-ops/scripts/
├── deployment/
│   ├── auto-deploy.sh
│   ├── cleanup_processes.sh
│   ├── startup-thermalog.sh
│   └── shutdown-thermalog.sh
├── maintenance/
│   ├── docker-cleanup.sh
│   └── ssl-renew-dual.sh
├── monitoring/
│   ├── uptime-kuma-alerts-improved.sh
│   └── configure-monitors.sh
└── backup/
    └── create-encrypted-backup.sh
```

### Script Migration Map

| Old Location | New Location | Category |
|--------------|--------------|----------|
| `/root/auto-deploy.sh` | `/root/thermalog-ops/scripts/deployment/auto-deploy.sh` | Deployment |
| `/root/docker-cleanup.sh` | `/root/thermalog-ops/scripts/maintenance/docker-cleanup.sh` | Maintenance |
| `/root/uptime-kuma-alerts-improved.sh` | `/root/thermalog-ops/scripts/monitoring/uptime-kuma-alerts-improved.sh` | Monitoring |
| `/root/startup-thermalog.sh` | `/root/thermalog-ops/scripts/deployment/startup-thermalog.sh` | Deployment |
| `/root/ssl-renew.sh` | `/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh` | Maintenance |

### Symlinks Created

For backward compatibility:
```bash
ln -s /root/thermalog-ops/scripts/deployment/auto-deploy.sh /root/auto-deploy.sh
```

**Note**: Symlinks created but **cron jobs updated to use full paths**.

### Migration Steps Performed

1. **Created new directory structure** in thermalog-ops

2. **Moved active scripts** to appropriate categories

3. **Updated all cron jobs** to use new paths:
   ```bash
   crontab -e
   # Updated all paths from /root/ to /root/thermalog-ops/scripts/
   ```

4. **Created symlinks** for commonly accessed scripts

5. **Updated systemd services** to use new script locations

6. **Kept reference copies** in thermalog-infrastructure for deployment

### Cron Job Updates

**Example migration**:
```bash
# OLD
*/5 * * * * /root/auto-deploy.sh >> /root/logs/auto-deploy.log 2>&1

# NEW
*/5 * * * * /root/thermalog-ops/scripts/deployment/auto-deploy.sh >> /root/thermalog-ops/logs/deployment/auto-deploy-cron.log 2>&1
```

### Impact

**Benefits**:
- ✅ Better organization (deployment, maintenance, monitoring, backup)
- ✅ Clear separation of concerns
- ✅ Easier to maintain and update
- ✅ Improved logging structure
- ✅ Version control for operational scripts

**No Breaking Changes**:
- ✅ Symlinks maintain backward compatibility
- ✅ All cron jobs updated atomically

### Current Status
✅ **Complete** - All scripts migrated and operational

### Documentation
- [scripts/README.md](scripts/README.md) - Script organization guide

---

## Migration 4: SSL Renewal (systemd timer → cron)

### Overview
**Date**: September 2025
**Reason**: Simplify automation, consolidate all scheduled tasks in cron, easier troubleshooting

### What Changed

#### Before (systemd timer)
```bash
# /etc/systemd/system/certbot-renew.timer
[Timer]
OnCalendar=*-*-* 00,12:00:00
```

#### After (cron)
```bash
# crontab
15 3,15 * * * /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh
```

### Migration Steps Performed

1. **Disabled systemd timer**:
   ```bash
   systemctl stop certbot-renew.timer
   systemctl disable certbot-renew.timer
   ```

2. **Created dual SSL renewal script**:
   ```bash
   /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh
   ```

3. **Added cron job**:
   ```bash
   crontab -e
   # Added: 15 3,15 * * * /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh
   ```

4. **Tested manual renewal**:
   ```bash
   /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh
   ```

### Why This Change?

**Problems with systemd timer**:
- Separate from other automation (cron)
- Less visible in `crontab -l`
- Different logging approach
- More complex troubleshooting

**Benefits of cron**:
- ✅ All automation in one place (`crontab -l`)
- ✅ Consistent logging approach
- ✅ Easier to troubleshoot
- ✅ Standard across all scripts

### Schedule Comparison

| Method | Schedule | Sydney Time |
|--------|----------|-------------|
| systemd timer (old) | 00:00, 12:00 UTC | 10 AM, 10 PM |
| cron (new) | 3:15, 15:15 UTC | 1:15 PM, 1:15 AM |

**Note**: Both run twice daily, just different times.

### Impact

**Benefits**:
- ✅ Simplified automation management
- ✅ Consistent with other scheduled tasks
- ✅ Better visibility

**No Breaking Changes**:
- ✅ Still runs twice daily
- ✅ Same renewal process

### Current Status
✅ **Production** - Cron-based renewal active

---

## Migration 5: /root Directory Reorganization

### Overview
**Date**: September 2025
**Reason**: Organize /root directory for clarity, separate concerns (documentation, scripts, configs, repositories)

### What Changed

#### Before
```
/root/
├── Thermalog-Backend/
├── Thermalog-frontend/
├── thermalog-infrastructure/
├── nginx/
├── docker-compose.yml
├── auto-deploy.sh
├── backup.sh
└── [many scattered files]
```

#### After
```
/root/
├── Documentation/
├── Scripts/
├── Config/
│   └── nginx/
├── Reference Repositories/
│   ├── Thermalog-Gateway/
│   └── Thermalog-Android/
├── Active Repositories/
│   ├── Thermalog-Backend/
│   ├── Thermalog-frontend/
│   ├── thermalog-infrastructure/
│   ├── thermalog-ops/
│   └── emqx-platform/
└── [symlinks for compatibility]
```

### Symlinks Created

For backward compatibility:
```bash
ln -s /root/Config/nginx /root/nginx
ln -s /root/thermalog-ops/config/docker-compose.yml /root/docker-compose.yml
ln -s /root/Scripts/add-iot-monitors.sh /root/add-iot-monitors.sh
ln -s /root/thermalog-ops/scripts/deployment/auto-deploy.sh /root/auto-deploy.sh
```

### Migration Steps Performed

1. **Created organizational directories**:
   ```bash
   mkdir -p /root/Documentation
   mkdir -p /root/Scripts
   mkdir -p /root/Config
   mkdir -p /root/Active\ Repositories
   mkdir -p /root/Reference\ Repositories
   ```

2. **Moved nginx config**:
   ```bash
   mv /root/nginx /root/Config/nginx
   ln -s /root/Config/nginx /root/nginx
   ```

3. **Created symlinks** for frequently accessed files

4. **Updated documentation** to reflect new structure

### Impact

**Benefits**:
- ✅ Clearer organization
- ✅ Easier navigation
- ✅ Separate active from reference repositories
- ✅ Centralized configurations

**No Breaking Changes**:
- ✅ Symlinks maintain compatibility
- ✅ All existing paths still work

### Current Status
✅ **Complete** - New structure in use

### Documentation
- [CURRENT_ARCHITECTURE.md](docs/CURRENT_ARCHITECTURE.md#directory-structure) - Directory structure

---

## Migration 6: New Systemd Services

### Overview
**Date**: September 2025
**Reason**: Ensure reliable startup/shutdown, automate service management

### Services Added

#### Before
```bash
# Manual Docker commands
docker compose up -d
```

#### After
```bash
# Systemd services
systemctl start thermalog.service
systemctl start emqx-platform.service
```

### New Services

| Service | Purpose | Auto-Start |
|---------|---------|------------|
| `thermalog.service` | Main application stack | ✅ Enabled |
| `thermalog-startup.service` | Startup verification | ✅ Enabled |
| `thermalog-shutdown.service` | Graceful shutdown | ✅ Enabled |
| `emqx-platform.service` | EMQX IoT platform | ✅ Enabled |

### Service Files

**Location**: `/etc/systemd/system/`

```bash
/etc/systemd/system/
├── thermalog.service
├── thermalog-startup.service
├── thermalog-shutdown.service
└── emqx-platform.service
```

### Migration Steps Performed

1. **Created service files** in `/etc/systemd/system/`

2. **Enabled services**:
   ```bash
   systemctl daemon-reload
   systemctl enable thermalog.service
   systemctl enable thermalog-startup.service
   systemctl enable thermalog-shutdown.service
   systemctl enable emqx-platform.service
   ```

3. **Tested startup**:
   ```bash
   systemctl start thermalog.service
   systemctl start emqx-platform.service
   ```

4. **Verified auto-start** after reboot

### Service Dependencies

```
Boot Sequence:
1. docker.service
2. emqx-platform.service (requires docker)
3. thermalog.service (requires docker)
4. thermalog-startup.service (after thermalog)
```

### Impact

**Benefits**:
- ✅ Automatic startup after server reboot
- ✅ Graceful shutdown handling
- ✅ Service monitoring via systemd
- ✅ Dependency management
- ✅ Startup verification

**No Breaking Changes**:
- ✅ Docker Compose still works manually
- ✅ Services wrap existing docker-compose files

### Current Status
✅ **Production** - All services enabled and auto-starting

### Documentation
- [SERVER_RESTART_RESILIENCE.md](docs/SERVER_RESTART_RESILIENCE.md) - Service configuration

---

## Migration 7: Cron Job Path Changes

### Overview
**Date**: September 2025
**Reason**: Consolidate with script organization migration, use full absolute paths

### Path Changes

| Script | Old Path | New Path |
|--------|----------|----------|
| Auto-deploy | `/root/auto-deploy.sh` | `/root/thermalog-ops/scripts/deployment/auto-deploy.sh` |
| Docker cleanup | `/root/docker-cleanup.sh` | `/root/thermalog-ops/scripts/maintenance/docker-cleanup.sh` |
| Monitoring | `/root/uptime-kuma-alerts-improved.sh` | `/root/thermalog-ops/scripts/monitoring/uptime-kuma-alerts-improved.sh` |
| SSL renewal | `/root/ssl-renew.sh` | `/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh` |
| Backup | `/root/thermalog-infrastructure/scripts/backup.sh` | (unchanged - already correct) |
| Backup verify | `/root/thermalog-infrastructure/scripts/verify-latest-backup.sh` | (unchanged - already correct) |

### Complete Updated Crontab

```bash
# Auto-deployment every 5 minutes
*/5 * * * * /root/thermalog-ops/scripts/deployment/auto-deploy.sh >> /root/thermalog-ops/logs/deployment/auto-deploy-cron.log 2>&1

# Monitoring alerts every 2 minutes
*/2 * * * * /root/thermalog-ops/scripts/monitoring/uptime-kuma-alerts-improved.sh >> /root/thermalog-ops/logs/monitoring/uptime-alerts.log 2>&1

# Docker cleanup daily at 2 AM UTC
0 2 * * * /root/thermalog-ops/scripts/maintenance/docker-cleanup.sh >> /root/thermalog-ops/logs/maintenance/docker-cleanup-cron.log 2>&1

# Process cleanup every 12 hours
0 */12 * * * /root/thermalog-ops/scripts/deployment/cleanup_processes.sh >> /root/thermalog-ops/logs/maintenance/process-cleanup-cron.log 2>&1

# Dual SSL renewal twice daily
15 3,15 * * * /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh >> /root/thermalog-ops/logs/maintenance/ssl-renewal.log 2>&1

# Daily backup at 3 AM Sydney (17:00 UTC)
0 17 * * * /root/thermalog-infrastructure/scripts/backup.sh >> /root/thermalog-ops/logs/maintenance/backup.log 2>&1

# Weekly backup verification Sunday 4 AM Sydney (18:00 UTC Saturday)
0 18 * * 6 /root/thermalog-infrastructure/scripts/verify-latest-backup.sh >> /root/thermalog-ops/logs/maintenance/backup-verify.log 2>&1
```

### Migration Steps Performed

1. **Edited crontab**:
   ```bash
   crontab -e
   ```

2. **Updated all paths** to use full absolute paths

3. **Updated log paths** to new centralized location

4. **Verified cron jobs**:
   ```bash
   crontab -l
   grep CRON /var/log/syslog
   ```

### Impact

**Benefits**:
- ✅ Consistent absolute paths
- ✅ Centralized logging in `/root/thermalog-ops/logs/`
- ✅ Clear separation by category (deployment, maintenance, monitoring)

**No Breaking Changes**:
- ✅ All cron jobs still run on same schedule

### Current Status
✅ **Production** - All cron jobs updated and running

---

## Migration 8: Documentation Modernization

### Overview
**Date**: October 2025
**Reason**: Update all documentation to reflect current architecture, remove obsolete information

### What Changed

#### Updated Documentation (11 files)
1. `README.md` - Added EMQX, dual SSL, updated structure
2. `DEPLOYMENT_GUIDE.md` - Fixed script paths, added EMQX
3. `BACKUP_DOCUMENTATION.md` - Clarified dual backup approach
4. `docs/SSL_RENEWAL.md` - Complete rewrite for dual certificates
5. `docs/ssl-setup.md` - Updated for dual certificate setup
6. `docs/AUTOMATED_DEPLOYMENT.md` - Updated paths, added EMQX
7. `docs/MONITORING.md` - Added EMQX containers
8. `docs/SERVER_RESTART_RESILIENCE.md` - Added all systemd services
9. `docs/troubleshooting.md` - Added EMQX and dual SSL sections
10. `docs/deployment.md` - Updated for current architecture
11. `scripts/README.md` - New script organization guide

#### New Documentation (3 files)
1. `docs/EMQX_PLATFORM.md` - Complete IoT platform guide
2. `docs/DUAL_SSL_CERTIFICATES.md` - Dual certificate system
3. `docs/CURRENT_ARCHITECTURE.md` - System architecture reference
4. `docs/DISASTER_RECOVERY.md` - Recovery procedures

#### Removed/Cleaned
- Deleted 3 .backup files
- Removed empty docker/ directory
- Marked old scripts as deprecated

### Impact

**Benefits**:
- ✅ Accurate current documentation
- ✅ Complete deployment reference
- ✅ Disaster recovery procedures
- ✅ Better onboarding for developers

### Current Status
✅ **Complete** - All documentation updated

---

## Future Migration Plans

### Planned Migrations

| Migration | Priority | Complexity | Target Date |
|-----------|----------|------------|-------------|
| Move to managed PostgreSQL for main app | Medium | High | TBD |
| Implement HA (High Availability) | Low | High | TBD |
| Containerize backup system | Low | Medium | TBD |

### Under Consideration

- **Kubernetes migration**: For multi-server deployments
- **Automated testing**: Integration tests for deployments
- **Blue-green deployments**: Zero-downtime updates

---

## Rollback Procedures

### If Issues Arise from Recent Migrations

#### Rollback EMQX to Mosquitto
```bash
# Stop EMQX platform
systemctl stop emqx-platform.service

# Start Mosquitto (if container still exists)
docker start mosquitto

# Update device configurations to use Mosquitto
# Restore from pre-migration backup if needed
```

#### Rollback to Single SSL
```bash
# Use only one certificate in nginx config
# Comment out second ssl_certificate lines
docker exec nginx vim /etc/nginx/conf.d/default.conf
docker exec nginx nginx -s reload
```

#### Rollback Script Locations
```bash
# Symlinks still exist, so old paths work
# Or copy scripts back to /root/
cp /root/thermalog-ops/scripts/deployment/auto-deploy.sh /root/
```

---

## Lessons Learned

### Successful Strategies

1. **Phased migrations** - One major change at a time
2. **Backward compatibility** - Symlinks and dual support during transition
3. **Comprehensive testing** - Test in staging before production
4. **Documentation first** - Document before and after states
5. **Backup before migration** - Always create full backup

### Challenges Encountered

1. **Device re-provisioning** - Required updating all IoT devices for EMQX
2. **Certificate timing** - Coordinating dual SSL renewal initially tricky
3. **Path updates** - Many cron jobs to update for script consolidation

### Best Practices Going Forward

1. ✅ **Always backup** before major changes
2. ✅ **Document migration plan** before executing
3. ✅ **Maintain backward compatibility** during transition
4. ✅ **Test thoroughly** in non-production environment
5. ✅ **Update documentation** immediately after migration
6. ✅ **Have rollback plan** ready before starting

---

## Verification Checklist

After any migration, verify these components:

### Core Services
- [ ] All Docker containers running (`docker ps`)
- [ ] All systemd services active (`systemctl status`)
- [ ] HTTPS accessible (`curl -I https://dashboard.thermalog.com.au`)
- [ ] Backend API responding (`curl https://dashboard.thermalog.com.au/api/health`)

### EMQX Platform
- [ ] EMQX broker running (`docker exec emqx emqx ctl status`)
- [ ] PostgreSQL accessible (`docker exec iot-postgres pg_isready`)
- [ ] Test MQTT connection

### SSL Certificates
- [ ] Both certificates present (`ls /root/Config/nginx/*.pem`)
- [ ] Valid and not expired (`openssl x509 -enddate`)
- [ ] HTTPS working without warnings

### Automation
- [ ] All cron jobs present (`crontab -l`)
- [ ] Scripts executable and in correct locations
- [ ] Logs being generated

### Backups
- [ ] Backup running successfully
- [ ] Latest backup exists and is valid
- [ ] Backup verification passing

---

## Related Documentation

- [CURRENT_ARCHITECTURE.md](docs/CURRENT_ARCHITECTURE.md) - Current system architecture
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Deployment procedures
- [DISASTER_RECOVERY.md](docs/DISASTER_RECOVERY.md) - Recovery procedures
- [scripts/README.md](scripts/README.md) - Script organization

---

**Last Updated**: October 2025
**Maintainer**: Thermalog Infrastructure Team

For questions about these migrations, refer to the individual documentation files or review commit history in the respective repositories.
