#!/bin/bash
# Install SSL renewal hooks for automated certificate deployment

set -e

echo "Installing SSL renewal hooks..."

# Create hook directories
sudo mkdir -p /etc/letsencrypt/renewal-hooks/{pre,post,deploy}

# Copy hook scripts
sudo cp ssl-hooks/pre/stop-nginx.sh /etc/letsencrypt/renewal-hooks/pre/
sudo cp ssl-hooks/post/start-nginx.sh /etc/letsencrypt/renewal-hooks/post/
sudo cp ssl-hooks/deploy/docker-nginx.sh /etc/letsencrypt/renewal-hooks/deploy/

# Make scripts executable
sudo chmod +x /etc/letsencrypt/renewal-hooks/pre/stop-nginx.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/post/start-nginx.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/docker-nginx.sh

echo "SSL renewal hooks installed successfully!"
echo "Certificate renewals will now automatically deploy to nginx container."