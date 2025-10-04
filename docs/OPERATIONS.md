# Operational Quick Reference

Common commands and troubleshooting for daily operations.

## Health Checks

```bash
# Quick status check
curl http://localhost:3001/api/health
docker ps
systemctl status thermalog emqx-platform

# View all containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

## Common Tasks

### Manual Deployment
```bash
/root/thermalog-ops/scripts/deployment/auto-deploy.sh
```

### View Logs
```bash
# Application logs
docker logs thermalog-backend -f
docker logs thermalog-frontend -f
docker logs nginx -f

# EMQX logs
docker logs emqx -f

# Deployment logs
tail -f /root/thermalog-ops/logs/deployment/auto-deploy-cron.log

# SSL renewal logs
tail -f /root/thermalog-ops/logs/maintenance/ssl-renewal.log

# All recent activity
tail -f /root/thermalog-ops/logs/**/*.log
```

### Docker Management

**Main Application:**
```bash
cd /root/thermalog-ops
docker compose -f config/docker-compose.yml ps
docker compose -f config/docker-compose.yml restart backend
docker compose -f config/docker-compose.yml logs -f
```

**EMQX Platform:**
```bash
cd /root/emqx-platform
docker compose ps
docker compose logs -f emqx
docker compose restart
```

**Cleanup:**
```bash
# Manual cleanup
/root/thermalog-ops/scripts/maintenance/docker-cleanup.sh

# Or direct
docker system prune -a
```

### SSL Management
```bash
# Check expiry
certbot certificates

# Test renewal
certbot renew --dry-run

# Manual renewal (dual certificates)
/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh

# Verify HTTPS
curl -I https://dashboard.thermalog.com.au
```

### System Recovery
```bash
# Restart services
systemctl restart thermalog
systemctl restart emqx-platform

# Full verification
/root/thermalog-ops/scripts/deployment/startup-thermalog.sh

# Check auto-start status
systemctl is-enabled thermalog emqx-platform
```

## Troubleshooting

### Application Down
```bash
# 1. Check containers
docker ps

# 2. Check backend
curl http://localhost:3001/api/health

# 3. View errors
docker logs thermalog-backend --tail=100 | grep -i error

# 4. Restart
docker compose -f /root/thermalog-ops/config/docker-compose.yml restart
```

### SSL Issues
```bash
# 1. Check status
certbot certificates

# 2. Test nginx config
docker exec nginx nginx -t

# 3. Force renewal
/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh

# 4. Verify both certificates
ls -lh /root/Config/nginx/*.pem
```

### EMQX Platform Issues
```bash
# 1. Check EMQX status
docker exec emqx emqx ctl status

# 2. Check database
docker exec iot-postgres pg_isready -U iotadmin

# 3. View EMQX logs
docker logs emqx --tail=100

# 4. Restart platform
systemctl restart emqx-platform
```

### Disk Space Issues
```bash
# 1. Check disk
df -h

# 2. Check Docker usage
docker system df

# 3. Clean up
/root/thermalog-ops/scripts/maintenance/docker-cleanup.sh
docker system prune -a
```

### After Server Restart
```bash
# Systemd handles restart automatically, but verify:
systemctl status thermalog emqx-platform
docker ps
crontab -l  # Verify cron jobs active
```

## Automation Schedule

| Frequency | Task | Script |
|-----------|------|--------|
| Every 2 min | Health monitoring | `uptime-kuma-alerts-improved.sh` |
| Every 5 min | Auto-deployment | `auto-deploy.sh` |
| Every 12h | Process cleanup | `cleanup_processes.sh` |
| Daily 2 AM UTC | Docker cleanup | `docker-cleanup.sh` |
| Twice daily 3:15 AM/PM UTC | SSL renewal | `ssl-renew-dual.sh` |
| Daily 3 AM Sydney | Backup | `backup.sh` |
| Weekly Sunday 4 AM Sydney | Backup verify | `verify-latest-backup.sh` |

View active cron jobs:
```bash
crontab -l
```

## Log Locations

| Type | Location |
|------|----------|
| Deployment | `/root/thermalog-ops/logs/deployment/` |
| Maintenance | `/root/thermalog-ops/logs/maintenance/` |
| Monitoring | `/root/thermalog-ops/logs/monitoring/` |
| Backups | `/var/backups/thermalog/` |

## Access Points

### Public
- Frontend: https://dashboard.thermalog.com.au
- Uptime Kuma: http://[server-ip]:3002

### Internal
- Backend API: http://localhost:3001/api/*
- Backend Health: http://localhost:3001/api/health
- EMQX Dashboard: http://localhost:18083
- EMQX Provisioning: http://localhost:3003

### Ports
- 80/443: Nginx (HTTP/HTTPS)
- 3001: Backend API
- 3002: Uptime Kuma
- 3003: EMQX Provisioning
- 5433: PostgreSQL/TimescaleDB
- 8883: MQTTS (TLS only)
- 18083: EMQX Dashboard

## Emergency Procedures

### Complete Reset
```bash
systemctl stop thermalog emqx-platform
systemctl start thermalog emqx-platform
/root/thermalog-ops/scripts/deployment/startup-thermalog.sh
```

### Rollback Deployment
```bash
docker images | grep backup
docker tag root-thermalog-backend:backup-YYYYMMDD root-thermalog-backend:latest
docker compose -f /root/thermalog-ops/config/docker-compose.yml up -d thermalog-backend
```

### Disable Automation
```bash
# Edit crontab and comment out lines with #
crontab -e
```

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture and diagrams
- [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md) - Recovery procedures
- [troubleshooting.md](troubleshooting.md) - Detailed troubleshooting
- [MONITORING.md](MONITORING.md) - Monitoring setup
- [BACKUP_DOCUMENTATION.md](../BACKUP_DOCUMENTATION.md) - Backup system

---

**Note**: This server is designed to be self-managing. Most tasks run automatically via cron and systemd.
