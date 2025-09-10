# SSL Certificate Setup and Management

This guide covers SSL certificate setup, management, and troubleshooting for the Thermalog application.

## 🔒 Overview

The Thermalog infrastructure uses Let's Encrypt SSL certificates with automatic renewal and Docker integration.

## 🚀 Initial SSL Setup

### Automatic Setup
The `setup-server.sh` script handles SSL automatically:

```bash
./scripts/setup-server.sh
```

### Manual Setup

1. **Stop nginx to free port 80**:
   ```bash
   docker stop nginx
   ```

2. **Generate SSL certificate**:
   ```bash
   certbot certonly --standalone \
     -d dashboard.thermalog.com.au \
     --non-interactive \
     --agree-tos \
     --email admin@thermalog.com.au
   ```

3. **Install renewal hooks**:
   ```bash
   ./scripts/install-ssl-hooks.sh
   ```

4. **Start nginx with SSL**:
   ```bash
   docker start nginx
   ```

## 🔄 Automatic Renewal System

### How It Works

The automatic renewal system uses three hooks:

1. **Pre-hook** (`scripts/ssl-hooks/pre/stop-nginx.sh`):
   - Stops nginx container before renewal
   - Frees port 80 for Let's Encrypt validation

2. **Post-hook** (`scripts/ssl-hooks/post/start-nginx.sh`):
   - Starts nginx container after renewal
   - Restores service availability

3. **Deploy-hook** (`scripts/ssl-hooks/deploy/docker-nginx.sh`):
   - Copies new certificates to nginx container
   - Reloads nginx configuration
   - Logs deployment status

### Renewal Schedule

- **Timer**: Runs twice daily (systemd timer)
- **Trigger**: 30 days before expiration
- **Method**: Let's Encrypt ACME standalone
- **Downtime**: ~30 seconds during renewal

### Verification

```bash
# Check renewal timer status
systemctl list-timers | grep certbot

# Test renewal process
certbot renew --dry-run

# Check deployment logs
cat /var/log/cert-deploy.log
```

## 📁 Certificate Files

### Location Structure
```
/etc/letsencrypt/
├── live/dashboard.thermalog.com.au/
│   ├── fullchain.pem    -> ../../archive/.../fullchain1.pem
│   ├── privkey.pem      -> ../../archive/.../privkey1.pem
│   ├── cert.pem         -> ../../archive/.../cert1.pem
│   └── chain.pem        -> ../../archive/.../chain1.pem
├── archive/dashboard.thermalog.com.au/
│   ├── fullchain1.pem   # Certificate + intermediate chain
│   ├── privkey1.pem     # Private key
│   ├── cert1.pem        # Certificate only
│   └── chain1.pem       # Intermediate chain
└── renewal/dashboard.thermalog.com.au.conf
```

### Docker Integration

Certificates are copied to the nginx container:
```bash
# In container paths:
/etc/ssl/certs/fullchain.pem   # Full certificate chain
/etc/ssl/certs/privkey.pem     # Private key
```

## 🔧 Configuration Files

### Nginx SSL Configuration

Located in `nginx/default.conf`:

```nginx
server {
    listen 443 ssl;
    server_name dashboard.thermalog.com.au;

    # SSL Certificate files
    ssl_certificate /etc/ssl/certs/fullchain.pem;
    ssl_certificate_key /etc/ssl/certs/privkey.pem;

    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers off;

    # Your application configuration...
}
```

### Certbot Renewal Configuration

Located in `/etc/letsencrypt/renewal/dashboard.thermalog.com.au.conf`:

```ini
version = 2.11.0
archive_dir = /etc/letsencrypt/archive/dashboard.thermalog.com.au
cert = /etc/letsencrypt/live/dashboard.thermalog.com.au/cert.pem
privkey = /etc/letsencrypt/live/dashboard.thermalog.com.au/privkey.pem
chain = /etc/letsencrypt/live/dashboard.thermalog.com.au/chain.pem
fullchain = /etc/letsencrypt/live/dashboard.thermalog.com.au/fullchain.pem

[renewalparams]
authenticator = standalone
installer = None
account = 93f69f4aa29005bf15ab75afbba1d3ec
server = https://acme-v02.api.letsencrypt.org/directory
```

## 🛠️ Manual Operations

### Force Renewal
```bash
# Stop nginx
docker stop nginx

# Force certificate renewal
certbot renew --force-renewal --cert-name dashboard.thermalog.com.au

# Deploy new certificate
/etc/letsencrypt/renewal-hooks/deploy/docker-nginx.sh

# Start nginx
docker start nginx
```

### Certificate Information
```bash
# List all certificates
certbot certificates

# Check certificate details
openssl x509 -in /etc/letsencrypt/live/dashboard.thermalog.com.au/fullchain.pem -text -noout

# Check certificate expiry
echo | openssl s_client -servername dashboard.thermalog.com.au -connect dashboard.thermalog.com.au:443 2>/dev/null | openssl x509 -dates -noout
```

### Revoke Certificate
```bash
# If you need to revoke a certificate
certbot revoke --cert-path /etc/letsencrypt/live/dashboard.thermalog.com.au/cert.pem
```

## 🚨 Troubleshooting

### Common Issues

#### 1. Port 80 Already in Use
```bash
# Error: "Address already in use"
# Solution: Stop nginx before renewal
docker stop nginx
certbot renew --force-renewal
docker start nginx
```

#### 2. Certificate Not Deployed to Container
```bash
# Check if deployment hook ran
cat /var/log/cert-deploy.log

# Manual deployment
docker cp /etc/letsencrypt/archive/dashboard.thermalog.com.au/fullchain1.pem nginx:/etc/ssl/certs/fullchain.pem
docker cp /etc/letsencrypt/archive/dashboard.thermalog.com.au/privkey1.pem nginx:/etc/ssl/certs/privkey.pem
docker exec nginx nginx -s reload
```

#### 3. Domain Validation Failures
```bash
# Check domain DNS resolution
dig dashboard.thermalog.com.au A

# Verify domain points to server
curl -I http://dashboard.thermalog.com.au
```

#### 4. Certificate Chain Issues
```bash
# Test SSL configuration
openssl s_client -connect dashboard.thermalog.com.au:443 -servername dashboard.thermalog.com.au

# Check certificate chain
echo | openssl s_client -connect dashboard.thermalog.com.au:443 -servername dashboard.thermalog.com.au 2>/dev/null | openssl x509 -noout -text
```

### Debug Commands

```bash
# Check certbot status
systemctl status snap.certbot.renew.timer

# View detailed renewal logs
tail -f /var/log/letsencrypt/letsencrypt.log

# Test nginx SSL configuration
docker exec nginx nginx -t

# Check certificate permissions
ls -la /etc/letsencrypt/live/dashboard.thermalog.com.au/
```

## 🔄 Backup and Recovery

### Backup SSL Certificates
```bash
# Create backup
tar -czf ssl_backup_$(date +%Y%m%d).tar.gz /etc/letsencrypt/

# Store in secure location
cp ssl_backup_*.tar.gz /root/backups/
```

### Restore SSL Certificates
```bash
# Extract backup
tar -xzf ssl_backup_YYYYMMDD.tar.gz

# Restore certificates
sudo cp -r etc/letsencrypt/* /etc/letsencrypt/

# Deploy to container
/etc/letsencrypt/renewal-hooks/deploy/docker-nginx.sh
```

## 🌐 Multiple Domains

### Adding Additional Domains
```bash
# Generate certificate for multiple domains
certbot certonly --standalone \
  -d dashboard.thermalog.com.au \
  -d api.thermalog.com.au \
  -d thermalog.com.au
```

### Wildcard Certificates
```bash
# Requires DNS validation
certbot certonly --manual \
  --preferred-challenges dns \
  -d "*.thermalog.com.au" \
  -d thermalog.com.au
```

## 📊 Monitoring

### Certificate Expiry Monitoring
```bash
# Check days until expiry
openssl x509 -enddate -noout -in /etc/letsencrypt/live/dashboard.thermalog.com.au/cert.pem

# Set up monitoring script
cat > /usr/local/bin/check-ssl-expiry.sh << 'EOF'
#!/bin/bash
CERT_FILE="/etc/letsencrypt/live/dashboard.thermalog.com.au/cert.pem"
EXPIRY_DATE=$(openssl x509 -enddate -noout -in "$CERT_FILE" | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( ($EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))

echo "SSL certificate expires in $DAYS_UNTIL_EXPIRY days"

if [ $DAYS_UNTIL_EXPIRY -lt 30 ]; then
    echo "WARNING: Certificate expires soon!"
fi
EOF

chmod +x /usr/local/bin/check-ssl-expiry.sh
```

## 🔐 Security Best Practices

### SSL Configuration Hardening
- Use only TLS 1.2 and 1.3
- Implement HSTS headers
- Use secure cipher suites
- Regular certificate rotation

### Access Control
- Restrict access to certificate files
- Use proper file permissions (600 for private keys)
- Regular security updates

### Monitoring and Alerting
- Monitor certificate expiry
- Alert on renewal failures
- Log all certificate operations