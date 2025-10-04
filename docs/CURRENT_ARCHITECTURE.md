# Current System Architecture

Complete reference for the Thermalog production server architecture as of October 2025.

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Thermalog Production Server               │
│                                                               │
│  ┌──────────────────┐          ┌─────────────────────────┐  │
│  │  Main App Stack  │          │   EMQX IoT Platform     │  │
│  │                  │          │                         │  │
│  │  - Backend       │          │  - MQTT Broker (EMQX)   │  │
│  │  - Frontend      │          │  - PostgreSQL/TimeScale │  │
│  │  - Nginx (dual)  │          │  - Provisioning Service │  │
│  │  - Uptime Kuma   │          │                         │  │
│  └──────────────────┘          └─────────────────────────┘  │
│                                                               │
│  Automation: Cron + Systemd Services                         │
│  Monitoring: Uptime Kuma + SendGrid Alerts                   │
│  Backup: Daily automated + Weekly verification               │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

### /root/ Organization
```
/root/
├── Documentation/                    # All markdown documentation
│   ├── ARCHITECTURE_DIAGRAM.md
│   ├── ARCHITECTURE_DIAGRAM.txt
│   ├── DOCKER-COMPOSE-CONFIG.md
│   ├── README.md
│   └── SERVER_ARCHITECTURE_OVERVIEW.md
│
├── Scripts/                          # Operational scripts
│   ├── add-iot-monitors.sh
│   ├── test-https-dashboard.sh
│   └── installers/
│       └── get-docker.sh
│
├── Config/                           # Configuration files
│   ├── nginx/                       # Nginx config (ECDSA + RSA certs)
│   ├── secrets/                     # Secure credentials
│   └── docker-compose.secrets.yml
│
├── Reference Repositories/           # Archived/reference code
│   ├── Thermalog-Gateway/
│   └── Thermalog-Android/
│
├── Active Repositories/              # Production code
│   ├── Thermalog-Backend/
│   ├── Thermalog-frontend/
│   ├── thermalog-infrastructure/
│   ├── thermalog-ops/
│   └── emqx-platform/
│
└── [Symlinks for backward compatibility]
    ├── nginx → Config/nginx
    ├── docker-compose.yml → thermalog-ops/config/docker-compose.yml
    ├── add-iot-monitors.sh → Scripts/add-iot-monitors.sh
    └── auto-deploy.sh → thermalog-ops/scripts/deployment/auto-deploy.sh
```

### thermalog-ops Structure
```
/root/thermalog-ops/
├── scripts/
│   ├── deployment/
│   │   ├── auto-deploy.sh
│   │   ├── setup-auto-deploy.sh
│   │   ├── startup-thermalog.sh
│   │   ├── shutdown-thermalog.sh
│   │   └── cleanup_processes.sh
│   ├── maintenance/
│   │   ├── docker-cleanup.sh
│   │   └── ssl-renew-dual.sh
│   ├── monitoring/
│   │   ├── uptime-kuma-alerts-improved.sh
│   │   ├── uptime-kuma-alerts.sh
│   │   └── configure-monitors.sh
│   ├── backup/
│   │   ├── create-encrypted-backup.sh
│   │   └── create-server-backup.sh
│   └── security/
│       └── load-secrets.sh
├── config/
│   └── docker-compose.yml
└── logs/
    ├── deployment/
    ├── maintenance/
    └── monitoring/
```

## Docker Containers

### Main Application Stack
**Location**: `/root/thermalog-ops/config/docker-compose.yml`

| Container | Image | Ports | Purpose |
|-----------|-------|-------|---------|
| thermalog-backend | Custom (Node.js) | 3001 | Main API server |
| thermalog-frontend | Custom (React) | 80 | Web dashboard |
| nginx | nginx:alpine | 80, 443 | Reverse proxy, SSL termination |
| uptime-kuma | louislam/uptime-kuma | 3002 | Monitoring dashboard |

### EMQX IoT Platform
**Location**: `/root/emqx-platform/docker-compose.yml`

| Container | Image | Ports | Purpose |
|-----------|-------|-------|---------|
| iot-postgres | timescale/timescaledb:latest-pg15 | 5432 | IoT database + TimescaleDB |
| emqx | emqx/emqx:5.8.8 | 1883, 8883, 18083 | MQTT broker |
| provisioning-service | Custom (Node.js) | 3002 | Device provisioning API |

## Docker Volumes

| Volume Name | Purpose | Backup Status |
|-------------|---------|---------------|
| thermalog_uptime-kuma-data | Uptime Kuma config/data | ✅ Daily |
| emqx-platform_postgres-data | IoT PostgreSQL data | ✅ Daily |
| emqx-platform_emqx-data | EMQX broker data | ✅ Daily |
| emqx-platform_emqx-log | EMQX logs | ✅ Daily |

## Systemd Services

| Service | Type | Purpose | Auto-Start |
|---------|------|---------|------------|
| docker.service | System | Docker daemon | ✅ Enabled |
| cron.service | System | Cron scheduler | ✅ Enabled |
| thermalog.service | Application | Main app stack | ✅ Enabled |
| thermalog-startup.service | Application | Startup verification | ✅ Enabled |
| thermalog-shutdown.service | Application | Graceful shutdown | ✅ Enabled |
| emqx-platform.service | Application | EMQX IoT platform | ✅ Enabled |

**Service Files**: `/etc/systemd/system/`

## Cron Jobs (Sydney Time = UTC+10/11)

| Schedule | Script | Purpose |
|----------|--------|---------|
| */5 * * * * | auto-deploy.sh | Auto-deployment from GitHub |
| */2 * * * * | uptime-kuma-alerts-improved.sh | Monitoring alerts (SendGrid) |
| 0 2 * * * | docker-cleanup.sh | Docker maintenance (2 AM UTC) |
| 0 */12 * * * | cleanup_processes.sh | Process cleanup (every 12h) |
| 15 3,15 * * * | ssl-renew-dual.sh | Dual SSL renewal (twice daily) |
| 0 17 * * * | backup.sh | Daily backup (3 AM Sydney) |
| 0 18 * * 6 | verify-latest-backup.sh | Weekly verification (4 AM Sunday Sydney) |

**Full Paths**: All scripts in `/root/thermalog-ops/scripts/`
**Logs**: `/root/thermalog-ops/logs/`

## SSL Certificates

### Dual Certificate System
- **ECDSA P-384**: Modern browsers (`dashboard.thermalog.com.au`)
- **RSA 4096-bit**: Legacy compatibility (`dashboard.thermalog.com.au-rsa`)

### Storage Locations
```
/etc/letsencrypt/
├── live/dashboard.thermalog.com.au/          # ECDSA
├── live/dashboard.thermalog.com.au-rsa/      # RSA
└── renewal/*.conf                             # Auto-renewal configs

/root/Config/nginx/                            # Deployed certificates
├── fullchain-ecdsa.pem
├── privkey-ecdsa.pem
├── fullchain-rsa.pem
└── privkey-rsa.pem
```

### Renewal
- **Method**: Cron-based (`ssl-renew-dual.sh`)
- **Frequency**: Twice daily at 3:15 AM/PM UTC
- **Process**: Stop nginx → Renew both → Deploy → Restart

## Network Architecture

### External Ports
- **80 (HTTP)**: Redirects to HTTPS
- **443 (HTTPS)**: Main application (nginx)
- **8883 (MQTTS)**: MQTT over TLS for IoT devices
- **18083 (HTTP)**: EMQX dashboard (restricted)

### Internal Docker Network
- **app-network**: Main application containers
- **emqx-network**: EMQX platform containers
- Bridge networking for inter-stack communication

### Firewall (UFW)
```bash
# Allow rules
80/tcp    # HTTP
443/tcp   # HTTPS
8883/tcp  # MQTTS
22/tcp    # SSH
```

## Database Architecture

### Main Application Database
- **Type**: External PostgreSQL (not on this server)
- **Connection**: Via DATABASE_URL in backend .env
- **Purpose**: User data, device management, app data

### IoT Platform Database
- **Type**: PostgreSQL 15 + TimescaleDB (local Docker)
- **Database**: `iot_platform`
- **Purpose**: Device credentials, temperature time-series data
- **Key Tables**:
  - `device_credentials` - MQTT authentication
  - `temperature_readings` - TimescaleDB hypertable
  - `device_metadata` - Device information

## Environment Files

| Repository | Location | Purpose |
|------------|----------|---------|
| Backend | `/root/Thermalog-Backend/.env` | API config, DB connection |
| Frontend | `/root/Thermalog-frontend/.env` | API URLs, WebSocket config |
| Infrastructure | `/root/thermalog-infrastructure/.env` | Infrastructure settings |
| EMQX Platform | `/root/emqx-platform/.env` | IoT database credentials |

**Security**: All .env files have 600 permissions (root only)
**Backup**: Full backup daily (includes sensitive data)

## Monitoring System

### Uptime Kuma
- **Dashboard**: `https://dashboard.thermalog.com.au/monitoring/`
- **Monitors**: Backend, Frontend, Nginx, EMQX, IoT PostgreSQL
- **Storage**: Docker volume `thermalog_uptime-kuma-data`

### SendGrid Email Alerts
- **Script**: `uptime-kuma-alerts-improved.sh`
- **Frequency**: Every 2 minutes
- **Recipients**: 3 email addresses
- **Alert Types**: DOWN, UP, PENDING

### Logs
- **Deployment**: `/root/thermalog-ops/logs/deployment/`
- **Maintenance**: `/root/thermalog-ops/logs/maintenance/`
- **Monitoring**: `/root/thermalog-ops/logs/monitoring/`

## Backup System

### Daily Backup
- **Script**: `/root/thermalog-infrastructure/scripts/backup.sh`
- **Type**: Unencrypted tar.gz
- **Schedule**: Daily at 3 AM Sydney (17:00 UTC)
- **Location**: `/var/backups/thermalog/`
- **Retention**: Last 10 backups

### Contents
- PostgreSQL database dump (iot_platform)
- All 4 Docker volumes
- SSL certificates (both ECDSA + RSA)
- Environment files (all 4 repos)
- Systemd services
- Nginx configuration
- Crontab
- System information

### Verification
- **Script**: `verify-latest-backup.sh`
- **Schedule**: Weekly Sunday 4 AM Sydney (18:00 UTC Sat)
- **Checks**: Integrity, size, database, all components

## Automation Flow

### Server Startup
1. **Systemd** starts Docker, cron
2. **thermalog.service** starts main app stack
3. **emqx-platform.service** starts IoT platform
4. **thermalog-startup.service** verifies all services
5. **Cron** resumes all automation

### Auto-Deployment
1. **Cron** triggers every 5 minutes
2. **auto-deploy.sh** checks GitHub for changes
3. If changes: Pull → Build → Deploy
4. Health check verification
5. Rollback on failure

### SSL Renewal
1. **Cron** triggers twice daily
2. **ssl-renew-dual.sh** checks expiry (<30 days)
3. Stop nginx → Renew both certs → Deploy → Restart
4. Verify HTTPS connectivity
5. Log results

## Security Architecture

### Access Control
- **Root access**: Required for all operations
- **File permissions**: Strict 600/644/755 as needed
- **Firewall**: UFW enabled, only necessary ports open
- **SSH**: Key-based authentication only

### Secrets Management
- **Environment files**: 600 permissions
- **SSL private keys**: 600 permissions
- **Database credentials**: In .env files
- **API keys**: Environment variables
- **Backup encryption**: AES-256-CBC for off-site

### TLS/SSL
- **Protocols**: TLS 1.2, TLS 1.3 only
- **Dual certificates**: ECDSA + RSA
- **HSTS**: Enabled with 1-year max-age
- **MQTT TLS**: Port 8883 for devices

## Performance Optimizations

### Docker
- Resource limits on containers
- Restart policies: always
- Health checks enabled
- Log rotation configured

### Nginx
- HTTP/2 enabled
- Gzip compression
- Browser caching headers
- Connection pooling

### Database
- TimescaleDB compression
- Connection pooling
- Regular maintenance (vacuuming)
- Optimized indexes

## Disaster Recovery

### Recovery Points
- **Daily backups**: 24-hour RPO
- **Git repositories**: Code recovery
- **Documentation**: This repository
- **Encrypted backups**: Off-site storage

### Recovery Process
1. Deploy new server
2. Clone thermalog-infrastructure
3. Run deploy-everything.sh
4. Restore from backup
5. Verify all services

See [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md) for detailed procedures.

## Version Information

- **OS**: Ubuntu 20.04/22.04 LTS
- **Docker**: Latest stable
- **Node.js**: v18+ (Backend/Frontend)
- **PostgreSQL**: 15 + TimescaleDB
- **EMQX**: 5.8.8
- **Nginx**: Latest alpine
- **Uptime Kuma**: Latest

## Quick Reference Commands

### Service Management
```bash
# Check all services
systemctl status thermalog thermalog-startup emqx-platform

# View containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check logs
tail -f /root/thermalog-ops/logs/**/*.log
```

### Monitoring
```bash
# View cron jobs
crontab -l

# Test SSL
curl -I https://dashboard.thermalog.com.au

# Check EMQX
docker exec emqx emqx ctl status
```

### Backup
```bash
# Manual backup
/root/thermalog-infrastructure/scripts/backup.sh

# Verify latest
/root/thermalog-infrastructure/scripts/verify-latest-backup.sh
```

---

Last Updated: October 2025
For updates and changes, see [MIGRATION_NOTES.md](../MIGRATION_NOTES.md)
