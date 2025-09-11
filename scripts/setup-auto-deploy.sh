#!/bin/bash

# Setup script for automated deployments

echo "Setting up automated deployment for Thermalog..."

# 1. Create log file
touch /root/deployment.log

# 2. Add cron job (check every 5 minutes)
CRON_CMD="/root/auto-deploy.sh >> /root/deployment-cron.log 2>&1"
CRON_JOB="*/5 * * * * $CRON_CMD"

# Check if cron job already exists
if ! crontab -l 2>/dev/null | grep -q "auto-deploy.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "✅ Cron job added - will check for updates every 5 minutes"
else
    echo "⚠️  Cron job already exists"
fi

# 3. Show current cron jobs
echo ""
echo "Current cron jobs:"
crontab -l

echo ""
echo "Setup complete! The system will now:"
echo "• Check GitHub for updates every 5 minutes"
echo "• Automatically deploy backend changes with health checks"
echo "• Automatically deploy frontend changes"
echo "• Rollback on failure"
echo ""
echo "Monitor logs at:"
echo "• /root/deployment.log - Main deployment log"
echo "• /root/deployment-cron.log - Cron execution log"
echo ""
echo "To disable auto-deployment, run: crontab -e and remove the auto-deploy.sh line"