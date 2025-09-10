# Deployment Guide

This guide covers deployment scenarios for the Thermalog application.

## 🆕 New Server Deployment

### Prerequisites
- Ubuntu 20.04+ server
- Domain name configured (A record pointing to server IP)
- Root access to the server
- SSH access configured

### Automated Setup

1. **Clone the infrastructure repository**:
   ```bash
   git clone https://github.com/yourusername/thermalog-infrastructure.git
   cd thermalog-infrastructure
   ```

2. **Run the setup script**:
   ```bash
   sudo ./scripts/setup-server.sh
   ```

3. **Configure environment variables** when prompted:
   - Edit `Thermalog-Backend/.env`
   - Edit `Thermalog-frontend/.env`

### Manual Setup (Alternative)

If you prefer manual control:

1. **Update system and install Docker**:
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   ```

2. **Install Certbot**:
   ```bash
   sudo snap install --classic certbot
   sudo ln -s /snap/bin/certbot /usr/bin/certbot
   ```

3. **Clone application repositories**:
   ```bash
   mkdir -p /root/thermalog-app && cd /root/thermalog-app
   git clone https://github.com/yourusername/Thermalog-Backend.git
   git clone https://github.com/yourusername/Thermalog-frontend.git
   git clone https://github.com/yourusername/thermalog-infrastructure.git
   ```

4. **Setup configuration**:
   ```bash
   cp thermalog-infrastructure/docker/*.yml .
   cp thermalog-infrastructure/configs/.env.*.template .
   # Edit environment files with your configuration
   ```

5. **Start application**:
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
   ```

6. **Setup SSL**:
   ```bash
   docker stop nginx
   certbot certonly --standalone -d your-domain.com --non-interactive --agree-tos --email your-email@domain.com
   ./thermalog-infrastructure/scripts/install-ssl-hooks.sh
   docker start nginx
   ```

## 🔄 Update Deployment

### Automated Updates
```bash
cd /root/thermalog-app
./thermalog-infrastructure/scripts/deploy.sh
```

### Manual Updates

1. **Create backup**:
   ```bash
   ./thermalog-infrastructure/scripts/backup.sh
   ```

2. **Pull latest code**:
   ```bash
   cd Thermalog-Backend && git pull origin main && cd ..
   cd Thermalog-frontend && git pull origin main && cd ..
   cd thermalog-infrastructure && git pull origin main && cd ..
   ```

3. **Update configuration** (if needed):
   ```bash
   cp thermalog-infrastructure/docker/*.yml .
   cp thermalog-infrastructure/nginx/default.conf nginx/
   ```

4. **Redeploy**:
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.prod.yml down
   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
   ```

## 🏗️ Environment-Specific Deployments

### Development Environment
```bash
# Use only base docker-compose
docker compose up -d

# With local database
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

### Staging Environment
```bash
# Similar to production but with staging domain
export DOMAIN="staging.thermalog.com.au"
./scripts/setup-server.sh
```

### Production Environment
```bash
# Full production setup with SSL
./scripts/setup-server.sh
```

## 🔧 Configuration Management

### Environment Variables

**Backend (.env)**:
```bash
DATABASE_URL="postgresql://user:pass@host:port/db"
ALLOWED_ORIGIN=https://your-domain.com
NODE_ENV=production
```

**Frontend (.env)**:
```bash
REACT_APP_API_URL=https://your-domain.com/api
REACT_APP_WEB_SOCKET_URL=wss://your-domain.com
```

### SSL Configuration

The SSL setup includes:
- Automatic certificate generation
- Renewal hooks for Docker deployment
- Zero-downtime certificate updates

### Database Configuration

Configure your database connection in the backend `.env` file:

```bash
# External PostgreSQL
DATABASE_URL="postgresql://username:password@your-db-host:5432/thermalog?schema=public"

# Local TimescaleDB container (if enabled)
DATABASE_URL="postgresql://postgres:password@timescaledb:5432/mydatabase"
```

## 📊 Post-Deployment Verification

### Health Checks
```bash
# Check container status
docker ps

# Test application endpoints
curl -k https://your-domain.com/api/health

# Check SSL certificate
echo | openssl s_client -servername your-domain.com -connect your-domain.com:443 2>/dev/null | openssl x509 -dates -noout
```

### Performance Monitoring
```bash
# Container resource usage
docker stats

# System resources
htop
df -h

# Network connectivity
netstat -tulpn | grep :443
```

## 🚨 Troubleshooting

### Container Issues
```bash
# View logs
docker logs thermalog-backend --tail 100
docker logs nginx --tail 100

# Restart containers
docker restart thermalog-backend
docker restart nginx

# Rebuild containers
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build --force-recreate
```

### SSL Issues
```bash
# Test SSL renewal
certbot renew --dry-run

# Check certificate details
certbot certificates

# Manual certificate regeneration
docker stop nginx
certbot certonly --standalone -d your-domain.com --force-renewal
docker start nginx
```

### Database Connection Issues
```bash
# Check backend logs for database errors
docker logs thermalog-backend | grep -i database

# Test database connectivity (if using external DB)
docker exec thermalog-backend npx prisma db pull
```

## 🔄 Rollback Procedures

### Application Rollback
```bash
# Stop current containers
docker compose down

# Restore from backup
tar -xzf /root/backups/thermalog_backup_YYYYMMDD_HHMMSS.tar.gz
cd thermalog_backup_YYYYMMDD_HHMMSS/thermalog-app

# Start previous version
docker compose up -d
```

### Configuration Rollback
```bash
# Restore nginx config
docker cp backup/nginx/default.conf nginx:/etc/nginx/conf.d/
docker exec nginx nginx -s reload

# Restore environment files
cp backup/env/*.env /path/to/app/
docker restart thermalog-backend
```

## 🔐 Security Considerations

### SSL/TLS
- Certificates auto-renew 30 days before expiration
- Modern TLS protocols only (1.2+)
- Strong cipher suites configured

### Container Security
- Containers run with minimal privileges
- Regular base image updates recommended
- Secrets managed via environment variables

### Firewall Configuration
```bash
# Allow HTTP/HTTPS traffic
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow SSH (adjust port as needed)
sudo ufw allow 22/tcp

# Enable firewall
sudo ufw enable
```

## 📈 Monitoring and Logging

### Application Monitoring
- Docker container health checks
- Application-level health endpoints
- SSL certificate expiry monitoring

### Log Management
```bash
# Configure log rotation for Docker
echo '{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}' | sudo tee /etc/docker/daemon.json

sudo systemctl restart docker
```