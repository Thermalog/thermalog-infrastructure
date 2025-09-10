#!/bin/bash
# Stop nginx before renewal to free port 80
docker stop nginx
echo "$(date): nginx stopped for renewal" >> /var/log/cert-deploy.log
