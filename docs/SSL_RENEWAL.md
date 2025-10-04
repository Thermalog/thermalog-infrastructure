# Dual SSL Certificate Auto-Renewal

## Overview

Thermalog infrastructure uses **dual SSL certificates** (ECDSA + RSA) with automated renewal via Let's Encrypt. This dual-certificate approach ensures maximum browser compatibility while providing modern security for supported clients.

The system uses a Docker-aware renewal process that safely stops nginx during renewal and automatically restarts it with both new certificates.

## Current Setup

### Dual Certificate Information
- **Domain**: `dashboard.thermalog.com.au`
- **Provider**: Let's Encrypt
- **Certificate Types**:
  - **ECDSA P-384** - Modern, efficient (preferred by modern browsers)
  - **RSA 4096-bit** - Legacy compatibility (for older browsers/systems)
- **Renewal Method**: Standalone HTTP challenge (both certificates)
- **Script**: `/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh`

### Auto-Renewal Schedule
- **Frequency**: Twice daily at 3:15 AM and 3:15 PM UTC
- **Renewal Threshold**: Only renews when <30 days remaining
- **Method**: Cron job automation
- **Log File**: `/root/thermalog-ops/logs/maintenance/ssl-renewal.log`

### Why Dual Certificates?
- **Modern Clients**: Use ECDSA for faster, more efficient cryptography
- **Legacy Support**: RSA ensures compatibility with older browsers and systems
- **Automatic Selection**: Nginx automatically serves the optimal certificate per client
- **No Performance Impact**: Both certificates are small and load quickly

## Installation

### 1. Deploy Dual SSL Renewal Script
```bash
# Script is deployed to thermalog-ops during setup
# Location: /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh
chmod +x /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh
```

### 2. Setup Cron Job
```bash
# Add to crontab (automated during deployment)
15 3,15 * * * /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh >> /root/thermalog-ops/logs/maintenance/ssl-renewal.log 2>&1
```

### 3. Verify Installation
```bash
# Check cron job is configured
crontab -l | grep ssl-renew-dual

# Test script syntax
bash -n /root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh

# Check log directory exists
ls -la /root/thermalog-ops/logs/maintenance/
```

## Dual SSL Renewal Process

### Automatic Renewal Flow
1. **Dual Certificate Check**
   - Checks BOTH certificate expiry dates (ECDSA + RSA)
   - Only proceeds if either certificate <30 days remaining
   - Logs all actions for comprehensive audit trail

2. **Docker-Safe Renewal**
   - Stops nginx container to free port 80
   - Renews ECDSA certificate (P-384 key)
   - Renews RSA certificate (4096-bit key)
   - Both renewals use standalone HTTP-01 challenge

3. **Dual Certificate Deployment**
   - Copies ECDSA certificates to nginx directory:
     - `fullchain-ecdsa.pem`
     - `privkey-ecdsa.pem`
   - Copies RSA certificates to nginx directory:
     - `fullchain-rsa.pem`
     - `privkey-rsa.pem`
   - Sets proper file permissions (644/600)

4. **Service Recovery**
   - Restarts nginx container with both certificates
   - Verifies container is running
   - Performs HTTPS connectivity test for both certificates

5. **Verification & Logging**
   - Tests HTTPS connectivity
   - Verifies nginx serves correct certificate per client
   - Logs both certificate expiry dates
   - Reports success/failure status to log file

### Manual Renewal
```bash
# Test dual renewal process (dry run for both certificates)
certbot renew --dry-run

# Run dual renewal script manually
/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh

# Force renewal of both certificates (for testing)
# ECDSA certificate
certbot renew --force-renewal --cert-name dashboard.thermalog.com.au

# RSA certificate
certbot renew --force-renewal --cert-name dashboard.thermalog.com.au-rsa
```

## Configuration

### Script Configuration
Script location: `/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh`

**Key Variables:**
```bash
DOMAIN="dashboard.thermalog.com.au"                      # Your domain
NGINX_CERT_DIR="/root/nginx"                             # Nginx certificate directory (via symlink to /root/Config/nginx)
LOG_FILE="/root/thermalog-ops/logs/maintenance/ssl-renewal.log"  # Log file location

# Certificate paths
ECDSA_CERT_PATH="/etc/letsencrypt/live/$DOMAIN"          # ECDSA certificate
RSA_CERT_PATH="/etc/letsencrypt/live/$DOMAIN-rsa"        # RSA certificate
```

### Nginx Integration
The script automatically:
- Stops nginx before renewal (frees port 80)
- Renews BOTH certificates (ECDSA + RSA)
- Copies both certificates to nginx directory
- Restarts nginx after successful renewal
- Verifies HTTPS connectivity with both certificates

## Monitoring

### Log Files
- **Main Log**: `/root/thermalog-ops/logs/maintenance/ssl-renewal.log` - Dual SSL renewal activity
- **Certbot Log**: `/var/log/letsencrypt/letsencrypt.log` - Detailed certbot logs
- **Cron Log**: Check `/root/thermalog-ops/logs/maintenance/` for cron execution

### Check Dual Certificate Status
```bash
# View all certificates (both ECDSA and RSA)
certbot certificates

# Check ECDSA certificate expiry
openssl x509 -in /root/nginx/fullchain-ecdsa.pem -text -noout | grep "Not After"

# Check RSA certificate expiry
openssl x509 -in /root/nginx/fullchain-rsa.pem -text -noout | grep "Not After"

# Test HTTPS connectivity
curl -I https://dashboard.thermalog.com.au

# View renewal logs
tail -f /root/thermalog-ops/logs/maintenance/ssl-renewal.log

# Check which certificate is served to client
openssl s_client -connect dashboard.thermalog.com.au:443 -servername dashboard.thermalog.com.au < /dev/null 2>/dev/null | openssl x509 -noout -text | grep -E "Public Key Algorithm|Signature Algorithm"
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