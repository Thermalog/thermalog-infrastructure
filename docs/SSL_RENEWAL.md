# SSL Certificate Auto-Renewal

## Overview

Thermalog infrastructure includes automated SSL certificate renewal using Let's Encrypt certificates. The system uses a Docker-aware renewal process that safely stops nginx during renewal and automatically restarts it with new certificates.

## Current Setup

### Certificate Information
- **Domain**: `dashboard.thermalog.com.au`
- **Provider**: Let's Encrypt
- **Certificate Type**: ECDSA
- **Renewal Method**: Standalone HTTP challenge

### Auto-Renewal Schedule
- **Frequency**: Twice daily at 3:15 AM and 3:15 PM UTC
- **Random Delay**: 0-60 minutes to prevent rate limiting
- **Renewal Threshold**: Only renews when <30 days remaining
- **Method**: Cron job (simple and reliable)

## Installation

### 1. Deploy SSL Renewal Script
```bash
# Copy script to server
scp scripts/ssl-renew.sh root@server:/root/
chmod +x /root/ssl-renew.sh
```

### 2. Setup Cron Job
```bash
# Add SSL renewal to crontab
echo "15 3,15 * * * sleep \$((RANDOM \\% 3600)) && /root/ssl-renew.sh >> /root/ssl-renewal.log 2>&1" >> /tmp/cron_ssl
crontab /tmp/cron_ssl
rm /tmp/cron_ssl
```

## SSL Renewal Process

### Automatic Renewal Flow
1. **Certificate Check**
   - Checks current certificate expiry
   - Only proceeds if <30 days remaining
   - Logs all actions for audit trail

2. **Docker-Safe Renewal**
   - Stops nginx container to free port 80
   - Runs certbot with standalone authenticator
   - Handles HTTP-01 challenges automatically

3. **Certificate Deployment**
   - Copies new certificates to nginx directory
   - Sets proper file permissions (644/600)
   - Updates both fullchain.pem and privkey.pem

4. **Service Recovery**
   - Restarts nginx container
   - Verifies container is running
   - Performs SSL connectivity test

5. **Verification & Logging**
   - Tests HTTPS connectivity
   - Logs new certificate expiry date
   - Reports success/failure status

### Manual Renewal
```bash
# Test renewal process (dry run)
certbot renew --dry-run

# Run renewal script manually
/root/ssl-renew.sh

# Force renewal (for testing)
certbot renew --force-renewal --standalone
```

## Configuration

### Script Configuration
Edit `/root/ssl-renew.sh` to customize:

```bash
DOMAIN="dashboard.thermalog.com.au"           # Your domain
CERT_PATH="/etc/letsencrypt/live/$DOMAIN"     # Certificate path
NGINX_CERT_DIR="/root/nginx"                  # Nginx certificate directory
LOG_FILE="/root/ssl-renewal.log"              # Log file location
```

### Nginx Integration
The script automatically:
- Stops nginx before renewal
- Copies certificates to nginx directory
- Restarts nginx after successful renewal
- Verifies SSL connectivity

## Monitoring

### Log Files
- **Main Log**: `/root/ssl-renewal.log` - SSL renewal activity
- **Certbot Log**: `/var/log/letsencrypt/letsencrypt.log` - Detailed certbot logs
- **Cron Log**: Check system cron logs for execution

### Check Certificate Status
```bash
# View certificate information
certbot certificates

# Check certificate expiry
openssl x509 -in /root/nginx/fullchain.pem -text -noout | grep "Not After"

# Test SSL connectivity
curl -I https://dashboard.thermalog.com.au

# View renewal logs
tail -f /root/ssl-renewal.log
```

### Health Monitoring
```bash
# Check if certificates are up to date
certbot certificates | grep "VALID"

# Test renewal process without making changes
certbot renew --dry-run

# Check nginx container status after renewal
docker ps | grep nginx
```

## Troubleshooting

### Common Issues

#### Port 80 Already in Use
If renewal fails due to port 80 being in use:
```bash
# Check what's using port 80
netstat -tlnp | grep :80

# Stop nginx manually if needed
docker stop nginx

# Run renewal manually
/root/ssl-renew.sh

# Restart nginx
docker start nginx
```

#### Certificate Not Updated
If nginx is still using old certificates:
```bash
# Check certificate files
ls -la /root/nginx/*.pem

# Compare certificate dates
openssl x509 -in /root/nginx/fullchain.pem -text -noout | grep "Not After"
openssl x509 -in /etc/letsencrypt/live/dashboard.thermalog.com.au/fullchain.pem -text -noout | grep "Not After"

# Copy certificates manually
cp /etc/letsencrypt/live/dashboard.thermalog.com.au/fullchain.pem /root/nginx/
cp /etc/letsencrypt/live/dashboard.thermalog.com.au/privkey.pem /root/nginx/
chmod 644 /root/nginx/fullchain.pem
chmod 600 /root/nginx/privkey.pem

# Restart nginx
docker compose restart nginx
```

#### Rate Limiting
If hitting Let's Encrypt rate limits:
- Wait before retrying (limits reset weekly)
- Use staging environment for testing
- Ensure random delays are working in cron

### Emergency Procedures

#### Manual Certificate Renewal
```bash
# Stop nginx
docker compose stop nginx

# Renew certificate
certbot renew --standalone --force-renewal

# Copy certificates
cp /etc/letsencrypt/live/dashboard.thermalog.com.au/fullchain.pem /root/nginx/
cp /etc/letsencrypt/live/dashboard.thermalog.com.au/privkey.pem /root/nginx/
chmod 644 /root/nginx/fullchain.pem
chmod 600 /root/nginx/privkey.pem

# Start nginx
docker compose start nginx
```

#### Rollback to Previous Certificate
```bash
# Check available certificates
ls -la /etc/letsencrypt/archive/dashboard.thermalog.com.au/

# Use previous certificate (adjust numbers as needed)
cp /etc/letsencrypt/archive/dashboard.thermalog.com.au/fullchain1.pem /root/nginx/fullchain.pem
cp /etc/letsencrypt/archive/dashboard.thermalog.com.au/privkey1.pem /root/nginx/privkey.pem

# Restart nginx
docker compose restart nginx
```

## Security Considerations

### File Permissions
- Certificate files: 644 (readable by nginx)
- Private keys: 600 (readable only by root)
- Scripts: 755 (executable by root)

### Access Control
- SSL renewal script runs as root
- Docker containers access certificates via volume mounts
- Certbot configuration protected with appropriate permissions

### Monitoring & Alerting
- Monitor certificate expiry dates
- Set up alerts for renewal failures
- Log all renewal attempts for audit

## Best Practices

### Testing
- Always test with `--dry-run` before live renewal
- Test renewal process after infrastructure changes
- Verify nginx starts successfully after renewal

### Maintenance
- Review renewal logs regularly
- Keep certbot updated via snap
- Monitor Let's Encrypt announcements for changes

### Backup
- Certificate files are automatically backed up by Let's Encrypt
- Consider additional backup of `/etc/letsencrypt/` directory
- Test certificate restoration procedures

## Integration with Docker

### Docker Compose Configuration
```yaml
nginx:
  volumes:
    - ./nginx/fullchain.pem:/etc/ssl/certs/fullchain.pem
    - ./nginx/privkey.pem:/etc/ssl/certs/privkey.pem
  restart: always
```

### Container Health Checks
The system includes health monitoring for nginx after certificate renewal to ensure service availability.

## Support

### Log Analysis
```bash
# Check recent SSL renewal activity
grep -A 10 -B 5 "SSL CERTIFICATE RENEWAL" /root/ssl-renewal.log

# Check certbot activity
grep ERROR /var/log/letsencrypt/letsencrypt.log

# Check nginx restart logs
docker logs nginx | grep -i ssl
```

### Getting Help
1. Check renewal logs first
2. Test with dry-run to isolate issues
3. Verify Docker container status
4. Check Let's Encrypt status page for service issues