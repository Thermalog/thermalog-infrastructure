#!/bin/bash
# Auto-deployment hook for Docker nginx
CERT_NAME="dashboard.thermalog.com.au"
CONTAINER="nginx"

# Function to find latest certificate files
find_latest() {
    local cert_dir="/etc/letsencrypt/archive/$CERT_NAME"
    local latest=$(ls -t "$cert_dir"/$1*.pem 2>/dev/null | head -1)
    echo "$latest"
}

# Deploy certificates
FULLCHAIN=$(find_latest "fullchain")
PRIVKEY=$(find_latest "privkey")

if [[ -n "$FULLCHAIN" && -n "$PRIVKEY" ]]; then
    docker cp "$FULLCHAIN" "$CONTAINER":/etc/ssl/certs/fullchain.pem
    docker cp "$PRIVKEY" "$CONTAINER":/etc/ssl/certs/privkey.pem
    docker exec "$CONTAINER" nginx -s reload
    echo "$(date): Certificates deployed successfully" >> /var/log/cert-deploy.log
else
    echo "$(date): ERROR - Certificate files not found" >> /var/log/cert-deploy.log
fi
