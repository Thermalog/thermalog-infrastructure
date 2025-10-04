# Thermalog Infrastructure

Complete infrastructure configuration for the Thermalog application, enabling easy deployment and disaster recovery.

## 📚 Documentation Quick Links

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Visual system architecture with Mermaid diagrams
- **[OPERATIONS.md](docs/OPERATIONS.md)** - Quick operational commands and troubleshooting
- **[DISASTER_RECOVERY.md](docs/DISASTER_RECOVERY.md)** - Complete server recovery procedures
- **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - New server deployment reference

## 🚀 Quick Start

### 🆕 One-Click Deployment (Recommended)
```bash
# 1. Install prerequisites (git and curl only)
sudo apt update && sudo apt install -y git curl

# 2. Clone ONLY this infrastructure repository
git clone https://github.com/Thermalog/thermalog-infrastructure.git
cd thermalog-infrastructure

# 3. Run the master deployment script (automatically clones other repos)
sudo ./deploy-everything.sh
```

**⚡ The script automatically clones Thermalog-Backend and Thermalog-frontend repositories for you!**

### 📊 Monitoring & Alerts
The system includes comprehensive crash reporting and monitoring:
- **Real-time monitoring** via Uptime Kuma dashboard
- **Email alerts** for service failures and recoveries  
- **24/7 automated checking** every 2 minutes
- **SSL-enabled dashboard** at `https://dashboard.thermalog.com.au/monitoring/`

See [MONITORING.md](docs/MONITORING.md) for detailed setup instructions.

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
# Create complete unencrypted backup (recommended for fast local recovery)
./scripts/backup.sh

# Create encrypted backup (for secure off-site storage)
# Note: Encrypted backup script is in thermalog-ops repository
/root/thermalog-ops/scripts/backup/create-encrypted-backup.sh

# Extract backup
./extract-backup.sh /path/to/backup.tar.gz.enc
```

**Note**: Daily unencrypted backups are automated. Encrypted backups are stored securely for disaster recovery. See [BACKUP_DOCUMENTATION.md](BACKUP_DOCUMENTATION.md) for complete backup procedures.

## 📁 Repository Structure

```
thermalog-infrastructure/
├── scripts/                         # Reference deployment scripts
│   ├── setup-server.sh             # Complete server setup
│   ├── auto-deploy.sh              # Automated deployment (reference)
│   ├── docker-cleanup.sh           # Docker cleanup automation
│   ├── setup-auto-deploy.sh        # Setup automation (cron jobs)
│   ├── ssl-renew.sh                # SSL certificate renewal (reference)
│   ├── startup-thermalog.sh        # Server restart verification
│   ├── deploy.sh                    # Manual deployment
│   ├── backup.sh                    # Unencrypted backup creation
│   ├── verify-latest-backup.sh      # Backup integrity verification
│   ├── install-ssl-hooks.sh         # SSL automation setup
│   ├── uptime-kuma-alerts.sh        # Monitoring alerts
│   ├── uptime-kuma-alerts-improved.sh # Enhanced monitoring
│   └── ssl-hooks/                   # Certificate renewal hooks
│       ├── pre/stop-nginx.sh        # Pre-renewal hook
│       ├── post/start-nginx.sh      # Post-renewal hook
│       └── deploy/docker-nginx.sh   # Certificate deployment
├── configs/                         # Configuration templates
│   ├── health-check.json           # Health check configuration
│   ├── docker-cleanup.json         # Docker cleanup settings
│   ├── .env.backend.template        # Backend environment template
│   ├── .env.frontend.template       # Frontend environment template
│   └── systemd/                    # Systemd service files
│       ├── thermalog.service       # Main application service
│       ├── thermalog-startup.service # Startup verification
│       ├── thermalog-shutdown.service # Graceful shutdown
│       └── emqx-platform.service    # EMQX IoT platform service
├── nginx/                           # Nginx configuration reference
│   └── default.conf                 # Reference nginx configuration
├── backups/                         # Encrypted backup storage
│   └── *.tar.gz.enc                # Encrypted backup files (tracked)
├── docs/                           # Comprehensive documentation
│   ├── ARCHITECTURE.md             # System architecture with diagrams
│   ├── OPERATIONS.md               # Quick operational reference
│   ├── AUTOMATED_DEPLOYMENT.md    # Automated deployment system
│   ├── SSL_RENEWAL.md              # Dual SSL certificate renewal
│   ├── SERVER_RESTART_RESILIENCE.md # Restart recovery system
│   ├── MONITORING.md               # Uptime Kuma monitoring
│   ├── EMQX_PLATFORM.md            # EMQX IoT platform guide
│   ├── DUAL_SSL_CERTIFICATES.md    # Dual certificate system
│   ├── DISASTER_RECOVERY.md        # Recovery procedures
│   ├── deployment.md               # Deployment procedures
│   ├── ssl-setup.md                # SSL configuration details
│   └── troubleshooting.md          # Common issues and solutions
├── BACKUP_DOCUMENTATION.md         # Comprehensive backup guide
├── DEPLOYMENT_GUIDE.md             # Complete deployment reference
├── MIGRATION_NOTES.md              # System evolution and changes
├── deploy-everything.sh             # Master deployment script
├── extract-backup.sh               # Backup extraction utility
└── README.md                       # This file
```

**Note**: Active production scripts are located in `/root/thermalog-ops/scripts/`. This repository contains reference scripts for deployment and documentation purposes.

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

### Cron Jobs (Sydney Time = UTC+10/11)
```bash
*/5 * * * *    # Auto-deployment monitoring every 5 minutes
*/2 * * * *    # Uptime Kuma monitoring alerts every 2 minutes
0 2 * * *      # Docker cleanup daily at 2 AM UTC
0 */12 * * *   # Process cleanup every 12 hours
15 3,15 * * *  # Dual SSL renewal twice daily (3:15 AM/PM UTC)
0 17 * * *     # Daily comprehensive backup (3 AM Sydney = 17:00 UTC)
0 18 * * 6     # Weekly backup verification (4 AM Sunday Sydney = 18:00 UTC Sat)
@reboot        # Startup verification after server restart
```

### Systemd Services
```bash
thermalog.service           # Main application stack (Backend, Frontend, Nginx)
thermalog-startup.service   # Startup verification and recovery
thermalog-shutdown.service  # Graceful shutdown handler
emqx-platform.service       # EMQX IoT platform (MQTT + PostgreSQL)
docker.service              # Docker daemon (enabled)
cron.service                # Cron scheduler (enabled)
```

## 🔧 Prerequisites

- Fresh Ubuntu 20.04+ server
- Domain name pointing to your server
- Root access
- Git installed

## 🎯 Features

- **🐳 Docker Orchestration**: Complete containerized setup with dual-stack architecture
- **🔒 Dual SSL Certificates**: ECDSA + RSA certificates with automatic renewal
- **📡 EMQX IoT Platform**: Full-featured MQTT broker with TimescaleDB integration
- **📦 One-Command Setup**: Complete server setup in minutes
- **🚀 Easy Deployments**: Automated deployment with health checks and rollback
- **💾 Comprehensive Backups**: Daily automated backups with weekly verification
- **📊 Real-time Monitoring**: Uptime Kuma with email alerts every 2 minutes
- **🔄 Server Resilience**: Auto-recovery after restart with multi-layer redundancy
- **📚 Complete Documentation**: Detailed guides for deployment and troubleshooting

## 🔄 SSL Certificate Management

Dual SSL certificates (ECDSA + RSA) are automatically managed with:
- **Dual Certificates**: ECDSA (modern) + RSA (legacy browser compatibility)
- **Initial Setup**: Both certificates generated during server setup
- **Auto-Renewal**: Certificates renewed 30 days before expiration (twice daily checks)
- **Zero Downtime**: Nginx restarted automatically after renewal
- **Container Integration**: Both certificates automatically deployed to nginx container
- **Browser Compatibility**: Nginx serves optimal certificate based on client capabilities

See [docs/DUAL_SSL_CERTIFICATES.md](docs/DUAL_SSL_CERTIFICATES.md) for detailed information.

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

1. **Backend Configuration** (`./Thermalog-Backend/.env`):
   ```bash
   DATABASE_URL="postgresql://username:password@host:port/database"
   ALLOWED_ORIGIN=https://dashboard.thermalog.com.au
   JWT_SECRET=your-jwt-secret-key
   PORT=3001
   ```

2. **Frontend Configuration** (`./Thermalog-frontend/.env`):
   ```bash
   REACT_APP_API_URL=https://dashboard.thermalog.com.au/api
   REACT_APP_WEB_SOCKET_URL=wss://dashboard.thermalog.com.au
   ```

**Note**: Environment files are automatically configured during deployment. See `configs/` directory for templates.

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
# Extract encrypted backup (recommended)
./extract-backup.sh backups/thermalog_server_backup_YYYYMMDD_HHMMSS_encrypted.tar.gz.enc

# OR extract legacy unencrypted backup
tar -xzf thermalog_backup_YYYYMMDD_HHMMSS.tar.gz

# Restore SSL certificates
sudo cp -r thermalog_backup_*/letsencrypt/* /etc/letsencrypt/

# Restore configurations
cp thermalog_backup_*/docker-compose.yml .
cp thermalog_backup_*/nginx/default.conf nginx/
```

**Note**: Encrypted backups provide enhanced security and are the recommended approach. See [BACKUP_DOCUMENTATION.md](BACKUP_DOCUMENTATION.md) for detailed recovery procedures.

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