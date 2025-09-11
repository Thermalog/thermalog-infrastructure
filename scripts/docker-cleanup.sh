#!/bin/bash

# Docker Cleanup Script
# Removes unnecessary Docker images while preserving current and backup images

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/root/docker-cleanup.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}     DOCKER CLEANUP - $(date)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

log "Starting Docker cleanup"

# Function to get size in human readable format (removed - not needed)

# Store initial disk usage
BEFORE_IMAGES=$(docker images -q | wc -l)
BEFORE_SIZE=$(docker system df | grep "Images" | awk '{print $3}' | sed 's/[^0-9.]//g')

echo -e "${YELLOW}Current Docker status:${NC}"
docker system df
echo ""

# 1. Remove stopped containers
echo -e "${YELLOW}Removing stopped containers...${NC}"
STOPPED_CONTAINERS=$(docker ps -a -q -f status=exited -f status=created)
if [ ! -z "$STOPPED_CONTAINERS" ]; then
    docker rm $STOPPED_CONTAINERS 2>/dev/null || true
    echo -e "${GREEN}✓ Removed stopped containers${NC}"
else
    echo "No stopped containers to remove"
fi

# 2. Remove dangling images (untagged)
echo -e "${YELLOW}Removing dangling images...${NC}"
DANGLING_IMAGES=$(docker images -f "dangling=true" -q)
if [ ! -z "$DANGLING_IMAGES" ]; then
    docker rmi $DANGLING_IMAGES 2>/dev/null || true
    echo -e "${GREEN}✓ Removed dangling images${NC}"
else
    echo "No dangling images to remove"
fi

# 3. Clean up old backup images (keep only last 3 for each service)
echo -e "${YELLOW}Cleaning old backup images...${NC}"
for SERVICE in backend frontend; do
    # Get all backup images sorted by creation date
    BACKUP_IMAGES=$(docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}" | \
                    grep "root-thermalog-$SERVICE" | \
                    grep -E "(backup-|auto-backup-)" | \
                    tail -n +4 | \
                    awk '{print $3}')
    
    if [ ! -z "$BACKUP_IMAGES" ]; then
        for IMAGE_ID in $BACKUP_IMAGES; do
            docker rmi $IMAGE_ID 2>/dev/null && \
            echo "  Removed old backup: $IMAGE_ID" || true
        done
    fi
done

# 4. Remove unused images (except current and recent backups)
echo -e "${YELLOW}Identifying unused images...${NC}"

# Get list of images in use by running containers
USED_IMAGES=$(docker ps --format "{{.Image}}" | sort -u)

# Get all image IDs
ALL_IMAGES=$(docker images -q | sort -u)

# Images to keep (current + last 3 backups of each service)
KEEP_IMAGES=""
for SERVICE in backend frontend; do
    # Current image
    KEEP_IMAGES="$KEEP_IMAGES $(docker images --format "{{.ID}}" root-thermalog-$SERVICE:latest 2>/dev/null || true)"
    
    # Last 3 backups
    KEEP_IMAGES="$KEEP_IMAGES $(docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}" | \
                                 grep "root-thermalog-$SERVICE" | \
                                 grep -E "(backup-|auto-backup-|last-stable)" | \
                                 head -n 3 | \
                                 awk '{print $3}')"
done

# Also keep nginx and base images
KEEP_IMAGES="$KEEP_IMAGES $(docker images --format "{{.ID}}" nginx:alpine node:20-alpine 2>/dev/null || true)"

# 5. Remove old build cache
echo -e "${YELLOW}Cleaning build cache...${NC}"
docker builder prune -f --filter "until=24h" 2>/dev/null || true
echo -e "${GREEN}✓ Cleaned build cache older than 24 hours${NC}"

# 6. Clean up volumes not used by any container
echo -e "${YELLOW}Cleaning unused volumes...${NC}"
UNUSED_VOLUMES=$(docker volume ls -qf dangling=true)
if [ ! -z "$UNUSED_VOLUMES" ]; then
    docker volume rm $UNUSED_VOLUMES 2>/dev/null || true
    echo -e "${GREEN}✓ Removed unused volumes${NC}"
else
    echo "No unused volumes to remove"
fi

# 7. Clean up unused networks (except default ones)
echo -e "${YELLOW}Cleaning unused networks...${NC}"
UNUSED_NETWORKS=$(docker network ls -q --filter "dangling=true" | grep -v bridge | grep -v host | grep -v none)
if [ ! -z "$UNUSED_NETWORKS" ]; then
    docker network rm $UNUSED_NETWORKS 2>/dev/null || true
    echo -e "${GREEN}✓ Removed unused networks${NC}"
else
    echo "No unused networks to remove"
fi

# Calculate space saved
AFTER_IMAGES=$(docker images -q | wc -l)
AFTER_SIZE=$(docker system df | grep "Images" | awk '{print $3}' | sed 's/[^0-9.]//g')

if [ -z "$AFTER_SIZE" ]; then
    AFTER_SIZE=$BEFORE_SIZE
fi

# Convert to MB for calculation
BEFORE_SIZE_MB=$(echo "$BEFORE_SIZE * 1024" | bc 2>/dev/null || echo "0")
AFTER_SIZE_MB=$(echo "$AFTER_SIZE * 1024" | bc 2>/dev/null || echo "0")
SAVED_SIZE_MB=$(echo "$BEFORE_SIZE_MB - $AFTER_SIZE_MB" | bc 2>/dev/null || echo "0")

# Format saved size
if [ "$SAVED_SIZE_MB" -gt 0 ]; then
    SAVED_SIZE_HUMAN="${SAVED_SIZE_MB}MB"
else
    SAVED_SIZE_HUMAN="0MB"
fi
REMOVED_IMAGES=$(($BEFORE_IMAGES - $AFTER_IMAGES))

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Cleanup Summary:${NC}"
echo -e "${GREEN}• Images removed: $REMOVED_IMAGES${NC}"
echo -e "${GREEN}• Space reclaimed: $SAVED_SIZE_HUMAN${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"

echo ""
echo -e "${YELLOW}Final Docker status:${NC}"
docker system df

log "Cleanup completed - Removed $REMOVED_IMAGES images, freed $SAVED_SIZE_HUMAN"

# Show what's still kept
echo ""
echo -e "${BLUE}Protected images (keeping):${NC}"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "(thermalog|nginx)" | head -n 10

exit 0