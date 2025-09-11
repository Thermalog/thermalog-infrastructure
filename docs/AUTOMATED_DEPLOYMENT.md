# Thermalog Automated Deployment System

## Overview

The Thermalog automated deployment system provides safe, continuous deployment with health checks, automatic rollback, and Docker cleanup. This system monitors GitHub repositories and automatically deploys changes with zero-downtime strategies.

## Features

### ✅ Health Check API
- **Database connectivity verification**
- **Response time monitoring**
- **Memory usage tracking**
- **Multiple endpoint types**: `/health`, `/health/live`, `/health/ready`

### ✅ Automated Deployment
- **GitHub change detection** every 5 minutes
- **Safe deployment** with automatic rollback
- **Health verification** before marking deployment as successful
- **Backup creation** before each deployment

### ✅ Docker Management
- **Automatic cleanup** after deployments
- **Daily maintenance** at 2 AM
- **Smart image preservation** (keeps current + 3 backups)
- **Build cache management**

## Architecture

```
GitHub Repository
       ↓
   Auto-Deploy Script (every 5min)
       ↓
   Build & Deploy
       ↓
   Health Check API
       ↓
   Success/Rollback
       ↓
   Docker Cleanup
```

## Installation

### 1. Deploy Scripts
```bash
# Copy scripts to server
scp scripts/auto-deploy.sh root@server:/root/
scp scripts/docker-cleanup.sh root@server:/root/
scp scripts/setup-auto-deploy.sh root@server:/root/

# Make executable
chmod +x /root/*.sh
```

### 2. Setup Automated Deployment
```bash
# Run setup script
/root/setup-auto-deploy.sh
```

This will:
- Create log files
- Setup cron jobs
- Configure automatic monitoring

## Configuration

### Cron Schedule
```bash
# Check for deployments every 5 minutes
*/5 * * * * /root/auto-deploy.sh >> /root/deployment-cron.log 2>&1

# Daily Docker cleanup at 2 AM
0 2 * * * /root/docker-cleanup.sh >> /root/docker-cleanup-cron.log 2>&1
```

### Health Check Endpoints

#### Main Health Check
```bash
GET /api/health
```

Response:
```json
{
  "status": "healthy",
  "timestamp": "2025-09-11T19:44:58.416Z",
  "uptime": 933,
  "database": {
    "status": "connected",
    "responseTime": 3
  },
  "memory": {
    "used": 64,
    "total": 3912,
    "percentage": 2
  },
  "environment": "development"
}
```

#### Liveness Probe
```bash
GET /api/health/live
```

#### Readiness Probe
```bash
GET /api/health/ready
```

## Monitoring

### Log Files
- `/root/deployment.log` - Main deployment activity
- `/root/deployment-cron.log` - Cron execution logs
- `/root/docker-cleanup.log` - Docker cleanup activity
- `/root/docker-cleanup-cron.log` - Daily cleanup logs

### Real-time Monitoring
```bash
# Watch deployment activity
tail -f /root/deployment.log

# Watch cron execution
tail -f /root/deployment-cron.log

# Check Docker cleanup
tail -f /root/docker-cleanup.log
```

## Manual Operations

### Manual Deployment
```bash
# Run deployment check manually
/root/auto-deploy.sh
```

### Manual Cleanup
```bash
# Run Docker cleanup manually
/root/docker-cleanup.sh
```

### Disable Auto-deployment
```bash
# Edit crontab to remove auto-deploy line
crontab -e
```

### Re-enable Auto-deployment
```bash
# Run setup script again
/root/setup-auto-deploy.sh
```

## Safety Features

### Automatic Rollback
- **Health check failure**: Automatically restores previous version
- **Build failure**: Reverts code and Docker images
- **Database connectivity loss**: Triggers rollback sequence

### Backup Strategy
- **Pre-deployment backup**: Every deployment creates timestamped backup
- **Last stable version**: Tagged for quick rollback
- **Retention policy**: Keeps last 3 backups per service

### Process Safety
- **Lock files**: Prevents concurrent deployments
- **Error handling**: `set -e` ensures script stops on errors
- **Validation checks**: Verifies Git, Docker, and health endpoints

## Docker Management

### Cleanup Strategy
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Keep Current  │    │   Keep Backups   │    │  Remove Others  │
│                 │    │                  │    │                 │
│ • latest tags   │    │ • Last 3 backups │    │ • Dangling      │
│ • Running images│    │ • Timestamped    │    │ • Old builds    │
│ • Base images   │    │ • Auto-generated │    │ • Unused volumes│
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Space Management
- **Build cache**: Cleaned daily (>24h old)
- **Volumes**: Removes unused volumes
- **Networks**: Cleans dangling networks
- **Containers**: Removes stopped containers

## Notifications (Optional)

### Slack Integration
Add Slack webhook URL to auto-deploy.sh:
```bash
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

### Email Integration
Configure system mail or add email notifications to scripts.

## Troubleshooting

### Deployment Failures
1. Check deployment logs: `tail -f /root/deployment.log`
2. Verify health endpoint: `curl http://localhost:3001/api/health`
3. Check Docker status: `docker ps`
4. Review container logs: `docker logs thermalog-backend`

### Health Check Issues
1. Verify database connectivity
2. Check API endpoint accessibility
3. Review backend container status
4. Validate environment variables

### Cron Job Issues
1. Check cron service: `service cron status`
2. Verify crontab: `crontab -l`
3. Check permissions: `ls -la /root/*.sh`
4. Review cron logs: `tail -f /root/deployment-cron.log`

## Best Practices

### Development Workflow
1. **Push to main branch** triggers automatic deployment
2. **Health checks** ensure database connectivity
3. **Automatic rollback** on any failure
4. **Cleanup** maintains system efficiency

### Production Considerations
- Monitor log files regularly
- Set up alerting for failed deployments  
- Review backup retention policies
- Plan maintenance windows for major updates

### Security
- Scripts run with proper permissions (755)
- No hardcoded credentials
- Logs don't contain sensitive data
- Process isolation with lock files

## System Requirements

- Docker & Docker Compose
- Git access to repositories
- Cron service running
- Sufficient disk space for backups
- Network access to GitHub

## Version History

- **v2.0**: Added automated deployment with health checks
- **v1.5**: Implemented Docker cleanup automation
- **v1.0**: Basic health check API integration

## Support

For issues or improvements:
1. Check logs first
2. Review this documentation
3. Open GitHub issue in thermalog-infrastructure repository
4. Include relevant log snippets and error messages