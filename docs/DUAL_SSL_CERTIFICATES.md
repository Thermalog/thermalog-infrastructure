# Dual SSL Certificate System

## Overview

Thermalog uses a **dual SSL certificate approach** with both ECDSA and RSA certificates to ensure maximum browser compatibility while providing optimal security and performance.

### Why Dual Certificates?

**Problem**: Different clients support different cryptographic algorithms
- **Modern browsers**: Support ECDSA (faster, smaller, more secure)
- **Older systems**: Only support RSA (larger, slower, but widely compatible)
- **IoT devices**: May require specific cipher suites

**Solution**: Nginx serves both certificates and automatically selects the best one for each client.

## Certificate Types

### ECDSA (Elliptic Curve)
- **Key Type**: ECDSA P-384 (secp384r1)
- **Certificate Name**: `dashboard.thermalog.com.au`
- **Advantages**:
  - Faster encryption/decryption
  - Smaller certificate size
  - Lower CPU usage
  - Modern cryptographic standard
- **Supported by**: Chrome 49+, Firefox 45+, Safari 10+, Edge 14+

### RSA (Rivest-Shamir-Adleman)
- **Key Size**: 4096-bit
- **Certificate Name**: `dashboard.thermalog.com.au-rsa`
- **Advantages**:
  - Universal compatibility
  - Supported by legacy systems
  - Trusted by older browsers
- **Supported by**: All browsers, legacy systems, older IoT devices

## How It Works

### 1. Client Connection
```
Client → HTTPS Request → Nginx
```

### 2. TLS Handshake
```
1. Client sends supported cipher suites
2. Nginx analyzes client capabilities
3. Nginx selects optimal certificate:
   - ECDSA if client supports elliptic curve
   - RSA if client only supports RSA
4. TLS connection established with best certificate
```

### 3. Automatic Selection
Nginx uses `ssl_certificate` directives with both certificates:
```nginx
# Nginx automatically chooses based on client
ssl_certificate /etc/ssl/certs/fullchain-ecdsa.pem;
ssl_certificate_key /etc/ssl/certs/privkey-ecdsa.pem;

ssl_certificate /etc/ssl/certs/fullchain-rsa.pem;
ssl_certificate_key /etc/ssl/certs/privkey-rsa.pem;
```

## Certificate Locations

### Let's Encrypt Storage
```
/etc/letsencrypt/
├── live/
│   ├── dashboard.thermalog.com.au/           # ECDSA
│   │   ├── fullchain.pem
│   │   ├── privkey.pem
│   │   ├── cert.pem
│   │   └── chain.pem
│   └── dashboard.thermalog.com.au-rsa/       # RSA
│       ├── fullchain.pem
│       ├── privkey.pem
│       ├── cert.pem
│       └── chain.pem
└── renewal/
    ├── dashboard.thermalog.com.au.conf       # ECDSA config
    └── dashboard.thermalog.com.au-rsa.conf   # RSA config
```

### Nginx Deployment Location
```
/root/nginx/                          # Actual: /root/Config/nginx/ (via symlink)
├── fullchain-ecdsa.pem              # ECDSA certificate chain
├── privkey-ecdsa.pem                # ECDSA private key (600 perms)
├── fullchain-rsa.pem                # RSA certificate chain
└── privkey-rsa.pem                  # RSA private key (600 perms)
```

## Generation

### Initial Setup

**ECDSA Certificate**:
```bash
certbot certonly --standalone \
  -d dashboard.thermalog.com.au \
  --key-type ecdsa \
  --elliptic-curve secp384r1 \
  --non-interactive \
  --agree-tos \
  --email admin@thermalog.com.au
```

**RSA Certificate**:
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

### Automated Renewal

**Script**: `/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh`

**Process**:
1. Check expiry of both certificates
2. Stop nginx (frees port 80)
3. Renew ECDSA if <30 days remaining
4. Renew RSA if <30 days remaining
5. Deploy both to nginx directory
6. Restart nginx
7. Verify HTTPS connectivity

**Schedule**: Twice daily at 3:15 AM and 3:15 PM UTC via cron

## Nginx Configuration

### Complete SSL Block
```nginx
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name dashboard.thermalog.com.au;

    # Dual SSL certificates
    ssl_certificate /etc/ssl/certs/fullchain-ecdsa.pem;
    ssl_certificate_key /etc/ssl/certs/privkey-ecdsa.pem;
    ssl_certificate /etc/ssl/certs/fullchain-rsa.pem;
    ssl_certificate_key /etc/ssl/certs/privkey-rsa.pem;

    # SSL protocols
    ssl_protocols TLSv1.2 TLSv1.3;

    # Cipher suites (supports both ECDSA and RSA)
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';

    # Let client choose (modern approach)
    ssl_prefer_server_ciphers off;

    # OCSP stapling for both
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_trusted_certificate /etc/ssl/certs/fullchain-ecdsa.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Application configuration...
}
```

## Monitoring

### Check Active Certificate
```bash
# Test from external client
openssl s_client -connect dashboard.thermalog.com.au:443 -servername dashboard.thermalog.com.au < /dev/null 2>/dev/null | openssl x509 -noout -text | grep "Public Key Algorithm"

# ECDSA shows: "id-ecPublicKey"
# RSA shows: "rsaEncryption"
```

### Verify Both Certificates
```bash
# Check ECDSA expiry
openssl x509 -in /root/nginx/fullchain-ecdsa.pem -noout -enddate

# Check RSA expiry
openssl x509 -in /root/nginx/fullchain-rsa.pem -noout -enddate

# List all certificates
certbot certificates
```

### Test Client Compatibility
```bash
# Force ECDSA (modern client)
openssl s_client -connect dashboard.thermalog.com.au:443 -cipher ECDHE-ECDSA-AES128-GCM-SHA256

# Force RSA (legacy client)
openssl s_client -connect dashboard.thermalog.com.au:443 -cipher ECDHE-RSA-AES128-GCM-SHA256
```

## Browser Compatibility

### ECDSA Support
- ✅ Chrome 49+ (2016)
- ✅ Firefox 45+ (2016)
- ✅ Safari 10+ (2016)
- ✅ Edge 14+ (2016)
- ✅ iOS Safari 10+ (2016)
- ✅ Android Chrome 49+ (2016)

### RSA Fallback
- ✅ All browsers (100% coverage)
- ✅ Internet Explorer 11
- ✅ Legacy Android devices
- ✅ Older IoT devices

## Performance Benefits

### ECDSA Advantages
- **30-40% faster** TLS handshake
- **50% smaller** certificate size
- **Lower CPU usage** on server
- **Better mobile performance**

### Comparison
| Metric | ECDSA P-384 | RSA 4096 |
|--------|-------------|----------|
| Certificate Size | ~500 bytes | ~1600 bytes |
| Handshake Speed | Fast | Moderate |
| CPU Usage | Low | Higher |
| Security Level | 192-bit | 128-bit |

## Troubleshooting

### Certificate Mismatch
**Problem**: Nginx serves wrong certificate

**Solution**:
```bash
# Check certificate order in config
docker exec nginx cat /etc/nginx/conf.d/default.conf | grep ssl_certificate

# ECDSA should be listed first for preference
# Restart nginx
docker restart nginx
```

### Renewal Fails for One Type
**Problem**: ECDSA renews but RSA fails

**Solution**:
```bash
# Check certbot logs
tail -f /var/log/letsencrypt/letsencrypt.log

# Manually renew failed certificate
certbot renew --force-renewal --cert-name dashboard.thermalog.com.au-rsa

# Run deployment script
/root/thermalog-ops/scripts/maintenance/ssl-renew-dual.sh
```

### Client Gets Wrong Certificate
**Problem**: Modern browser receives RSA instead of ECDSA

**Solution**:
```bash
# Verify cipher order in nginx config
# ECDSA ciphers should be listed first
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256...';

# Reload nginx
docker exec nginx nginx -s reload
```

## Security Considerations

### Certificate Storage
- **Private keys**: 600 permissions (root only)
- **Public certificates**: 644 permissions (world-readable)
- **Backup**: Both certificates included in daily backups

### Renewal Security
- **Port 80 access**: Required for HTTP-01 challenge
- **Automated process**: No manual intervention needed
- **Validation**: Let's Encrypt validates domain ownership

### Best Practices
1. Keep both certificates synchronized (renew together)
2. Monitor expiry dates for both
3. Test both certificate types after renewal
4. Maintain proper file permissions
5. Regular security audits

## Migration from Single to Dual

If upgrading from single certificate:

1. **Generate second certificate type**
2. **Update nginx configuration** with both
3. **Test with both cipher types**
4. **Update renewal automation**
5. **Monitor for issues**

See [ssl-setup.md](ssl-setup.md) for detailed setup instructions.

---

For renewal automation, see [SSL_RENEWAL.md](SSL_RENEWAL.md)
For troubleshooting, see [troubleshooting.md](troubleshooting.md)
