# Thermalog Infrastructure

Complete infrastructure configuration for the Thermalog application, enabling easy deployment and disaster recovery.

## 🚀 Quick Start

### New Server Setup
```bash
# 1. Clone this repository
git clone https://github.com/yourusername/thermalog-infrastructure.git
cd thermalog-infrastructure

# 2. Run the automated setup script
sudo ./scripts/setup-server.sh
```

### Automated Deployment
```bash
# Setup automated deployment (run once)
./scripts/setup-auto-deploy.sh

# Manual deployment (if needed)
./scripts/auto-deploy.sh
```

### Traditional Deployment
```bash
# Update and redeploy manually
./scripts/deploy.sh
```

### Creating Backups
```bash
# Create a complete backup
./scripts/backup.sh
```

## 📁 Repository Structure

```
thermalog-infrastructure/
├── docker/                          # Docker orchestration
│   ├── docker-compose.yml           # Base configuration
│   └── docker-compose.prod.yml      # Production overrides
├── nginx/                           # Nginx configuration
│   └── default.conf                 # Main nginx config
├── scripts/                         # Automation scripts
│   ├── setup-server.sh             # Complete server setup
│   ├── auto-deploy.sh              # 🆕 Automated deployment with health checks
│   ├── docker-cleanup.sh           # 🆕 Docker cleanup and maintenance
│   ├── setup-auto-deploy.sh        # 🆕 Setup automation (cron jobs)
│   ├── ssl-renew.sh                # 🆕 SSL certificate auto-renewal
│   ├── startup-thermalog.sh        # 🆕 Server restart verification
│   ├── deploy.sh                    # Manual deployment (legacy)
│   ├── backup.sh                    # Backup creation
│   ├── install-ssl-hooks.sh         # SSL automation setup
│   └── ssl-hooks/                   # Certificate renewal hooks
│       ├── pre/stop-nginx.sh        # Pre-renewal hook
│       ├── post/start-nginx.sh      # Post-renewal hook
│       └── deploy/docker-nginx.sh   # Certificate deployment
├── configs/                         # Configuration templates
│   ├── health-check.json           # 🆕 Health check configuration
│   ├── docker-cleanup.json         # 🆕 Docker cleanup settings
│   ├── systemd/                    # 🆕 Systemd service files
│   │   ├── thermalog.service       # 🆕 Main application service
│   │   └── thermalog-startup.service # 🆕 Startup verification service
│   ├── .env.backend.template        # Backend environment template
│   └── .env.frontend.template       # Frontend environment template
├── docs/                           # Documentation
│   ├── AUTOMATED_DEPLOYMENT.md    # 🆕 Automated deployment guide
│   ├── SSL_RENEWAL.md              # 🆕 SSL certificate auto-renewal
│   ├── SERVER_RESTART_RESILIENCE.md # 🆕 Server restart recovery
│   ├── deployment.md               # Manual deployment guide
│   ├── ssl-setup.md                # SSL configuration
│   └── troubleshooting.md          # Common issues
└── README.md                       # This file
```

## 🤖 Automated Deployment Features

### Health Check API
- **Database connectivity verification** with response time monitoring
- **Memory usage tracking** and system health
- **Multiple endpoints**: `/health`, `/health/live`, `/health/ready`
- **Automatic failure detection** with HTTP 503 responses

### Continuous Deployment
- **GitHub monitoring** every 5 minutes
- **Safe deployment** with automatic rollback
- **Health verification** before deployment completion
- **Zero-downtime** deployment strategies

### Docker Management
- **Automatic cleanup** after deployments
- **Daily maintenance** at 2 AM UTC
- **Smart retention** (keeps current + 3 backups)
- **Build cache management** and space optimization

### Monitoring & Alerting
- **Comprehensive logging** for all operations
- **Real-time monitoring** with colored output
- **Optional Slack integration** for notifications
- **Backup verification** and rollback safety

### Server Restart Resilience
- **Multi-layer recovery** system with automatic restart
- **Systemd service integration** for boot-time startup
- **Startup verification** with health checks and recovery
- **Complete automation** resumes after restart

### SSL Certificate Management
- **Automatic renewal** twice daily with Let's Encrypt
- **Docker-aware process** safely stops/starts nginx
- **Smart scheduling** with random delays to prevent rate limiting
- **Comprehensive logging** and error handling

## 📅 Complete Automation Schedule

### Cron Jobs
```bash
*/5 * * * *    # Auto-deployment monitoring every 5 minutes
0 2 * * *      # Docker cleanup daily at 2 AM
15 3,15 * * *  # SSL renewal twice daily (3:15 AM/PM + random delay)
@reboot        # Startup verification after server restart
```

### Systemd Services
```bash
thermalog.service         # Main application stack auto-start
thermalog-startup.service # Startup verification and recovery
docker.service            # Docker daemon (enabled)
cron.service              # Cron scheduler (enabled)
```

## 🔧 Prerequisites

- Fresh Ubuntu 20.04+ server
- Domain name pointing to your server
- Root access
- Git installed

## 🎯 Features

- **🐳 Docker Orchestration**: Complete containerized setup
- **🔒 Automated SSL**: Let's Encrypt with automatic renewal
- **📦 One-Command Setup**: Complete server setup in minutes  
- **🚀 Easy Deployments**: Update with a single command
- **💾 Comprehensive Backups**: Full configuration and data backups
- **📚 Complete Documentation**: Detailed guides and troubleshooting

## 🔄 SSL Certificate Management

SSL certificates are automatically managed with:
- **Initial Setup**: Certificates generated during server setup
- **Auto-Renewal**: Certificates renewed 30 days before expiration
- **Zero Downtime**: Nginx restarted automatically after renewal
- **Container Integration**: Certificates automatically deployed to containers

## 🛠️ Manual Commands

### Docker Management
```bash
# Start all services
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# Stop all services
docker compose down

# View logs
docker logs thermalog-backend
docker logs nginx

# Restart a service
docker restart thermalog-backend
```

### SSL Management
```bash
# Test SSL renewal
certbot renew --dry-run

# Force SSL renewal
certbot renew --force-renewal

# Check certificate status
certbot certificates
```

## 🔧 Configuration

### Environment Variables

1. **Backend Configuration** (`/path/to/Thermalog-Backend/.env`):
   ```bash
   DATABASE_URL="postgresql://username:password@host:port/database"
   ALLOWED_ORIGIN=https://your-domain.com
   ```

2. **Frontend Configuration** (`/path/to/Thermalog-frontend/.env`):
   ```bash
   REACT_APP_API_URL=https://your-domain.com/api
   REACT_APP_WEB_SOCKET_URL=wss://your-domain.com
   ```

### Domain Configuration

Update the following files with your domain:
- `scripts/setup-server.sh` - Update `DOMAIN` variable
- `nginx/default.conf` - Update `server_name`
- `scripts/ssl-hooks/deploy/docker-nginx.sh` - Update `CERT_NAME`

## 📊 Monitoring

### Health Checks
```bash
# Check container status
docker ps

# Check resource usage
docker stats

# Check SSL certificate expiry
openssl s_client -connect your-domain.com:443 -servername your-domain.com < /dev/null 2>/dev/null | openssl x509 -dates -noout
```

### Logs
```bash
# Application logs
docker logs thermalog-backend --tail 100

# SSL renewal logs
cat /var/log/cert-deploy.log

# Nginx logs
docker logs nginx --tail 100
```

## 🆘 Disaster Recovery

### Complete Server Recovery
1. Set up new server with same domain
2. Clone this repository
3. Run `./scripts/setup-server.sh`
4. Restore your application repositories
5. Configure environment variables
6. Run `./scripts/deploy.sh`

### Backup Recovery
```bash
# Extract backup
tar -xzf thermalog_backup_YYYYMMDD_HHMMSS.tar.gz

# Restore SSL certificates
sudo cp -r thermalog_backup_*/letsencrypt/* /etc/letsencrypt/

# Restore configurations
cp thermalog_backup_*/docker-compose.yml .
cp thermalog_backup_*/nginx/default.conf nginx/
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test your changes on a staging environment
4. Submit a pull request

## 📄 License

This infrastructure configuration is part of the Thermalog project.

## 🆘 Support

For issues and questions:
- Check `docs/troubleshooting.md`
- Review container logs
- Check SSL certificate status
- Verify domain DNS configuration