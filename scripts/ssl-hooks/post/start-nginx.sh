#!/bin/bash
# Start nginx after renewal
docker start nginx
echo "$(date): nginx started after renewal" >> /var/log/cert-deploy.log
