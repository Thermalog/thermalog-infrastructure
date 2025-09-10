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

### Deploying Updates
```bash
# Update and redeploy the application
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
│   ├── deploy.sh                    # Deployment automation
│   ├── backup.sh                    # Backup creation
│   ├── install-ssl-hooks.sh         # SSL automation setup
│   └── ssl-hooks/                   # Certificate renewal hooks
│       ├── pre/stop-nginx.sh        # Pre-renewal hook
│       ├── post/start-nginx.sh      # Post-renewal hook
│       └── deploy/docker-nginx.sh   # Certificate deployment
├── configs/                         # Configuration templates
│   ├── .env.backend.template        # Backend environment template
│   └── .env.frontend.template       # Frontend environment template
├── docs/                           # Documentation
│   ├── deployment.md               # Deployment guide
│   ├── ssl-setup.md                # SSL configuration
│   └── troubleshooting.md          # Common issues
└── README.md                       # This file
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