# Thermalog Monitoring System

This document describes the comprehensive monitoring and crash reporting system implemented for Thermalog services.

## Overview

The monitoring system uses **Uptime Kuma** for real-time service monitoring combined with **SendGrid API** for email notifications. It provides 24/7 monitoring with instant alerts when services go down or recover.

## Components

### 1. Uptime Kuma Dashboard
- **URL:** `http://SERVER_IP:3002` or `https://monitoring.thermalog.com.au`
- **Purpose:** Web-based monitoring dashboard
- **Features:** Real-time status, charts, history, maintenance windows

### 2. Automated Email Alerts
- **Script:** `/root/uptime-kuma-alerts.sh`
- **Frequency:** Every 2 minutes via cron
- **Recipients:** Multiple email addresses via SendGrid API
- **Alert Types:** DOWN, UP, PENDING status changes

### 3. Monitored Services
- **Backend Service** (Port 3001 check)
- **Frontend Service** (Port 80 check)
- **Nginx Proxy** (Port 80 check)
- **Backend API Health** (HTTP health endpoint)
- **Frontend Dashboard** (HTTPS external check)

## Setup Instructions

### Initial Deployment
1. Deploy the updated `docker-compose.yml` with Uptime Kuma service
2. Configure nginx with monitoring routes
3. Set up the monitoring alert script
4. Configure cron job for automated checking

### First-Time Configuration
1. Access Uptime Kuma dashboard: `http://SERVER_IP:3002`
2. Create admin account (first user becomes admin)
3. Monitors are automatically configured via database
4. Email notifications work via existing SendGrid integration

### Email Configuration
The system uses the existing SendGrid API configuration from `auto-deploy.sh`:
- **API Key:** From existing deployment system
- **Recipients:** `abid148@gmail.com`, `work.alishan@gmail.com`, `tahahanif24@gmail.com`
- **Method:** SendGrid HTTP API (not SMTP)

## Files Structure

```
/root/
├── docker-compose.yml          # Updated with Uptime Kuma service
├── uptime-kuma-alerts.sh      # Main monitoring script
└── nginx/default.conf         # Updated with monitoring routes

/root/thermalog-infrastructure/
├── docker/docker-compose.yml  # Infrastructure docker-compose
├── scripts/uptime-kuma-alerts.sh # Monitoring script backup
├── nginx/default.conf         # Nginx configuration
└── docs/MONITORING.md         # This documentation
```

## Cron Configuration

The monitoring script runs every 2 minutes:
```bash
*/2 * * * * /root/uptime-kuma-alerts.sh >> /root/uptime-alerts.log 2>&1
```

## Alert Examples

### DOWN Alert Email:
```
Subject: 🚨 Thermalog Monitor Alert: Backend Service FAILED

THERMALOG MONITORING ALERT

🖥️  Monitor: Backend Service (port)
📊 Status Change: UP → DOWN
⏰ Time: 2025-09-15 15:01:36.140
💬 Message: Request timeout

🔍 MONITOR DETAILS:
• Monitor ID: 4
• Type: port
• Previous Status: UP
• Current Status: DOWN

🏥 SYSTEM STATUS CHECK:
[Container status listing]

📊 QUICK DIAGNOSTICS:
• Backend Health: ❌ Unreachable
• Frontend: ✅ Reachable
• Dashboard: ✅ Reachable
```

### RECOVERY Alert Email:
```
Subject: ✅ Thermalog Monitor Alert: Backend Service RECOVERED

[Similar format with recovery details]
```

## Monitoring Dashboard Features

- **Real-time Status:** Live view of all services
- **Historical Data:** Charts showing uptime/downtime history
- **Response Times:** Performance monitoring
- **Maintenance Windows:** Schedule planned downtime
- **Status Page:** Public status page option
- **Multiple Notifications:** Email, Slack, Discord support

## Troubleshooting

### Check Service Status
```bash
# View container status
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check monitoring logs
tail -f /root/uptime-alerts.log

# Check Uptime Kuma logs
docker logs uptime-kuma --tail=50
```

### Monitor Database Access
```bash
# Check configured monitors
docker exec uptime-kuma sqlite3 /app/data/kuma.db "SELECT id, name, type, active FROM monitor;"

# Check recent heartbeats
docker exec uptime-kuma sqlite3 /app/data/kuma.db "SELECT m.name, h.status, h.time FROM monitor m LEFT JOIN heartbeat h ON m.id = h.monitor_id WHERE h.time >= datetime('now', '-1 hour') ORDER BY h.time DESC LIMIT 10;"
```

### Manual Testing
```bash
# Test alert system
docker stop thermalog-backend
# Wait for alert email
docker start thermalog-backend
# Wait for recovery email
```

## Integration with Existing Systems

The monitoring system integrates seamlessly with existing Thermalog infrastructure:

- **Auto-Deploy System:** Continues to work independently
- **SendGrid Configuration:** Reuses existing API key and settings
- **Email Recipients:** Uses same contact list
- **Cron Jobs:** Adds monitoring without conflicts
- **Docker Network:** Uses existing app-network
- **SSL Certificates:** Shares nginx SSL configuration

## Security Considerations

- **Dashboard Access:** Password-protected admin interface
- **Network Access:** Monitoring runs on internal Docker network
- **Email Security:** Uses authenticated SendGrid API
- **Database:** SQLite database with container isolation
- **Firewall:** Consider restricting port 3002 access if needed

## Maintenance

### Updates
```bash
# Update Uptime Kuma
docker compose pull uptime-kuma
docker compose up -d uptime-kuma
```

### Backup
- **Configuration:** Stored in Docker volume `uptime-kuma-data`
- **Database:** `/var/lib/docker/volumes/root_uptime-kuma-data/_data/kuma.db`
- **Scripts:** Backed up in infrastructure repository

### Log Rotation
```bash
# Rotate monitoring logs
logrotate /root/uptime-alerts.log
```

## Performance Impact

- **CPU Usage:** Minimal (~0.1% average)
- **Memory Usage:** ~50MB for Uptime Kuma container
- **Network Traffic:** Lightweight API calls every 2 minutes
- **Disk Space:** Log files and SQLite database (~10-50MB)

## Support

For issues with the monitoring system:

1. Check the troubleshooting section above
2. Review container logs and alert logs
3. Verify SendGrid API key is valid
4. Test individual components manually
5. Check cron job execution

The monitoring system is designed to be resilient and self-healing, with comprehensive logging for debugging any issues.