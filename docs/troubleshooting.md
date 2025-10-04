# Troubleshooting Guide

Common issues and solutions for the Thermalog infrastructure.

## 🐳 Docker Issues

### Container Won't Start

**Symptoms**: Container exits immediately or fails to start

**Diagnosis**:
```bash
# Check container status
docker ps -a

# View container logs
docker logs thermalog-backend
docker logs nginx

# Check container configuration
docker inspect thermalog-backend
```

**Common Solutions**:

1. **Environment Configuration**:
   ```bash
   # Check .env files exist and have correct values
   ls -la Thermalog-Backend/.env
   ls -la Thermalog-frontend/.env
   
   # Validate environment variables
   docker exec thermalog-backend env | grep DATABASE_URL
   ```

2. **Port Conflicts**:
   ```bash
   # Check if ports are already in use
   netstat -tulpn | grep :3001
   netstat -tulpn | grep :80
   netstat -tulpn | grep :443
   
   # Stop conflicting services
   sudo systemctl stop apache2  # if running
   sudo systemctl stop nginx    # if running on host
   ```

3. **Database Connection**:
   ```bash
   # Test database connectivity from backend container
   docker exec thermalog-backend npm run db:check
   
   # Check database logs (if using external DB)
   tail -f /var/log/postgresql/postgresql-*.log
   ```

### Build Failures

**Symptoms**: `docker compose build` fails

**Solutions**:

1. **Clear Docker Cache**:
   ```bash
   docker system prune -a
   docker compose build --no-cache
   ```

2. **Check Dockerfile Syntax**:
   ```bash
   # Validate Dockerfiles
   docker run --rm -i hadolint/hadolint < Thermalog-Backend/Dockerfile
   ```

3. **Dependency Issues**:
   ```bash
   # Check package.json and dependencies
   docker exec thermalog-backend npm audit
   docker exec thermalog-backend npm ci
   ```

## 🔒 SSL/TLS Issues

### SSL Certificate Problems

**Symptoms**: Browser shows "Not Secure" or SSL errors

**Diagnosis**:
```bash
# Check certificate status
certbot certificates

# Test SSL connection
echo | openssl s_client -servername dashboard.thermalog.com.au -connect dashboard.thermalog.com.au:443 2>/dev/null | openssl x509 -dates -noout

# Check nginx configuration
docker exec nginx nginx -t
```

**Solutions**:

1. **Certificate Not Found**:
   ```bash
   # Regenerate certificate
   docker stop nginx
   certbot certonly --standalone -d dashboard.thermalog.com.au --force-renewal
   /etc/letsencrypt/renewal-hooks/deploy/docker-nginx.sh
   docker start nginx
   ```

2. **Certificate Expired**:
   ```bash
   # Force renewal
   certbot renew --force-renewal --cert-name dashboard.thermalog.com.au
   ```

3. **Wrong Certificate in Container**:
   ```bash
   # Manually deploy certificate
   docker cp /etc/letsencrypt/archive/dashboard.thermalog.com.au/fullchain1.pem nginx:/etc/ssl/certs/fullchain.pem
   docker cp /etc/letsencrypt/archive/dashboard.thermalog.com.au/privkey1.pem nginx:/etc/ssl/certs/privkey.pem
   docker exec nginx nginx -s reload
   ```

### Certificate Renewal Failures

**Symptoms**: Automatic renewal fails

**Diagnosis**:
```bash
# Check renewal logs
tail -f /var/log/letsencrypt/letsencrypt.log

# Test renewal
certbot renew --dry-run

# Check systemd timer
systemctl status snap.certbot.renew.timer
```

**Solutions**:

1. **Port 80 Blocked**:
   ```bash
   # Check what's using port 80
   netstat -tulpn | grep :80
   
   # Ensure nginx is stopped during renewal
   docker stop nginx
   certbot renew --force-renewal
   docker start nginx
   ```

2. **DNS Issues**:
   ```bash
   # Check DNS resolution
   dig dashboard.thermalog.com.au A
   nslookup dashboard.thermalog.com.au
   ```

## 🌐 Network Issues

### Application Not Accessible

**Symptoms**: Website not loading, connection timeouts

**Diagnosis**:
```bash
# Check if containers are running
docker ps

# Check port bindings
docker port nginx
docker port thermalog-backend

# Test local connectivity
curl -I http://localhost:80
curl -I https://localhost:443
```

**Solutions**:

1. **Firewall Issues**:
   ```bash
   # Check firewall status
   sudo ufw status
   
   # Open necessary ports
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw reload
   ```

2. **DNS Configuration**:
   ```bash
   # Verify domain points to server
   dig dashboard.thermalog.com.au A
   
   # Check if IP matches server
   curl -H "Host: dashboard.thermalog.com.au" http://YOUR_SERVER_IP
   ```

3. **Container Networking**:
   ```bash
   # Check Docker networks
   docker network ls
   docker network inspect root_app-network
   
   # Test inter-container connectivity
   docker exec nginx ping thermalog-backend
   ```

### API Connection Issues

**Symptoms**: Frontend loads but API calls fail

**Diagnosis**:
```bash
# Check backend container logs
docker logs thermalog-backend --tail 100

# Test API directly
curl https://dashboard.thermalog.com.au/api/health

# Check nginx proxy configuration
docker exec nginx cat /etc/nginx/conf.d/default.conf | grep -A 10 "/api/"
```

**Solutions**:

1. **Backend Container Issues**:
   ```bash
   # Restart backend
   docker restart thermalog-backend
   
   # Check backend health
   docker exec thermalog-backend npm run health-check
   ```

2. **Nginx Proxy Configuration**:
   ```bash
   # Verify proxy settings in nginx config
   docker exec nginx nginx -t
   
   # Update nginx config if needed
   cp thermalog-infrastructure/nginx/default.conf nginx/
   docker cp nginx/default.conf nginx:/etc/nginx/conf.d/
   docker exec nginx nginx -s reload
   ```

## 💾 Database Issues

### Database Connection Failures

**Symptoms**: Backend logs show database connection errors

**Diagnosis**:
```bash
# Check backend logs for database errors
docker logs thermalog-backend | grep -i database

# Check DATABASE_URL format
docker exec thermalog-backend env | grep DATABASE_URL
```

**Solutions**:

1. **Connection String Issues**:
   ```bash
   # Verify DATABASE_URL format
   # Should be: postgresql://username:password@host:port/database?schema=public
   
   # Test connection from backend container
   docker exec thermalog-backend npx prisma db pull
   ```

2. **External Database Issues**:
   ```bash
   # Test network connectivity to database
   docker exec thermalog-backend ping your-db-host
   docker exec thermalog-backend telnet your-db-host 5432
   ```

3. **Migration Issues**:
   ```bash
   # Run database migrations
   docker exec thermalog-backend npx prisma migrate deploy
   
   # Generate Prisma client
   docker exec thermalog-backend npx prisma generate
   ```

## 🔍 Application Issues

### High Memory Usage

**Symptoms**: Containers using excessive memory

**Diagnosis**:
```bash
# Check container resource usage
docker stats

# Check system memory
free -h
df -h
```

**Solutions**:

1. **Container Resource Limits**:
   ```bash
   # Add memory limits to docker-compose.prod.yml
   services:
     thermalog-backend:
       deploy:
         resources:
           limits:
             memory: 512M
   ```

2. **Memory Leaks**:
   ```bash
   # Restart containers to free memory
   docker restart thermalog-backend
   docker restart nginx
   
   # Monitor for memory leaks
   docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
   ```

### Performance Issues

**Symptoms**: Slow page loads, high response times

**Diagnosis**:
```bash
# Check container performance
docker stats

# Check application logs for slow queries
docker logs thermalog-backend | grep -i slow

# Test response times
curl -w "@curl-format.txt" -o /dev/null -s https://dashboard.thermalog.com.au/api/health
```

**Solutions**:

1. **Database Optimization**:
   ```bash
   # Check for slow database queries
   docker exec thermalog-backend npx prisma studio
   
   # Add database indexes if needed
   # Review database query performance
   ```

2. **Container Optimization**:
   ```bash
   # Increase container resources
   # Add to docker-compose.prod.yml:
   services:
     thermalog-backend:
       deploy:
         resources:
           limits:
             cpus: '1.0'
             memory: 1G
   ```

## 📊 Monitoring and Debugging

### Log Analysis

**Backend Logs**:
```bash
# Real-time backend logs
docker logs thermalog-backend -f

# Filter for errors
docker logs thermalog-backend | grep -i error

# Export logs for analysis
docker logs thermalog-backend > backend_logs.txt
```

**Nginx Logs**:
```bash
# Access logs
docker exec nginx tail -f /var/log/nginx/access.log

# Error logs  
docker exec nginx tail -f /var/log/nginx/error.log

# SSL-specific errors
docker logs nginx | grep -i ssl
```

**System Logs**:
```bash
# Docker daemon logs
journalctl -u docker.service -f

# System resource monitoring
htop
iotop
```

### Health Checks

**Container Health**:
```bash
# Check all container status
docker ps -a

# Detailed container information
docker inspect thermalog-backend | grep -A 10 '"State"'

# Container resource usage
docker stats --no-stream
```

**Application Health**:
```bash
# Test application endpoints
curl -f https://dashboard.thermalog.com.au/api/health
curl -f https://dashboard.thermalog.com.au

# Check database connectivity
docker exec thermalog-backend npx prisma db pull --dry-run
```

## 🆘 Recovery Procedures

### Complete System Recovery

1. **Stop all services**:
   ```bash
   docker compose down
   ```

2. **Restore from backup**:
   ```bash
   cd /root/backups
   tar -xzf thermalog_backup_LATEST.tar.gz
   ```

3. **Restore configuration**:
   ```bash
   cp -r backup/thermalog-app/* /root/thermalog-app/
   ```

4. **Restart services**:
   ```bash
   cd /root/thermalog-app
   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
   ```

### Partial Recovery

**Restore SSL Certificates**:
```bash
sudo cp -r backup/letsencrypt/* /etc/letsencrypt/
/etc/letsencrypt/renewal-hooks/deploy/docker-nginx.sh
```

**Restore Configuration**:
```bash
cp backup/docker-compose.yml .
cp backup/nginx/default.conf nginx/
docker exec nginx nginx -s reload
```

## 🌐 EMQX Platform Issues

### MQTT Broker Not Accessible

**Symptoms**: Cannot connect to MQTT broker, devices failing to connect

**Diagnosis**:
```bash
# Check EMQX container status
docker ps | grep emqx

# Check EMQX logs
docker logs emqx --tail=100

# Test MQTT connection
mosquitto_pub -h localhost -p 1883 -t test -m "hello"

# Check EMQX dashboard
curl http://localhost:18083/api/v5/status
```

**Solutions**:
1. **Restart EMQX Platform**:
   ```bash
   systemctl restart emqx-platform.service
   ```

2. **Check EMQX Configuration**:
   ```bash
   docker exec emqx emqx ctl status
   docker exec emqx emqx ctl cluster status
   ```

### IoT PostgreSQL Connection Issues

**Symptoms**: Device data not being stored, provisioning failures

**Diagnosis**:
```bash
# Check PostgreSQL container
docker ps | grep iot-postgres

# Check PostgreSQL logs
docker logs iot-postgres --tail=100

# Test database connection
docker exec iot-postgres psql -U iotadmin -d iot_platform -c "SELECT COUNT(*) FROM device_credentials;"
```

**Solutions**:
1. **Restart IoT PostgreSQL**:
   ```bash
   cd /root/emqx-platform && docker-compose restart iot-postgres
   ```

2. **Check Database Connectivity from EMQX**:
   ```bash
   docker exec emqx ping iot-postgres
   ```

## 🔐 Dual SSL Certificate Issues

### Wrong Certificate Being Served

**Symptoms**: Browser shows RSA certificate when ECDSA expected (or vice versa)

**Diagnosis**:
```bash
# Check which certificate is served
openssl s_client -connect dashboard.thermalog.com.au:443 -servername dashboard.thermalog.com.au < /dev/null 2>/dev/null | openssl x509 -noout -text | grep "Public Key Algorithm"

# Should show "id-ecPublicKey" for ECDSA or "rsaEncryption" for RSA

# Verify both certificates exist
ls -la /root/nginx/*.pem
```

**Solutions**:
1. **Redeploy Both Certificates**:
   ```bash
   # Run dual SSL renewal script manually
   /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh
   ```

2. **Check Nginx Configuration**:
   ```bash
   docker exec nginx nginx -t
   docker exec nginx cat /etc/nginx/conf.d/default.conf | grep ssl_certificate
   ```

### Certificate Renewal Fails for One Type

**Symptoms**: ECDSA renews but RSA fails (or vice versa)

**Diagnosis**:
```bash
# Check both certificate expiry
certbot certificates

# Check renewal logs
tail -f /root/thermalog-ops/logs/maintenance/ssl-renewal.log
```

**Solutions**:
1. **Renew Failed Certificate Manually**:
   ```bash
   # For ECDSA
   certbot renew --force-renewal --cert-name dashboard.thermalog.com.au

   # For RSA
   certbot renew --force-renewal --cert-name dashboard.thermalog.com.au-rsa
   ```

2. **Regenerate Missing Certificate**:
   ```bash
   # Stop nginx
   docker stop nginx

   # Regenerate certificate (see docs/ssl-setup.md)
   # Then restart
   docker start nginx
   ```

## 📞 Getting Help

### Log Collection

Before seeking help, collect these logs:

```bash
# Create diagnostic bundle
mkdir -p /tmp/thermalog-debug
docker logs thermalog-backend > /tmp/thermalog-debug/backend.log
docker logs nginx > /tmp/thermalog-debug/nginx.log
docker ps -a > /tmp/thermalog-debug/containers.txt
docker inspect thermalog-backend > /tmp/thermalog-debug/backend-inspect.json
cp /var/log/letsencrypt/letsencrypt.log /tmp/thermalog-debug/
tar -czf thermalog-debug.tar.gz -C /tmp thermalog-debug/
```

### Support Checklist

- [ ] Container status (`docker ps -a`)
- [ ] Container logs (last 100 lines)
- [ ] System resources (`free -h`, `df -h`)
- [ ] Network connectivity tests
- [ ] SSL certificate status
- [ ] Environment configuration (sanitized)
- [ ] Recent changes or deployments