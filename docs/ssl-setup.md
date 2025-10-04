# Dual SSL Certificate Setup and Management

This guide covers dual SSL certificate (ECDSA + RSA) setup, management, and troubleshooting for the Thermalog application.

## 🔒 Overview

The Thermalog infrastructure uses **dual Let's Encrypt SSL certificates** with automatic renewal and Docker integration:
- **ECDSA P-384** - Modern, efficient cryptography for current browsers
- **RSA 4096-bit** - Legacy compatibility for older browsers and systems

This dual-certificate approach ensures maximum compatibility while providing optimal security and performance.

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

2. **Generate ECDSA SSL certificate**:
   ```bash
   certbot certonly --standalone \
     -d dashboard.thermalog.com.au \
     --key-type ecdsa \
     --elliptic-curve secp384r1 \
     --non-interactive \
     --agree-tos \
     --email admin@thermalog.com.au
   ```

3. **Generate RSA SSL certificate** (for legacy compatibility):
   ```bash
   certbot certonly --standalone \
     -d dashboard.thermalog.com.au \
     --cert-name dashboard.thermalog.com.au-rsa \
     --key-type rsa \
     --rsa-key-size 4096 \
     --non-interactive \
     --agree-tos \
     --email admin@thermalog.com.au
   ```

4. **Deploy dual certificates to nginx**:
   ```bash
   # Copy ECDSA certificates
   cp /etc/letsencrypt/live/dashboard.thermalog.com.au/fullchain.pem /root/nginx/fullchain-ecdsa.pem
   cp /etc/letsencrypt/live/dashboard.thermalog.com.au/privkey.pem /root/nginx/privkey-ecdsa.pem

   # Copy RSA certificates
   cp /etc/letsencrypt/live/dashboard.thermalog.com.au-rsa/fullchain.pem /root/nginx/fullchain-rsa.pem
   cp /etc/letsencrypt/live/dashboard.thermalog.com.au-rsa/privkey.pem /root/nginx/privkey-rsa.pem

   # Set permissions
   chmod 644 /root/nginx/fullchain-*.pem
   chmod 600 /root/nginx/privkey-*.pem
   ```

5. **Start nginx with dual SSL**:
   ```bash
   docker start nginx
   ```

## 🔄 Automatic Renewal System

### How It Works

The automatic renewal system uses a **cron-based approach** with the dual SSL renewal script:

**Script**: `/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh`

**Renewal Process**:
1. Checks expiry for BOTH certificates (ECDSA + RSA)
2. Stops nginx container (frees port 80)
3. Renews ECDSA certificate if <30 days remaining
4. Renews RSA certificate if <30 days remaining
5. Copies both certificates to nginx directory
6. Restarts nginx container
7. Verifies HTTPS connectivity
8. Logs results to `/root/thermalog-ops/logs/maintenance/ssl-renewal.log`

### Renewal Schedule

- **Method**: Cron job (simple and reliable)
- **Frequency**: Twice daily at 3:15 AM and 3:15 PM UTC
- **Trigger**: Only renews when <30 days remaining
- **Certificates**: Both ECDSA and RSA renewed together
- **Downtime**: ~30-60 seconds during renewal
- **Log**: `/root/thermalog-ops/logs/maintenance/ssl-renewal.log`

### Verification

```bash
# Check cron job is configured
crontab -l | grep ssl-renew-dual

# Test dual renewal process
certbot renew --dry-run

# Check renewal logs
tail -f /root/thermalog-ops/logs/maintenance/ssl-renewal.log

# Verify both certificates exist
ls -la /root/nginx/*.pem
```

## 📁 Dual Certificate Files

### Location Structure
```
/etc/letsencrypt/
├── live/dashboard.thermalog.com.au/           # ECDSA certificate
│   ├── fullchain.pem    -> ../../archive/.../fullchain1.pem
│   ├── privkey.pem      -> ../../archive/.../privkey1.pem
│   ├── cert.pem         -> ../../archive/.../cert1.pem
│   └── chain.pem        -> ../../archive/.../chain1.pem
├── live/dashboard.thermalog.com.au-rsa/       # RSA certificate
│   ├── fullchain.pem    -> ../../archive/.../fullchain1.pem
│   ├── privkey.pem      -> ../../archive/.../privkey1.pem
│   ├── cert.pem         -> ../../archive/.../cert1.pem
│   └── chain.pem        -> ../../archive/.../chain1.pem
├── archive/dashboard.thermalog.com.au/        # ECDSA archive
│   └── [ECDSA certificate files]
├── archive/dashboard.thermalog.com.au-rsa/    # RSA archive
│   └── [RSA certificate files]
├── renewal/dashboard.thermalog.com.au.conf    # ECDSA renewal config
└── renewal/dashboard.thermalog.com.au-rsa.conf # RSA renewal config
```

### Nginx Certificate Directory

Dual certificates deployed to nginx:
```bash
/root/nginx/                                    # Actual: /root/Config/nginx/ (via symlink)
├── fullchain-ecdsa.pem    # ECDSA certificate chain
├── privkey-ecdsa.pem      # ECDSA private key (600 permissions)
├── fullchain-rsa.pem      # RSA certificate chain
└── privkey-rsa.pem        # RSA private key (600 permissions)
```

## 🔧 Configuration Files

### Nginx Dual SSL Configuration

Located in `/root/Config/nginx/default.conf`:

```nginx
server {
    listen 443 ssl;
    server_name dashboard.thermalog.com.au;

    # Dual SSL Certificate files (ECDSA + RSA)
    # ECDSA certificate (preferred by modern clients)
    ssl_certificate /etc/ssl/certs/fullchain-ecdsa.pem;
    ssl_certificate_key /etc/ssl/certs/privkey-ecdsa.pem;

    # RSA certificate (fallback for legacy clients)
    ssl_certificate /etc/ssl/certs/fullchain-rsa.pem;
    ssl_certificate_key /etc/ssl/certs/privkey-rsa.pem;

    # SSL Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers off;

    # Nginx automatically selects the best certificate for each client
    # Modern browsers get ECDSA, older systems get RSA

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