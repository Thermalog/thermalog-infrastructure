# 🏗️ Thermalog Complete Server Architecture

![Status](https://img.shields.io/badge/status-production-success?style=flat-square)
![Uptime](https://img.shields.io/badge/uptime-99.9%25-success?style=flat-square)
![Version](https://img.shields.io/badge/version-EMQX_5.8.8-blue?style=flat-square)
![Containers](https://img.shields.io/badge/containers-7_running-blue?style=flat-square)

**Production Instance:** dashboard.thermalog.com.au
**Last Updated:** October 4, 2025
**EMQX Version:** 5.8.8

---

## 📑 Table of Contents

- [System Overview](#-system-overview)
- [Visual Architecture](#-visual-architecture)
  - [System Architecture Diagram](#system-architecture-diagram-mermaid)
  - [Data Flow Diagrams](#data-flow-diagrams-mermaid)
  - [Network Topology](#network-topology-diagram-mermaid)
  - [Deployment Workflow](#deployment-workflow-mermaid)
- [Docker Compose Stacks](#-docker-compose-stacks)
- [Container Specifications](#-container-specifications)
- [Systemd Services](#️-systemd-services-auto-start)
- [Automation & Cron Jobs](#-automation--cron-jobs)
- [Log Organization](#-log-organization--rotation)
- [SSL/TLS Management](#-ssltls-certificate-management)
- [Port Mapping](#-port-mapping)
- [Network Topology](#-network-topology)
- [Security Features](#-security-features)
- [Health Check Endpoints](#-health-check-endpoints)
- [Performance Metrics](#-performance-metrics--thresholds)
- [Environment Variables](#-environment-variables-reference)
- [Quick Commands Reference](#-quick-commands-reference)
- [Backup & Restore](#-backup--restore-procedures)
- [Disaster Recovery](#-disaster-recovery-plan)
- [Troubleshooting](#-troubleshooting-guide)
- [Maintenance Calendar](#-maintenance-calendar)
- [Dependencies & Versions](#-dependencies--versions)
- [System Status](#-system-status)
- [Documentation & Resources](#-documentation--resources)

---

## 📊 System Overview

| Component | Details |
|-----------|---------|
| 🏗️ **Architecture** | Dual Docker Compose Stacks (Main App + EMQX IoT Platform) |
| 🐳 **Total Containers** | 7 production containers |
| ⚙️ **Systemd Services** | 4 services (auto-start, auto-recovery, graceful shutdown) |
| 🤖 **Automation** | 6 cron jobs (deployment, maintenance, monitoring) |
| 🔐 **SSL/TLS** | Dual certificates (ECDSA + RSA), auto-renewal twice daily |
| 📊 **Monitoring** | Uptime Kuma with alerts every 2 minutes |
| 🚀 **Deployment** | Auto-deployment from GitHub every 5 minutes |
| 💾 **Database** | PostgreSQL 15 + TimescaleDB (time-series) |
| 🌍 **Cloud Provider** | DigitalOcean Droplet + Azure IoT Hub |

[↑ Back to Top](#-table-of-contents)

---

## 🎨 Visual Architecture

### System Architecture Diagram (Mermaid)

```mermaid
graph TB
    subgraph Internet["🌐 INTERNET"]
        NewDevices[New IoT Devices<br/>HMAC Auth]
        LegacyDevices[Legacy IoT Devices<br/>Device Keys]
    end

    subgraph Azure["☁️ AZURE CLOUD"]
        AzureIoT[Azure IoT Hub<br/>ThermalogData + tasmotaIOTHub]
        EventHub[Event Hub]
    end

    subgraph MainStack["📦 MAIN APPLICATION STACK<br/>thermalog_app-network"]
        Nginx[NGINX<br/>Reverse Proxy<br/>:80, :443]
        Backend[Thermalog Backend<br/>Node.js API<br/>:3001]
        Frontend[Thermalog Frontend<br/>React/Next.js<br/>:80]
        Uptime[Uptime Kuma<br/>Monitoring<br/>:3002]
    end

    subgraph IoTStack["📦 EMQX IoT PLATFORM STACK<br/>emqx-platform_iot-network"]
        Provisioning[EMQX Provisioning<br/>Device API<br/>:3003]
        EMQX[EMQX Broker 5.8.8<br/>MQTT/MQTTS<br/>:8883, :8086, :18083]
        TimescaleDB[(PostgreSQL 15<br/>TimescaleDB<br/>:5433)]
    end

    NewDevices -->|HTTPS| Provisioning
    Provisioning -->|Credentials| NewDevices
    NewDevices -->|MQTTS| EMQX
    EMQX --> TimescaleDB

    LegacyDevices -->|MQTT/HTTPS| AzureIoT
    AzureIoT --> EventHub
    EventHub --> Backend

    Nginx -->|/api| Backend
    Nginx -->|/| Frontend
    Backend --> Frontend

    Uptime -.Monitor.-> Nginx
    Uptime -.Monitor.-> Backend
    Uptime -.Monitor.-> EMQX
    Uptime -.Monitor.-> Provisioning

    EMQX -->|Events| Backend
    Provisioning --> TimescaleDB

    style Nginx fill:#2d5,stroke:#1a3,stroke-width:2px
    style EMQX fill:#25d,stroke:#13a,stroke-width:2px
    style TimescaleDB fill:#d52,stroke:#a31,stroke-width:2px
    style AzureIoT fill:#58d,stroke:#36b,stroke-width:2px
```

### Data Flow Diagrams (Mermaid)

#### New Device Provisioning & Data Flow

```mermaid
sequenceDiagram
    participant Device as IoT Device
    participant Prov as EMQX Provisioning API
    participant DB as PostgreSQL/TimescaleDB
    participant EMQX as EMQX Broker
    participant Backend as Backend API
    participant Frontend as Frontend Dashboard

    Note over Device,Prov: PROVISIONING PHASE
    Device->>Prov: HTTPS POST /provision<br/>(HMAC signature)
    Prov->>Prov: Validate HMAC
    Prov->>DB: Store device metadata
    Prov->>DB: Generate credentials<br/>(SHA256 hash)
    DB-->>Prov: Credentials created
    Prov-->>Device: Return username/password

    Note over Device,Frontend: DATA TRANSMISSION PHASE
    Device->>EMQX: MQTTS Connect (TLS)<br/>username + password
    EMQX->>DB: Verify credentials
    DB-->>EMQX: Auth OK
    EMQX-->>Device: Connected

    loop Every interval
        Device->>EMQX: Publish telemetry<br/>topic: device/{id}/data
        EMQX->>DB: Store time-series data
        EMQX->>Backend: Webhook notification
        Backend->>Frontend: Real-time update
    end
```

#### Auto-Deployment Flow

```mermaid
flowchart TD
    Start([Cron: Every 5 min]) --> CheckGitHub{GitHub Changes?}
    CheckGitHub -->|No| End([Sleep 5 min])
    CheckGitHub -->|Yes| PullChanges[Git Pull Latest]

    PullChanges --> BuildImages[Docker Build New Images]
    BuildImages --> HealthCheck1{Current Services<br/>Healthy?}

    HealthCheck1 -->|No| Alert1[Send Alert Email]
    Alert1 --> End

    HealthCheck1 -->|Yes| Deploy[Docker Compose Up<br/>--build --no-deps]
    Deploy --> Wait[Wait 30s for startup]
    Wait --> HealthCheck2{New Services<br/>Healthy?}

    HealthCheck2 -->|No| Rollback[Automatic Rollback]
    Rollback --> RestorePrevious[Restore Previous Images]
    RestorePrevious --> Alert2[Send Failure Email]
    Alert2 --> End

    HealthCheck2 -->|Yes| Cleanup[Cleanup Old Images]
    Cleanup --> Success[Send Success Email]
    Success --> End

    style HealthCheck1 fill:#fd5,stroke:#a31
    style HealthCheck2 fill:#fd5,stroke:#a31
    style Rollback fill:#f55,stroke:#a11
    style Success fill:#5f5,stroke:#1a1
```

### Network Topology Diagram (Mermaid)

```mermaid
graph LR
    subgraph External["🌍 EXTERNAL ACCESS"]
        Users[Users/Devices]
        Internet((Internet))
    end

    subgraph Host["🖥️ HOST MACHINE (Ubuntu 22.04)"]
        subgraph AppNet["thermalog_app-network"]
            nginx[nginx<br/>:80,:443]
            backend[backend<br/>:3001]
            frontend[frontend<br/>:80]
            uptime[uptime-kuma<br/>:3002]
        end

        subgraph IoTNet["emqx-platform_iot-network"]
            emqx[emqx-platform<br/>:8883,:8086,:18083]
            prov[emqx-provisioning<br/>:3003]
            postgres[(iot-postgres<br/>:5433)]
        end
    end

    Internet --> nginx
    Users --> nginx

    nginx -.Internal.-> backend
    nginx -.Internal.-> frontend
    backend -.Internal.-> frontend
    uptime -.Monitor.-> nginx
    uptime -.Monitor.-> backend

    Internet --> emqx
    Internet --> prov
    Users --> emqx
    Users --> prov

    emqx -.Internal.-> postgres
    prov -.Internal.-> postgres

    emqx -.Webhook.-> backend

    style AppNet fill:#e8f5e9,stroke:#4caf50,stroke-width:2px
    style IoTNet fill:#e3f2fd,stroke:#2196f3,stroke-width:2px
    style nginx fill:#2d5,stroke:#1a3,stroke-width:2px
    style emqx fill:#25d,stroke:#13a,stroke-width:2px
```

### Deployment Workflow (Mermaid)

```mermaid
gitGraph
    commit id: "v1.0.0 - Initial Release"
    commit id: "Stable Production"
    branch auto-deploy
    checkout auto-deploy
    commit id: "Cron: Check GitHub"
    commit id: "Pull Latest Changes"
    commit id: "Build & Test"
    checkout main
    merge auto-deploy id: "Auto-Deploy Success" tag: "v1.0.1"
    commit id: "Production Running"
    branch rollback
    checkout rollback
    commit id: "Health Check Failed"
    commit id: "Automatic Rollback"
    checkout main
    merge rollback id: "Restore v1.0.1" tag: "rollback"
    commit id: "Back to Stable"
```

[↑ Back to Top](#-table-of-contents)

---

## 🐳 Docker Compose Stacks

### Two Independent Stacks

#### Stack 1: Main Application

| Property | Value |
|----------|-------|
| **Location** | `/root/docker-compose.yml` |
| **Systemd Service** | `thermalog.service` |
| **Network** | `thermalog_app-network` |
| **Bridge Type** | Bridge (isolated) |
| **Management** | `docker-compose` commands |

**Containers:**
- `nginx` - Reverse proxy (ports 80, 443)
- `thermalog-backend` - API server (port 3001)
- `thermalog-frontend` - Web UI (port 80 internal)
- `uptime-kuma` - Monitoring (port 3002)

**Quick Commands:**
```bash
# Start stack
docker-compose -f /root/docker-compose.yml up -d

# View logs
docker-compose -f /root/docker-compose.yml logs -f

# Restart single service
docker-compose -f /root/docker-compose.yml restart backend

# Stop stack
docker-compose -f /root/docker-compose.yml down
```

#### Stack 2: EMQX IoT Platform

| Property | Value |
|----------|-------|
| **Location** | `/root/emqx-platform/docker-compose.yml` |
| **Systemd Service** | `emqx-platform.service` |
| **Network** | `emqx-platform_iot-network` |
| **Bridge Type** | Bridge (isolated) |
| **Management Script** | `/root/emqx-platform/emqx-platform.sh` |

**Containers:**
- `emqx-platform` - MQTT broker (ports 8883, 8086, 18083)
- `emqx-provisioning` - Device API (port 3003)
- `iot-postgres` - TimescaleDB (port 5433)

**Quick Commands:**
```bash
# Start stack
cd /root/emqx-platform && docker-compose up -d

# View logs
cd /root/emqx-platform && docker-compose logs -f emqx-platform

# Access EMQX dashboard
curl http://localhost:18083

# Database backup
docker exec iot-postgres pg_dump -U emqx emqx_iot_platform > backup.sql
```

[↑ Back to Top](#-table-of-contents)

---

## 💻 Container Specifications

### Resource Allocations & Health Checks

| Container | CPU Limit | Memory Limit | Restart Policy | Health Check | Volume Mounts |
|-----------|-----------|--------------|----------------|--------------|---------------|
| **nginx** | - | - | unless-stopped | TCP :80 | `/etc/nginx/`, SSL certs |
| **thermalog-backend** | - | - | unless-stopped | HTTP :3001/health | App code, .env |
| **thermalog-frontend** | - | - | unless-stopped | HTTP :80 | Build output |
| **uptime-kuma** | - | - | unless-stopped | HTTP :3002 | `uptime-kuma-data` |
| **emqx-platform** | - | - | unless-stopped | TCP :8883, :18083 | `emqx-data`, `emqx-log` |
| **emqx-provisioning** | - | - | unless-stopped | HTTP :3003/health | App code, .env |
| **iot-postgres** | - | - | unless-stopped | pg_isready | `postgres-data` |

### Volume Details

```bash
# List all volumes
docker volume ls | grep -E "(thermalog|emqx|uptime|postgres)"

# Inspect volume
docker volume inspect uptime-kuma-data

# Backup volume
docker run --rm -v uptime-kuma-data:/data -v $(pwd):/backup ubuntu tar czf /backup/uptime-kuma-backup.tar.gz /data
```

[↑ Back to Top](#-table-of-contents)

---

## ⚙️ Systemd Services (Auto-Start)

### Boot Sequence

```mermaid
graph TD
    A[System Boot] --> B[docker.service starts]
    B --> C[thermalog.service]
    B --> D[emqx-platform.service]
    C --> E[thermalog-startup.service]
    D --> E
    E --> F{All Services<br/>Healthy?}
    F -->|Yes| G[Boot Complete ✅]
    F -->|No| H[Recovery Procedure]
    H --> I[Restart Failed Services]
    I --> F

    style F fill:#fd5,stroke:#a31
    style G fill:#5f5,stroke:#1a1
    style H fill:#f55,stroke:#a11
```

### Active Services

| Service | Type | Purpose | Start Order | Dependencies |
|---------|------|---------|-------------|--------------|
| `thermalog.service` | oneshot | Main app auto-start on boot | 2 | docker.service |
| `emqx-platform.service` | oneshot | EMQX platform auto-start on boot | 2 | docker.service |
| `thermalog-startup.service` | oneshot | Startup verification & recovery | 3 | thermalog.service, emqx-platform.service |
| `thermalog-shutdown.service` | oneshot | Graceful shutdown (DB checkpointing) | pre-shutdown | - |

✅ **All services: enabled and active**

### Service Management Commands

```bash
# Check service status
systemctl status thermalog.service
systemctl status emqx-platform.service

# View service logs
journalctl -u thermalog.service -f
journalctl -u thermalog-startup.service -n 100

# Restart services
sudo systemctl restart thermalog.service
sudo systemctl restart emqx-platform.service

# Disable auto-start (if needed)
sudo systemctl disable thermalog.service
```

[↑ Back to Top](#-table-of-contents)

---

## 🤖 Automation & Cron Jobs

### Scheduled Tasks (6 Jobs)

| Schedule | Task | Script | Log Location | Purpose |
|----------|------|--------|--------------|---------|
| **Every 2 minutes** | Uptime Kuma health monitoring | `uptime-kuma-alerts-improved.sh` | `/root/thermalog-ops/logs/monitoring/` | Monitor all services, send alerts on failure |
| **Every 5 minutes** | Auto-deployment | `auto-deploy.sh` | `/root/thermalog-ops/logs/deployment/` | Deploy GitHub changes automatically with rollback |
| **Every 12 hours** | Process cleanup | `cleanup_processes.sh` | `/root/thermalog-ops/logs/maintenance/` | Remove stale processes and zombie containers |
| **Daily @ 2:00 AM** | Docker cleanup | `docker-cleanup.sh` | `/root/thermalog-ops/logs/maintenance/` | Prune images, volumes, keep current + 3 backups |
| **Daily @ 3:00 AM** | MQTT database backup | `/root/mqtt-broker/scripts/backup.sh` | Database backup location | Backup PostgreSQL/TimescaleDB data |
| **3:15 AM & PM** | SSL certificate renewal | `ssl-renew-dual.sh` | `/root/thermalog-ops/logs/maintenance/` | Renew Let's Encrypt certs, reload nginx |

### View Cron Jobs

```bash
# List all cron jobs
crontab -l

# Edit cron jobs
crontab -e

# View cron logs
grep CRON /var/log/syslog | tail -20
```

[↑ Back to Top](#-table-of-contents)

---

## 📁 Log Organization & Rotation

### Centralized Log Structure

```
/root/thermalog-ops/logs/
├── deployment/
│   ├── auto-deploy-cron.log        (Auto-deployment activity)
│   ├── deployment.log              (Main deployment log)
│   ├── startup-thermalog.log       (Server boot verification)
│   └── failures/                   (Failed deployment logs)
│
├── maintenance/
│   ├── docker-cleanup-cron.log     (Docker cleanup @ 2 AM)
│   ├── process-cleanup-cron.log    (Process cleanup @ 12h)
│   └── ssl-renewal.log             (SSL renewal @ 3:15 AM/PM)
│
├── monitoring/
│   ├── uptime-alerts.log           (Uptime Kuma alerts @ 2 min)
│   └── monitoring-history.csv      (Historical monitoring data)
│
└── notifications/
    └── email-notifications.log     (Email notification activity)
```

### Log Rotation (Automatic)

| Log Type | Rotation | Retention | Compression | Max Size |
|----------|----------|-----------|-------------|----------|
| Monitoring | Size-based | 4 rotations | gzip | 10MB |
| Notifications | Weekly | 4 weeks | gzip | - |
| Deployment | Weekly | 8 weeks | gzip | - |
| Failure logs | Monthly | 6 months | gzip | - |

**Configuration:** `/etc/logrotate.d/thermalog`

### Log Viewing Commands

```bash
# View latest deployment log
tail -f /root/thermalog-ops/logs/deployment/auto-deploy-cron.log

# View last 100 monitoring alerts
tail -100 /root/thermalog-ops/logs/monitoring/uptime-alerts.log

# Search for errors in logs
grep -i error /root/thermalog-ops/logs/deployment/*.log

# View compressed old logs
zcat /root/thermalog-ops/logs/monitoring/uptime-alerts.log.1.gz | less
```

[↑ Back to Top](#-table-of-contents)

---

## 🔐 SSL/TLS Certificate Management

### Dual Certificate System

| Certificate Type | ECDSA (Primary) | RSA (Fallback) |
|------------------|-----------------|----------------|
| **Algorithm** | ECDSA P-256 | RSA 2048 |
| **Performance** | Faster (70% less CPU) | Compatible |
| **Browser Support** | Modern (Chrome, Firefox, Safari) | Legacy (IE, old Android) |
| **Key Size** | 256-bit | 2048-bit |
| **Signature Speed** | ~3x faster | Baseline |

### Automatic Renewal

- **Frequency:** Twice daily (3:15 AM & 3:15 PM)
- **Provider:** Let's Encrypt
- **Domain:** dashboard.thermalog.com.au
- **Auto-reload:** Nginx reloaded on successful renewal
- **Dry-run test:** `certbot renew --dry-run`
- **Expiry check:** `certbot certificates`

### Certificate Locations

```bash
# ECDSA Certificate
/etc/letsencrypt/live/dashboard.thermalog.com.au-0001/
├── fullchain.pem    # Certificate + Chain
├── privkey.pem      # Private Key
├── cert.pem         # Certificate Only
└── chain.pem        # Chain Only

# RSA Certificate
/etc/letsencrypt/live/dashboard.thermalog.com.au/
├── fullchain.pem
├── privkey.pem
├── cert.pem
└── chain.pem
```

### Manual Certificate Operations

```bash
# Check certificate expiry
openssl x509 -in /etc/letsencrypt/live/dashboard.thermalog.com.au/cert.pem -noout -dates

# Test renewal
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal

# Reload nginx after renewal
sudo docker exec nginx nginx -s reload

# View renewal hooks
ls -la /etc/letsencrypt/renewal-hooks/deploy/
```

[↑ Back to Top](#-table-of-contents)

---

## 🌐 Port Mapping

### External Ports (Firewall Rules Applied)

| Port | Service | Purpose | Protocol | TLS/SSL | Exposed To |
|------|---------|---------|----------|---------|------------|
| 22 | SSH | Server administration | TCP | Yes (SSH) | Admin IPs only |
| 80 | HTTP | Redirect to HTTPS | TCP | No (redirect) | Public |
| 443 | HTTPS | Web & API traffic | TCP | Yes (dual cert) | Public |
| 3002 | Uptime Kuma | Monitoring dashboard | TCP | No | Internal/VPN |
| 3003 | EMQX Provisioning | Device registration | TCP | HTTPS | IoT Devices |
| 5433 | PostgreSQL | Database access | TCP | No | Internal only |
| 8086 | WebSocket Secure | WSS MQTT | TCP/WS | Yes (TLS) | IoT Devices |
| 8883 | MQTTS | Secure MQTT | TCP | Yes (TLS required) | IoT Devices |
| 18083 | EMQX Dashboard | Admin interface | TCP | No | Internal/VPN |

### Internal Ports (Docker Networks Only)

| Port | Service | Container | Access | Used By |
|------|---------|-----------|--------|---------|
| 3001 | Backend API | thermalog-backend | app-network | nginx, frontend |
| 80 | Frontend | thermalog-frontend | app-network | nginx only |
| 1883 | MQTT (disabled) | emqx-platform | iot-network | DISABLED (security) |

### Firewall Rules

```bash
# View current firewall rules
sudo ufw status verbose

# Allow new port
sudo ufw allow 8883/tcp

# Block port
sudo ufw deny 1883/tcp

# View iptables rules
sudo iptables -L -n -v
```

[↑ Back to Top](#-table-of-contents)

---

## 🌐 Network Topology

### Docker Networks (Isolated)

#### emqx-platform_iot-network (IoT Stack)

**Network Type:** Bridge (isolated)
**Subnet:** Auto-assigned by Docker
**Driver:** bridge

**Containers:**
- `emqx-platform` (MQTT broker)
- `emqx-provisioning` (Device API)
- `iot-postgres` (TimescaleDB)

**External Access:** Via published ports 8883, 8086, 18083, 3003

#### thermalog_app-network (Main App Stack)

**Network Type:** Bridge (isolated)
**Subnet:** Auto-assigned by Docker
**Driver:** bridge

**Containers:**
- `nginx` (Reverse proxy)
- `thermalog-backend` (API server)
- `thermalog-frontend` (Web UI)
- `uptime-kuma` (Monitoring)

**External Access:** Via nginx (80, 443), Direct: 3002 (Uptime Kuma)

### Network Inspection

```bash
# List all networks
docker network ls

# Inspect network
docker network inspect emqx-platform_iot-network
docker network inspect thermalog_app-network

# View container IPs
docker network inspect emqx-platform_iot-network | jq '.[].Containers'

# Test connectivity between containers
docker exec emqx-provisioning ping iot-postgres
```

> **Security Note:** The two networks are completely isolated. Cross-stack communication happens via published ports only.

[↑ Back to Top](#-table-of-contents)

---

## 🔐 Security Features

### Transport Security ✅

- ✅ TLS-only MQTT connections (port 1883 disabled)
- ✅ HTTPS for all web traffic (dual ECDSA + RSA certificates)
- ✅ WebSocket Secure (WSS) for MQTT over websockets
- ✅ SSH key-based authentication only (password auth disabled)
- ✅ Perfect Forward Secrecy (PFS) enabled
- ✅ TLS 1.2+ only (TLS 1.0/1.1 disabled)

### Authentication ✅

- ✅ SHA256 password hashing for MQTT credentials
- ✅ HMAC device authentication for provisioning
- ✅ Per-device unique credentials
- ✅ Azure IoT Hub key-based authentication (legacy)
- ✅ JWT tokens for API authentication
- ✅ Strong password policies enforced

### Authorization ✅

- ✅ Topic-based ACL for MQTT (per-device permissions)
- ✅ Nginx rate limiting (10 req/s per IP)
- ✅ Firewall rules (ufw/iptables)
- ✅ Docker network isolation
- ✅ Role-based access control (RBAC)
- ✅ API endpoint authentication

### Monitoring & Auditing ✅

- ✅ Health checks every 2 minutes (Uptime Kuma)
- ✅ Automatic alerts on service failures
- ✅ Deployment verification and rollback
- ✅ Log rotation and archival
- ✅ Failed login attempt tracking
- ✅ Security event logging

### Security Checklist

```bash
# Verify SSH key-only authentication
sudo grep -i "PasswordAuthentication no" /etc/ssh/sshd_config

# Check firewall status
sudo ufw status verbose

# Verify TLS configuration
openssl s_client -connect dashboard.thermalog.com.au:443 -tls1_2

# Check for outdated packages
sudo apt list --upgradable

# Verify Docker security
docker info | grep -i security
```

[↑ Back to Top](#-table-of-contents)

---

## 🏥 Health Check Endpoints

### All Service Health Checks

| Service | Endpoint | Expected Response | Check Interval | Timeout |
|---------|----------|-------------------|----------------|---------|
| **Backend API** | `http://localhost:3001/health` | `{"status":"ok"}` | 30s | 10s |
| **Frontend** | `http://localhost:80` | HTTP 200 | 30s | 10s |
| **Nginx** | `http://localhost:80` | HTTP 200/301 | 10s | 5s |
| **EMQX Broker** | `http://localhost:18083` | HTTP 200 | 30s | 10s |
| **EMQX Provisioning** | `http://localhost:3003/health` | `{"status":"healthy"}` | 30s | 10s |
| **Uptime Kuma** | `http://localhost:3002` | HTTP 200 | 60s | 15s |
| **PostgreSQL** | `pg_isready -U emqx` | `accepting connections` | 30s | 10s |

### Health Check Commands

```bash
# Backend health check
curl http://localhost:3001/health

# EMQX broker status
curl http://localhost:18083/api/v5/status

# PostgreSQL health check
docker exec iot-postgres pg_isready -U emqx

# Full system health check
/root/thermalog-ops/scripts/monitoring/health-check.sh

# Check all containers
docker ps --filter "status=running" --format "table {{.Names}}\t{{.Status}}"
```

### Monitoring via Uptime Kuma

**Access:** http://dashboard.thermalog.com.au:3002

**Monitored Services:**
- Thermalog Frontend (HTTP)
- Thermalog Backend (HTTP)
- EMQX MQTT Broker (TCP port 8883)
- EMQX Provisioning API (HTTP)
- EMQX Dashboard (HTTP)
- PostgreSQL (TCP port 5433)

**Alert Configuration:**
- Check interval: 2 minutes
- Retries before alert: 3
- Notification methods: Email

[↑ Back to Top](#-table-of-contents)

---

## 📈 Performance Metrics & Thresholds

### Expected Response Times

| Service | Endpoint | Expected | Warning | Critical | Current |
|---------|----------|----------|---------|----------|---------|
| Frontend | `/` | < 200ms | > 500ms | > 1s | ~150ms |
| Backend API | `/api/devices` | < 100ms | > 300ms | > 500ms | ~80ms |
| EMQX Broker | MQTT Connect | < 50ms | > 100ms | > 200ms | ~30ms |
| Provisioning | `/provision` | < 200ms | > 500ms | > 1s | ~180ms |
| Database | Simple Query | < 10ms | > 50ms | > 100ms | ~5ms |

### Resource Utilization Thresholds

| Resource | Normal | Warning | Critical | Action |
|----------|--------|---------|----------|--------|
| **CPU Usage** | < 50% | 50-80% | > 80% | Scale or optimize |
| **Memory Usage** | < 60% | 60-85% | > 85% | Restart or scale |
| **Disk Usage** | < 70% | 70-85% | > 85% | Clean logs/images |
| **Disk I/O** | < 50% | 50-80% | > 80% | Optimize queries |
| **Network I/O** | < 60% | 60-85% | > 85% | Check for attacks |

### Monitoring Commands

```bash
# Check CPU usage
top -b -n 1 | head -20

# Memory usage
free -h

# Disk usage
df -h

# Docker stats (live)
docker stats

# PostgreSQL performance
docker exec iot-postgres psql -U emqx -c "SELECT * FROM pg_stat_activity;"

# EMQX metrics
curl http://localhost:18083/api/v5/metrics
```

### Capacity Planning

| Metric | Current | Max Capacity | Time to Max | Recommendation |
|--------|---------|--------------|-------------|----------------|
| MQTT Connections | ~50 | 10,000 | N/A | Monitor growth |
| Messages/sec | ~100 | 5,000 | N/A | Current adequate |
| Database Size | 2 GB | 50 GB | ~2 years | Automated cleanup |
| Docker Images | 15 GB | 80 GB | 6 months | Weekly cleanup active |

[↑ Back to Top](#-table-of-contents)

---

## 🔧 Environment Variables Reference

### Main Application (.env)

```bash
# Backend Configuration
NODE_ENV=production
PORT=3001
API_VERSION=v1

# Database
DATABASE_URL=postgresql://user:pass@host:5432/dbname

# Azure IoT Hub (Legacy)
AZURE_IOT_CONNECTION_STRING=HostName=...
AZURE_EVENT_HUB_CONNECTION_STRING=Endpoint=...

# Email Notifications
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=alerts@thermalog.com.au
SMTP_PASS=***
ALERT_EMAIL=admin@thermalog.com.au

# Security
JWT_SECRET=***
ENCRYPTION_KEY=***
```

### EMQX Platform (.env)

```bash
# PostgreSQL Configuration
POSTGRES_USER=emqx
POSTGRES_PASSWORD=***
POSTGRES_DB=emqx_iot_platform

# EMQX Configuration
EMQX_NAME=emqx-platform
EMQX_HOST=emqx-platform
EMQX_NODE__COOKIE=***

# Provisioning API
HMAC_SECRET_KEY=***
DEVICE_USERNAME_PREFIX=device_
DEFAULT_TOPIC_PREFIX=device/
```

### Environment Variable Security

```bash
# Never commit .env files
echo ".env" >> .gitignore

# Backup env vars securely
gpg --encrypt --recipient admin@thermalog.com.au .env > .env.gpg

# Restore env vars
gpg --decrypt .env.gpg > .env
```

[↑ Back to Top](#-table-of-contents)

---

## ⚡ Quick Commands Reference

### Docker Management

```bash
# View all running containers
docker ps

# View all containers (including stopped)
docker ps -a

# View container logs
docker logs -f <container_name>
docker logs --tail 100 thermalog-backend

# Restart container
docker restart <container_name>

# Execute command in container
docker exec -it <container_name> /bin/bash

# View container resources
docker stats

# Clean up
docker system prune -a --volumes  # DANGEROUS: removes everything
```

### Service Control

```bash
# Start/Stop/Restart services
sudo systemctl start thermalog.service
sudo systemctl stop thermalog.service
sudo systemctl restart thermalog.service

# View service status
sudo systemctl status thermalog.service

# View service logs
sudo journalctl -u thermalog.service -f
```

### Log Viewing

```bash
# Deployment logs
tail -f /root/thermalog-ops/logs/deployment/auto-deploy-cron.log

# Monitoring logs
tail -f /root/thermalog-ops/logs/monitoring/uptime-alerts.log

# Nginx access logs
docker logs -f nginx

# Backend application logs
docker logs -f thermalog-backend
```

### Database Operations

```bash
# Connect to PostgreSQL
docker exec -it iot-postgres psql -U emqx emqx_iot_platform

# Backup database
docker exec iot-postgres pg_dump -U emqx emqx_iot_platform > backup_$(date +%Y%m%d).sql

# Restore database
docker exec -i iot-postgres psql -U emqx emqx_iot_platform < backup.sql

# View database size
docker exec iot-postgres psql -U emqx -c "SELECT pg_size_pretty(pg_database_size('emqx_iot_platform'));"
```

### Deployment Commands

```bash
# Manual deployment
/root/auto-deploy.sh

# Check deployment status
tail -50 /root/thermalog-ops/logs/deployment/deployment.log

# Rollback (if auto-deploy fails)
cd /root && docker-compose down && docker-compose up -d
```

### Monitoring Commands

```bash
# Check all services health
/root/thermalog-ops/scripts/monitoring/uptime-kuma-alerts-improved.sh

# System resource usage
htop

# Network connections
netstat -tulpn | grep LISTEN
ss -tulpn | grep LISTEN

# Disk usage
du -sh /var/lib/docker/
df -h
```

[↑ Back to Top](#-table-of-contents)

---

## 💾 Backup & Restore Procedures

### Automated Backups

| What | When | Location | Retention | Method |
|------|------|----------|-----------|--------|
| PostgreSQL/TimescaleDB | Daily @ 3 AM | `/root/mqtt-broker/backups/` | 7 days | pg_dump |
| Docker Volumes | Weekly | `/root/backups/volumes/` | 4 weeks | tar |
| Configuration Files | On change | Git repository | Indefinite | Git |
| SSL Certificates | Auto by Let's Encrypt | `/etc/letsencrypt/` | N/A | Certbot |

### Manual Database Backup

```bash
# Full database backup
docker exec iot-postgres pg_dump -U emqx emqx_iot_platform > \
  /root/backups/postgres/emqx_$(date +%Y%m%d_%H%M%S).sql

# Backup with compression
docker exec iot-postgres pg_dump -U emqx emqx_iot_platform | \
  gzip > /root/backups/postgres/emqx_$(date +%Y%m%d_%H%M%S).sql.gz

# Backup specific table
docker exec iot-postgres pg_dump -U emqx -t telemetry_data emqx_iot_platform > \
  /root/backups/postgres/telemetry_$(date +%Y%m%d).sql
```

### Database Restore

```bash
# Restore from backup
docker exec -i iot-postgres psql -U emqx emqx_iot_platform < \
  /root/backups/postgres/emqx_20251004_030000.sql

# Restore compressed backup
gunzip -c /root/backups/postgres/emqx_20251004_030000.sql.gz | \
  docker exec -i iot-postgres psql -U emqx emqx_iot_platform

# Restore specific table
docker exec -i iot-postgres psql -U emqx emqx_iot_platform < \
  /root/backups/postgres/telemetry_20251004.sql
```

### Docker Volume Backup

```bash
# Backup Uptime Kuma data
docker run --rm \
  -v uptime-kuma-data:/data \
  -v /root/backups/volumes:/backup \
  ubuntu tar czf /backup/uptime-kuma_$(date +%Y%m%d).tar.gz /data

# Backup all volumes
for volume in $(docker volume ls -q | grep -E "(thermalog|emqx|uptime)"); do
  docker run --rm \
    -v $volume:/data \
    -v /root/backups/volumes:/backup \
    ubuntu tar czf /backup/${volume}_$(date +%Y%m%d).tar.gz /data
done
```

### Docker Volume Restore

```bash
# Restore Uptime Kuma data
docker run --rm \
  -v uptime-kuma-data:/data \
  -v /root/backups/volumes:/backup \
  ubuntu tar xzf /backup/uptime-kuma_20251004.tar.gz -C /
```

### Configuration Backup

```bash
# Backup all configuration files
tar czf /root/backups/config_$(date +%Y%m%d).tar.gz \
  /root/docker-compose.yml \
  /root/.env \
  /root/emqx-platform/ \
  /etc/nginx/ \
  /etc/systemd/system/thermalog* \
  /etc/letsencrypt/

# Restore configuration
tar xzf /root/backups/config_20251004.tar.gz -C /
```

### Full System Backup Strategy

```bash
#!/bin/bash
# /root/thermalog-ops/scripts/maintenance/full-backup.sh

BACKUP_DIR="/root/backups/full/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# 1. Stop services
docker-compose -f /root/docker-compose.yml down
cd /root/emqx-platform && docker-compose down

# 2. Backup databases
docker start iot-postgres
docker exec iot-postgres pg_dump -U emqx emqx_iot_platform > \
  $BACKUP_DIR/database.sql

# 3. Backup volumes
for volume in $(docker volume ls -q); do
  docker run --rm \
    -v $volume:/data \
    -v $BACKUP_DIR:/backup \
    ubuntu tar czf /backup/${volume}.tar.gz /data
done

# 4. Backup configurations
tar czf $BACKUP_DIR/config.tar.gz \
  /root/docker-compose.yml \
  /root/emqx-platform/ \
  /etc/nginx/ \
  /etc/systemd/system/

# 5. Restart services
docker-compose -f /root/docker-compose.yml up -d
cd /root/emqx-platform && docker-compose up -d

echo "Full backup completed: $BACKUP_DIR"
```

[↑ Back to Top](#-table-of-contents)

---

## 🚨 Disaster Recovery Plan

### Scenario 1: Single Container Failure

**Symptoms:** One container is unhealthy or stopped

```bash
# 1. Check container status
docker ps -a | grep <container_name>

# 2. View logs
docker logs --tail 100 <container_name>

# 3. Restart container
docker restart <container_name>

# 4. If restart fails, recreate
docker-compose -f /root/docker-compose.yml up -d --force-recreate <service_name>

# 5. Verify health
docker ps | grep <container_name>
curl http://localhost:<port>/health
```

### Scenario 2: Database Corruption

**Symptoms:** PostgreSQL errors, data inconsistency

```bash
# 1. Stop EMQX services
cd /root/emqx-platform && docker-compose stop emqx-platform emqx-provisioning

# 2. Create corrupted database backup (just in case)
docker exec iot-postgres pg_dump -U emqx emqx_iot_platform > \
  /root/backups/corrupted_$(date +%Y%m%d_%H%M%S).sql

# 3. Drop and recreate database
docker exec -it iot-postgres psql -U emqx -c "DROP DATABASE emqx_iot_platform;"
docker exec -it iot-postgres psql -U emqx -c "CREATE DATABASE emqx_iot_platform;"

# 4. Restore from latest backup
LATEST_BACKUP=$(ls -t /root/backups/postgres/*.sql | head -1)
docker exec -i iot-postgres psql -U emqx emqx_iot_platform < $LATEST_BACKUP

# 5. Restart services
cd /root/emqx-platform && docker-compose start emqx-platform emqx-provisioning

# 6. Verify
docker exec iot-postgres psql -U emqx emqx_iot_platform -c "SELECT COUNT(*) FROM device_credentials;"
```

### Scenario 3: Complete Server Failure

**Symptoms:** Server unreachable, hardware failure

**Recovery Steps:**

```bash
# On new server:

# 1. Install Docker & Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo apt install docker-compose-plugin

# 2. Clone repositories
git clone https://github.com/Thermalog/thermalog-infrastructure.git
git clone https://github.com/Thermalog/Thermalog-Backend.git
git clone https://github.com/Thermalog/Thermalog-frontend.git

# 3. Restore configuration backup
scp old-server:/root/backups/config_latest.tar.gz /root/
tar xzf /root/config_latest.tar.gz -C /

# 4. Restore database backup
scp old-server:/root/backups/postgres/latest.sql /root/
# Start PostgreSQL container
cd /root/emqx-platform && docker-compose up -d iot-postgres
# Wait for PostgreSQL to start
sleep 10
# Restore database
docker exec -i iot-postgres psql -U emqx emqx_iot_platform < /root/latest.sql

# 5. Restore Docker volumes
scp old-server:/root/backups/volumes/*.tar.gz /root/backups/volumes/
for backup in /root/backups/volumes/*.tar.gz; do
  volume=$(basename $backup .tar.gz)
  docker volume create $volume
  docker run --rm \
    -v $volume:/data \
    -v /root/backups/volumes:/backup \
    ubuntu tar xzf /backup/$(basename $backup) -C /
done

# 6. Setup systemd services
sudo systemctl enable thermalog.service
sudo systemctl enable emqx-platform.service
sudo systemctl enable thermalog-startup.service

# 7. Restore SSL certificates (if not using DNS challenge)
scp -r old-server:/etc/letsencrypt /etc/

# 8. Start all services
sudo systemctl start thermalog.service
sudo systemctl start emqx-platform.service

# 9. Verify all services
docker ps
curl http://localhost:3001/health
curl http://localhost:3003/health

# 10. Update DNS (if new IP)
# Point dashboard.thermalog.com.au to new server IP
```

### Scenario 4: SSL Certificate Issues

```bash
# Force renew certificates
sudo certbot renew --force-renewal

# If renewal fails, obtain new certificates
sudo certbot certonly --standalone \
  -d dashboard.thermalog.com.au \
  --key-type ecdsa \
  --email admin@thermalog.com.au

# Reload nginx
docker exec nginx nginx -s reload
```

### Scenario 5: Failed Auto-Deployment

**Symptoms:** Auto-deploy script failed, services unhealthy

```bash
# 1. Check deployment log
tail -100 /root/thermalog-ops/logs/deployment/auto-deploy-cron.log

# 2. Auto-rollback should have happened, verify
docker ps | grep thermalog-backend

# 3. If services still broken, manual rollback
cd /root
git log --oneline -10
git reset --hard <last_working_commit>

# 4. Rebuild and restart
docker-compose down
docker-compose build --no-cache
docker-compose up -d

# 5. Verify
curl http://localhost:3001/health
```

### Emergency Contacts

| Issue | Contact | Response Time |
|-------|---------|---------------|
| Infrastructure | DevOps Team | 15 minutes |
| Database | Database Admin | 30 minutes |
| Security | Security Team | Immediate |
| General | On-call Engineer | 30 minutes |

[↑ Back to Top](#-table-of-contents)

---

## 🔍 Troubleshooting Guide

### Common Issues & Solutions

#### Issue 1: Container Won't Start

**Symptoms:**
- Container in "Restarting" state
- Container exits immediately after starting

**Diagnosis:**
```bash
# Check container logs
docker logs <container_name>

# Check container inspect
docker inspect <container_name>

# Check if port is already in use
sudo netstat -tulpn | grep <port>
```

**Solutions:**
```bash
# Solution 1: Port conflict
# Kill process using the port
sudo kill -9 $(sudo lsof -t -i:<port>)

# Solution 2: Corrupt volume
docker volume rm <volume_name>
docker-compose up -d --force-recreate

# Solution 3: Missing environment variables
# Check .env file exists and is correct
cat /root/.env
cat /root/emqx-platform/.env
```

#### Issue 2: High CPU Usage

**Symptoms:**
- Server slow
- CPU usage > 80%

**Diagnosis:**
```bash
# Check which container is using CPU
docker stats

# Check processes inside container
docker exec <container_name> top
```

**Solutions:**
```bash
# Solution 1: Restart high-CPU container
docker restart <container_name>

# Solution 2: Check for infinite loops in logs
docker logs <container_name> | grep -i error

# Solution 3: Temporary CPU limit
docker update --cpus="1.5" <container_name>
```

#### Issue 3: Database Connection Errors

**Symptoms:**
- "Connection refused" errors
- "Too many connections" errors

**Diagnosis:**
```bash
# Check PostgreSQL is running
docker ps | grep postgres

# Check connection
docker exec iot-postgres psql -U emqx -c "SELECT 1;"

# Check active connections
docker exec iot-postgres psql -U emqx -c "SELECT count(*) FROM pg_stat_activity;"
```

**Solutions:**
```bash
# Solution 1: Restart PostgreSQL
docker restart iot-postgres

# Solution 2: Increase max connections
docker exec -it iot-postgres psql -U emqx -c "ALTER SYSTEM SET max_connections = 200;"
docker restart iot-postgres

# Solution 3: Kill idle connections
docker exec iot-postgres psql -U emqx -c "
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE state = 'idle' AND query_start < NOW() - INTERVAL '1 hour';
"
```

#### Issue 4: MQTT Connection Failures

**Symptoms:**
- Devices can't connect to MQTT
- "Connection refused" on port 8883

**Diagnosis:**
```bash
# Check EMQX is running
docker ps | grep emqx-platform

# Check EMQX dashboard
curl http://localhost:18083

# Test MQTT connection
mosquitto_pub -h localhost -p 8883 --cafile /etc/ssl/certs/ca-certificates.crt -t test -m "test" -u device_test -P testpass
```

**Solutions:**
```bash
# Solution 1: Restart EMQX
docker restart emqx-platform

# Solution 2: Check EMQX logs
docker logs emqx-platform | tail -100

# Solution 3: Verify credentials in database
docker exec iot-postgres psql -U emqx emqx_iot_platform -c "SELECT * FROM device_credentials LIMIT 5;"
```

#### Issue 5: SSL Certificate Renewal Failed

**Symptoms:**
- Certificate expiry warnings
- HTTPS not working

**Diagnosis:**
```bash
# Check certificate expiry
certbot certificates

# Check renewal logs
tail -100 /root/thermalog-ops/logs/maintenance/ssl-renewal.log
```

**Solutions:**
```bash
# Solution 1: Manual renewal
sudo certbot renew --force-renewal

# Solution 2: Stop nginx temporarily for standalone renewal
docker stop nginx
sudo certbot renew --standalone
docker start nginx

# Solution 3: Check DNS is pointing correctly
nslookup dashboard.thermalog.com.au
```

#### Issue 6: Disk Space Full

**Symptoms:**
- "No space left on device" errors
- Server performance degraded

**Diagnosis:**
```bash
# Check disk usage
df -h

# Find large files
du -sh /var/lib/docker/* | sort -rh | head -10
du -sh /root/thermalog-ops/logs/* | sort -rh
```

**Solutions:**
```bash
# Solution 1: Clean Docker resources
docker system prune -a --volumes  # CAREFUL!

# Solution 2: Clean old logs
find /root/thermalog-ops/logs/ -name "*.log.*" -mtime +30 -delete

# Solution 3: Clean old Docker images
docker image prune -a --filter "until=720h"

# Solution 4: Rotate logs manually
sudo logrotate -f /etc/logrotate.d/thermalog
```

### Debug Mode

```bash
# Enable debug logging for backend
docker exec thermalog-backend sh -c "export DEBUG=* && npm start"

# Enable debug logging for EMQX
docker exec emqx-platform emqx_ctl log set-level debug

# Disable debug logging
docker exec emqx-platform emqx_ctl log set-level info
```

[↑ Back to Top](#-table-of-contents)

---

## 📅 Maintenance Calendar

### Daily Tasks (Automated)

| Time | Task | Duration | Impact |
|------|------|----------|--------|
| 02:00 AM | Docker cleanup | ~10 min | Low |
| 03:00 AM | Database backup | ~15 min | Low |
| 03:15 AM | SSL renewal check | ~5 min | None |
| 03:15 PM | SSL renewal check | ~5 min | None |

### Recurring Tasks

| Frequency | Task | What | Why |
|-----------|------|------|-----|
| **Every 2 minutes** | Health monitoring | Check all services | Early failure detection |
| **Every 5 minutes** | Auto-deployment | Deploy GitHub changes | Zero-downtime updates |
| **Every 12 hours** | Process cleanup | Remove stale processes | Resource optimization |
| **Weekly** | Log review | Review error logs | Proactive issue detection |
| **Monthly** | Security updates | Update packages | Security patches |
| **Quarterly** | Backup testing | Restore from backup | Verify backup integrity |

### Visual Calendar

```
┌─────────────────────── 24-Hour Timeline ───────────────────────┐
│                                                                 │
│ 00:00 ────────────────────────────────────────────────── 00:00 │
│   │                                                         │   │
│ 02:00 ───[Docker Cleanup]────────────────────────────── 02:00 │
│   │                                                         │   │
│ 03:00 ───[DB Backup]──[SSL Check]─────────────────────── 03:00 │
│   │                                                         │   │
│ 12:00 ───[Process Cleanup]──────────────────────────────── 12:00 │
│   │                                                         │   │
│ 15:00 ───────────[SSL Check]────────────────────────────── 15:00 │
│   │                                                         │   │
│ 00:00 ───[Process Cleanup]──────────────────────────────── 00:00 │
│                                                                 │
│ Continuous: Health Checks (every 2 min)                       │
│ Continuous: Auto-Deploy (every 5 min)                         │
└─────────────────────────────────────────────────────────────────┘
```

[↑ Back to Top](#-table-of-contents)

---

## 📦 Dependencies & Versions

### Operating System

| Component | Version | Notes |
|-----------|---------|-------|
| **OS** | Ubuntu 22.04.3 LTS (Jammy) | Base OS |
| **Kernel** | Linux 5.15.0-156-generic | |
| **Architecture** | x86_64 | |

### Docker Stack

| Component | Version | Notes |
|-----------|---------|-------|
| **Docker Engine** | 24.0+ | Container runtime |
| **Docker Compose** | 2.20+ | Multi-container orchestration |

### Main Application Stack

| Component | Version | Repository |
|-----------|---------|------------|
| **Node.js** | 20.x LTS | Backend runtime |
| **Nginx** | 1.25+ (Alpine) | Reverse proxy |
| **React** | 18.x | Frontend framework |
| **Next.js** | 13.x | Frontend SSR |
| **Uptime Kuma** | 1.23+ | Monitoring |

### EMQX IoT Platform Stack

| Component | Version | Notes |
|-----------|---------|-------|
| **EMQX Broker** | 5.8.8 | MQTT broker |
| **PostgreSQL** | 15 | Database |
| **TimescaleDB** | 2.x | Time-series extension |
| **Node.js** | 20.x LTS | Provisioning API |

### Cloud Services

| Service | Provider | Purpose |
|---------|----------|---------|
| **Azure IoT Hub** | Microsoft Azure | Legacy device connectivity |
| **Let's Encrypt** | ISRG | SSL/TLS certificates |
| **DigitalOcean Droplet** | DigitalOcean | Hosting infrastructure |

### System Tools

| Tool | Version | Purpose |
|------|---------|---------|
| **Git** | 2.34+ | Version control |
| **certbot** | 2.x | SSL certificate management |
| **curl** | 7.81+ | HTTP client |
| **jq** | 1.6 | JSON processor |
| **glow** | 1.5.1 | Markdown viewer |

### Compatibility Matrix

```
┌───────────────────────────────────────────────────────────┐
│                  Component Compatibility                  │
├───────────────────────────────────────────────────────────┤
│                                                           │
│  Node.js 20.x  ──┬──→  Backend API ───┐                 │
│                  └──→  Provisioning API│                 │
│                                         ├──→ PostgreSQL 15│
│  EMQX 5.8.8 ────────→  TimescaleDB ────┘                 │
│                                                           │
│  React 18 + Next.js 13  ──→  Frontend                    │
│                                                           │
│  Nginx 1.25  ──→  SSL Termination (ECDSA + RSA)         │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

### Version Check Commands

```bash
# Docker versions
docker --version
docker-compose --version

# Node.js
node --version

# PostgreSQL
docker exec iot-postgres psql --version

# EMQX
docker exec emqx-platform emqx version

# Nginx
docker exec nginx nginx -v

# System
lsb_release -a
uname -r
```

[↑ Back to Top](#-table-of-contents)

---

## ✅ System Status

### Production Services (7 containers)

**Main Application Stack:**
- ✅ `nginx` - Running (4+ days) - Healthy
- ✅ `thermalog-backend` - Running (13+ hours) - Healthy
- ✅ `thermalog-frontend` - Running (2+ days) - Healthy
- ✅ `uptime-kuma` - Running (6+ days) - Healthy

**EMQX IoT Platform Stack:**
- ✅ `emqx-platform` - Running - Healthy
- ✅ `emqx-provisioning` - Running - Healthy
- ✅ `iot-postgres` - Running - Healthy

### Systemd Services (4 enabled)

- ✅ `thermalog.service` - Active (exited)
- ✅ `emqx-platform.service` - Active (exited)
- ✅ `thermalog-startup.service` - Active (exited)
- ✅ `thermalog-shutdown.service` - Loaded

### Automation (6 cron jobs)

- ✅ Uptime monitoring (every 2 min) - Active
- ✅ Auto-deployment (every 5 min) - Active
- ✅ Process cleanup (every 12 hours) - Active
- ✅ Docker cleanup (daily @ 2 AM) - Active
- ✅ MQTT backup (daily @ 3 AM) - Active
- ✅ SSL renewal (twice daily @ 3:15 AM/PM) - Active

### Cloud Services

- ✅ Azure IoT Hub (ThermalogData) - Active
- ✅ Azure IoT Hub (tasmotaIOTHub) - Active
- ✅ Let's Encrypt SSL (ECDSA + RSA) - Valid

### Database

- ✅ PostgreSQL/TimescaleDB - Healthy
- ✅ Backup schedule - Daily (3 AM)
- 📊 Database size: ~2 GB
- 📊 Active connections: ~5-10

### System Resources

```bash
# Quick status check
$ docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# System load
$ uptime
 02:30:15 up 15 days,  6:42,  1 user,  load average: 0.24, 0.31, 0.28

# Disk usage
$ df -h /
Filesystem      Size  Used Avail Use% Mounted on
/dev/vda1        80G   35G   45G  44% /

# Memory usage
$ free -h
              total        used        free      shared  buff/cache   available
Mem:          4.0Gi       2.1Gi       0.8Gi        15Mi       1.1Gi       1.7Gi
```

[↑ Back to Top](#-table-of-contents)

---

## 📚 Documentation & Resources

### Root-Level Documentation

- `/root/README.md` - Quick reference guide
- `/root/SERVER_ARCHITECTURE_OVERVIEW.md` - Complete architecture details
- `/root/DOCKER-COMPOSE-CONFIG.md` - Docker configuration explained
- `/root/ARCHITECTURE_DIAGRAM.txt` - ASCII diagram (terminal friendly)
- `/root/ARCHITECTURE_DIAGRAM.md` - This document (rich markdown)

### EMQX IoT Platform

- `/root/emqx-platform/README.md` - EMQX platform guide
- `/root/emqx-platform/DEBUG_VIEWER_SETUP.md` - Debugging guide
- `/root/emqx-platform/docker-compose.yml` - Stack configuration

### Infrastructure Documentation

- `/root/thermalog-infrastructure/docs/AUTOMATED_DEPLOYMENT.md` - Auto-deploy details
- `/root/thermalog-infrastructure/docs/SSL_RENEWAL.md` - SSL management
- `/root/thermalog-infrastructure/docs/SERVER_RESTART_RESILIENCE.md` - Startup procedures
- `/root/thermalog-infrastructure/docs/MONITORING.md` - Monitoring setup

### GitHub Repositories

- **Infrastructure:** [thermalog-infrastructure](https://github.com/Thermalog/thermalog-infrastructure)
- **Backend:** [Thermalog-Backend](https://github.com/Thermalog/Thermalog-Backend)
- **Frontend:** [Thermalog-frontend](https://github.com/Thermalog/Thermalog-frontend)

### External Resources

- [EMQX Documentation](https://docs.emqx.com/en/emqx/v5.8/)
- [Docker Documentation](https://docs.docker.com/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/15/)
- [TimescaleDB Documentation](https://docs.timescale.com/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)

### Quick Links

- 🌐 **Production Dashboard:** https://dashboard.thermalog.com.au
- 📊 **Uptime Monitoring:** http://dashboard.thermalog.com.au:3002
- 🔧 **EMQX Dashboard:** http://localhost:18083 (internal only)
- 📖 **API Documentation:** https://dashboard.thermalog.com.au/api/docs

[↑ Back to Top](#-table-of-contents)

---

## 🎯 Operational Highlights

### Key Features

#### 🚀 Zero Downtime Deployment
- Auto-deployment every 5 minutes from GitHub
- Automatic rollback on failure
- Health verification before completing deployment
- Maintains 99.9% uptime

#### 🔄 Self-Healing Infrastructure
- Automatic service recovery on boot
- Health monitoring and alerts every 2 minutes
- Graceful shutdown with database checkpointing
- Systemd-based service management

#### 🤖 Maintenance-Free Operations
- Automatic SSL renewal twice daily
- Docker cleanup (keeps current + 3 backups)
- Log rotation (prevents disk space issues)
- Process cleanup every 12 hours
- Daily database backups

#### 🌐 Dual IoT Platform Support
- Self-hosted EMQX for new devices (full control)
- Azure IoT Hub for legacy devices (compatibility)
- Seamless integration between both platforms
- Scalable to 10,000+ concurrent MQTT connections

#### 🔐 Production-Ready Security
- TLS/SSL everywhere (dual certificate support)
- Per-device authentication and authorization
- Network isolation between stacks
- Regular security updates via auto-deployment
- Failed login attempt tracking

#### 📊 Comprehensive Monitoring
- Real-time health checks
- Email alerts on failures
- Performance metrics tracking
- Resource utilization monitoring
- Centralized logging

---

## 💡 Summary

> **This infrastructure is designed to be reliable, self-healing, and maintenance-free.**
>
> **Built for production. Optimized for uptime. Ready for scale.**

### Architecture Strengths

✅ **Resilient** - Automatic recovery from failures
✅ **Scalable** - Can handle 10,000+ IoT devices
✅ **Secure** - Multiple layers of security
✅ **Observable** - Comprehensive monitoring and logging
✅ **Maintainable** - Automated maintenance tasks
✅ **Documented** - Extensive documentation and runbooks

### Quick Health Check

```bash
# Run full system health check
/root/thermalog-ops/scripts/monitoring/uptime-kuma-alerts-improved.sh

# Expected output: All services healthy ✅
```

---

**Document Version:** 2.0
**Last Updated:** October 4, 2025
**Maintained By:** Thermalog DevOps Team
**Review Schedule:** Monthly

[↑ Back to Top](#-table-of-contents)

---

*This document is automatically synced with the production environment. For updates, modify `/root/ARCHITECTURE_DIAGRAM.md` and commit to version control.*
