# Server Restart Resilience

## Overview

Thermalog infrastructure is designed to automatically recover from server restarts with zero manual intervention. This includes Docker containers, automated deployments, SSL certificates, and all monitoring services.

## Auto-Start Components

### System Services (systemd)
All critical services are configured to start automatically on boot:

```bash
# Check service auto-start status
systemctl list-unit-files | grep enabled

# Key services:
- docker.service (enabled)      # Docker daemon
- cron.service (enabled)        # Cron scheduler  
- thermalog.service (enabled)   # Main application stack
- thermalog-startup.service (enabled) # Startup verification
```

### Docker Containers
All containers have restart policies configured:

```yaml
# docker-compose.yml
services:
  thermalog-backend:
    restart: always
  
  thermalog-frontend:
    restart: always
    
  nginx:
    restart: always
```

### Cron Jobs
All automation continues after reboot:

```bash
# Cron jobs that survive restart:
*/5 * * * * /root/auto-deploy.sh              # Auto-deployment
0 2 * * * /root/docker-cleanup.sh             # Docker cleanup
@reboot sleep 60 && /root/startup-thermalog.sh # Startup verification
15 3,15 * * * /root/ssl-renew.sh              # SSL renewal
```

## Multi-Layer Recovery System

### Layer 1: Docker Restart Policies
- **Policy**: `restart: always`
- **Behavior**: Containers automatically restart if they exit
- **Coverage**: All application containers

### Layer 2: Systemd Services
- **thermalog.service**: Starts Docker Compose stack
- **thermalog-startup.service**: Verifies and recovers services
- **Dependencies**: Services start in correct order

### Layer 3: Cron @reboot
- **Backup mechanism**: Runs startup script after boot
- **Delay**: 60-second delay to allow system startup
- **Verification**: Checks and recovers any issues

### Layer 4: Health Monitoring
- **Continuous monitoring**: Every 5 minutes via cron
- **Database verification**: Health checks include DB connectivity
- **Automatic recovery**: Failed services trigger recovery

## Installation

### 1. Deploy Systemd Services
```bash
# Copy service files
sudo cp configs/systemd/thermalog.service /etc/systemd/system/
sudo cp configs/systemd/thermalog-startup.service /etc/systemd/system/

# Enable services
sudo systemctl daemon-reload
sudo systemctl enable thermalog.service
sudo systemctl enable thermalog-startup.service
```

### 2. Deploy Startup Script
```bash
# Copy startup verification script
cp scripts/startup-thermalog.sh /root/
chmod +x /root/startup-thermalog.sh
```

### 3. Configure Cron Jobs
```bash
# Add @reboot job to crontab
echo "@reboot sleep 60 && /root/startup-thermalog.sh >> /root/startup-thermalog.log 2>&1" >> /tmp/cron_reboot
crontab /tmp/cron_reboot
rm /tmp/cron_reboot
```

## Boot Sequence

### Automatic Boot Process
1. **System boots** → systemd starts enabled services
2. **Docker starts** → Containers with restart policies start
3. **Thermalog service** → Runs `docker compose up -d`
4. **Startup verification** → Checks health and recovers issues
5. **Cron starts** → Resumes automated monitoring
6. **Health monitoring** → Continuous 5-minute health checks

### Expected Timeline
- **0-30s**: System boot, basic services start
- **30-60s**: Docker daemon ready, containers starting
- **60-90s**: Application stack fully operational
- **90s+**: Health monitoring active, automation resumed

## Systemd Service Files

### thermalog.service
```ini
[Unit]
Description=Thermalog Application Stack
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=forking
RemainAfterExit=yes
WorkingDirectory=/root
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
TimeoutStartSec=300
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
```

### thermalog-startup.service
```ini
[Unit]
Description=Thermalog Startup Verification and Recovery
After=thermalog.service network-online.target
Wants=thermalog.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/root/startup-thermalog.sh
TimeoutStartSec=600
User=root

[Install]
WantedBy=multi-user.target
```

## Startup Verification Script

### Features
- **Docker readiness**: Waits for Docker daemon
- **Container verification**: Ensures all containers are running
- **Health checks**: Verifies backend health and database connectivity
- **Service recovery**: Attempts to fix issues automatically
- **Comprehensive logging**: Detailed startup audit trail

### Recovery Actions
- Starts missing containers
- Restarts failed services
- Verifies health endpoints
- Reports final system status

### Sample Output
```
═══════════════════════════════════════════════════════
     THERMALOG STARTUP VERIFICATION - 2025-09-11
═══════════════════════════════════════════════════════

✓ Docker service is active
✓ Application stack already running
✓ thermalog-backend is running
✓ thermalog-frontend is running  
✓ nginx is running
✓ Backend is healthy and database is connected
✓ Cron service is active
✓ Auto-deployment cron job is configured
✓ Application is accessible and healthy

═══════════════════════════════════════════════════════
```

## Monitoring & Verification

### Check Auto-Start Configuration
```bash
# Verify systemd services
systemctl list-unit-files | grep -E "(docker|cron|thermalog)"

# Check Docker restart policies
docker inspect thermalog-backend | grep -A5 RestartPolicy

# Verify cron jobs
crontab -l | grep reboot
```

### Test Restart Resilience
```bash
# Simulate system restart
sudo reboot

# After reboot, verify all services
systemctl status docker cron thermalog thermalog-startup
docker ps
curl -f http://localhost:3001/api/health

# Check startup logs
cat /root/startup-thermalog.log
```

### Monitor Boot Process
```bash
# Check service startup order
journalctl -u thermalog.service
journalctl -u thermalog-startup.service

# Monitor container startup
docker events --since 5m

# Check overall system status
systemctl status
```

## Troubleshooting

### Common Issues

#### Services Don't Start After Reboot
```bash
# Check systemd service status
systemctl status thermalog.service

# Check dependencies
systemctl list-dependencies thermalog.service

# Manual service start
systemctl start thermalog.service

# Check logs
journalctl -u thermalog.service -f
```

#### Containers Don't Start
```bash
# Check Docker daemon
systemctl status docker

# Check docker-compose.yml
cd /root && docker compose config

# Manual container start  
docker compose up -d

# Check container logs
docker logs thermalog-backend
```

#### Health Checks Fail
```bash
# Check backend container
docker ps | grep thermalog-backend

# Check backend logs
docker logs thermalog-backend | tail -20

# Test health endpoint manually
curl -v http://localhost:3001/api/health

# Check database connectivity
docker exec thermalog-backend npx prisma db pull
```

### Manual Recovery Procedures

#### Full Stack Recovery
```bash
# Stop all services
systemctl stop thermalog.service
docker compose down

# Start services in order
systemctl start docker
systemctl start thermalog.service
systemctl start thermalog-startup.service

# Verify status
/root/startup-thermalog.sh
```

#### Emergency Container Recovery
```bash
# Nuclear option - rebuild and restart
cd /root
docker compose down
docker compose build
docker compose up -d

# Wait for health check
sleep 30
curl http://localhost:3001/api/health
```

## Advanced Configuration

### Custom Recovery Actions
Edit `/root/startup-thermalog.sh` to add custom recovery actions:

```bash
# Example: Restart specific services on failure
if ! check_custom_service; then
    echo "Restarting custom service..."
    systemctl restart custom.service
fi
```

### Notification Integration
Add notification support to startup script:

```bash
# Example: Send startup notification
send_notification() {
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"Thermalog system started successfully\"}" \
        "$SLACK_WEBHOOK_URL"
}
```

## Integration with Automated Deployment

### Seamless Integration
The restart resilience system integrates with automated deployment:

- **Deployment continues**: Auto-deployment resumes after restart
- **Health monitoring**: Deployment system verifies service health
- **Docker cleanup**: Cleanup continues on schedule
- **SSL renewal**: Certificate management resumes automatically

### Zero Configuration
Once deployed, the system requires no manual intervention:
- Services start automatically
- Health monitoring resumes
- All automation continues seamlessly
- Full functionality restored within 90 seconds

## Best Practices

### Testing
- Test restart resilience regularly
- Simulate different failure scenarios
- Verify all services recover correctly
- Check logs for any issues

### Monitoring
- Monitor startup times
- Set up alerts for failed startups
- Review startup logs regularly
- Track service availability metrics

### Maintenance
- Keep systemd services updated
- Review restart policies regularly
- Update startup scripts as needed
- Test after infrastructure changes

## Security Considerations

### Service Permissions
- All services run with appropriate permissions
- Docker daemon requires root access
- Scripts have minimal required permissions

### Auto-Start Security
- Only necessary services auto-start
- Services start with minimal privileges
- Network access restricted appropriately

### Logging Security
- Startup logs don't contain sensitive data
- Log files have appropriate permissions
- Log rotation configured properly