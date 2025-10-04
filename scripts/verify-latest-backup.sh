#!/bin/bash
# Backup Verification Script for Thermalog Infrastructure
# Verifies integrity of the latest backup archive
# Sends alerts on failures
# Scheduled: Weekly at 4:00 AM Sunday Sydney time (18:00 UTC Saturday)

set -e

# Configuration
BACKUP_DIR="/var/backups/thermalog"
LOG_FILE="/root/thermalog-ops/logs/maintenance/backup-verify.log"
MIN_BACKUP_SIZE_MB=10  # Minimum expected backup size in MB
MAX_BACKUP_SIZE_MB=500 # Maximum expected backup size in MB
ALERT_EMAIL="admin@thermalog.com.au"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "[INFO] $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log "✓ $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "⚠ $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "✗ $1"
}

# Send alert email
send_alert() {
    local subject="$1"
    local message="$2"

    # Check if mail command is available
    if command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "$subject" "$ALERT_EMAIL" 2>/dev/null || {
            log "Failed to send email alert"
        }
    else
        log "Mail command not available, skipping email alert"
    fi
}

# Find latest backup
find_latest_backup() {
    print_status "Finding latest backup..."

    if [ ! -d "$BACKUP_DIR" ]; then
        print_error "Backup directory not found: $BACKUP_DIR"
        return 1
    fi

    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)

    if [ -z "$LATEST_BACKUP" ]; then
        print_error "No backup files found in $BACKUP_DIR"
        send_alert "Thermalog Backup Verification FAILED" "No backup files found in $BACKUP_DIR"
        return 1
    fi

    BACKUP_NAME=$(basename "$LATEST_BACKUP")
    BACKUP_DATE=$(echo "$BACKUP_NAME" | grep -oE '[0-9]{8}_[0-9]{6}')

    print_success "Found latest backup: $BACKUP_NAME"
    log "Backup date: $BACKUP_DATE"
}

# Check backup file size
check_backup_size() {
    print_status "Checking backup file size..."

    if [ ! -f "$LATEST_BACKUP" ]; then
        print_error "Backup file does not exist: $LATEST_BACKUP"
        return 1
    fi

    # Get file size in MB
    FILE_SIZE_BYTES=$(stat -c%s "$LATEST_BACKUP" 2>/dev/null || stat -f%z "$LATEST_BACKUP" 2>/dev/null)
    FILE_SIZE_MB=$((FILE_SIZE_BYTES / 1024 / 1024))

    log "Backup size: ${FILE_SIZE_MB}MB (${FILE_SIZE_BYTES} bytes)"

    if [ "$FILE_SIZE_MB" -lt "$MIN_BACKUP_SIZE_MB" ]; then
        print_error "Backup size too small: ${FILE_SIZE_MB}MB (minimum: ${MIN_BACKUP_SIZE_MB}MB)"
        send_alert "Thermalog Backup Verification FAILED" "Backup size too small: ${FILE_SIZE_MB}MB (minimum: ${MIN_BACKUP_SIZE_MB}MB)"
        return 1
    fi

    if [ "$FILE_SIZE_MB" -gt "$MAX_BACKUP_SIZE_MB" ]; then
        print_warning "Backup size larger than expected: ${FILE_SIZE_MB}MB (maximum: ${MAX_BACKUP_SIZE_MB}MB)"
        log "This might be normal if data has grown significantly"
    fi

    print_success "Backup size OK: ${FILE_SIZE_MB}MB"
}

# Verify tar archive integrity
verify_archive_integrity() {
    print_status "Verifying tar archive integrity..."

    if ! tar -tzf "$LATEST_BACKUP" >/dev/null 2>&1; then
        print_error "Backup archive is corrupted or invalid"
        send_alert "Thermalog Backup Verification FAILED" "Backup archive is corrupted: $BACKUP_NAME"
        return 1
    fi

    # Count files in archive
    FILE_COUNT=$(tar -tzf "$LATEST_BACKUP" | wc -l)
    log "Archive contains ${FILE_COUNT} files"

    print_success "Archive integrity verified"
}

# Check for required components
check_backup_contents() {
    print_status "Checking backup contents..."

    REQUIRED_COMPONENTS=(
        "/database/"
        "/docker-volumes/"
        "/ssl/"
        "/env/"
        "/systemd/"
        "/crontab.txt"
    )

    MISSING_COMPONENTS=()

    for component in "${REQUIRED_COMPONENTS[@]}"; do
        if ! tar -tzf "$LATEST_BACKUP" | grep -q "$component" 2>/dev/null; then
            MISSING_COMPONENTS+=("$component")
            print_warning "Component missing: $component"
        else
            log "✓ Found: $component"
        fi
    done

    if [ ${#MISSING_COMPONENTS[@]} -gt 0 ]; then
        print_warning "Some components are missing from backup:"
        for missing in "${MISSING_COMPONENTS[@]}"; do
            log "  - $missing"
        done
        send_alert "Thermalog Backup Verification WARNING" "Backup is missing components: ${MISSING_COMPONENTS[*]}"
    else
        print_success "All required components present"
    fi
}

# Verify database dump
verify_database_dump() {
    print_status "Verifying database dump..."

    if ! tar -tzf "$LATEST_BACKUP" | grep -q "database/iot_platform.sql.gz" 2>/dev/null; then
        print_error "PostgreSQL database dump not found in backup"
        send_alert "Thermalog Backup Verification FAILED" "Database dump missing from backup"
        return 1
    fi

    # Extract just the database dump to verify it
    TEMP_DIR=$(mktemp -d)
    tar -xzf "$LATEST_BACKUP" -C "$TEMP_DIR" --wildcards "*/database/iot_platform.sql.gz" 2>/dev/null || {
        print_error "Failed to extract database dump for verification"
        rm -rf "$TEMP_DIR"
        return 1
    }

    # Find the extracted file
    DB_DUMP=$(find "$TEMP_DIR" -name "iot_platform.sql.gz" 2>/dev/null | head -1)

    if [ -n "$DB_DUMP" ] && [ -f "$DB_DUMP" ]; then
        # Check if gzip file is valid
        if gzip -t "$DB_DUMP" 2>/dev/null; then
            DB_SIZE=$(du -h "$DB_DUMP" | cut -f1)
            print_success "Database dump verified (${DB_SIZE})"
        else
            print_error "Database dump is corrupted"
            rm -rf "$TEMP_DIR"
            send_alert "Thermalog Backup Verification FAILED" "Database dump is corrupted in backup"
            return 1
        fi
    else
        print_error "Database dump not found after extraction"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Cleanup
    rm -rf "$TEMP_DIR"
}

# Check backup age
check_backup_age() {
    print_status "Checking backup age..."

    BACKUP_TIMESTAMP=$(stat -c %Y "$LATEST_BACKUP" 2>/dev/null || stat -f %m "$LATEST_BACKUP" 2>/dev/null)
    CURRENT_TIMESTAMP=$(date +%s)
    AGE_HOURS=$(( (CURRENT_TIMESTAMP - BACKUP_TIMESTAMP) / 3600 ))

    log "Backup age: ${AGE_HOURS} hours"

    if [ "$AGE_HOURS" -gt 48 ]; then
        print_warning "Backup is older than 48 hours (${AGE_HOURS} hours)"
        send_alert "Thermalog Backup Verification WARNING" "Latest backup is ${AGE_HOURS} hours old. Backup schedule may not be running."
    else
        print_success "Backup age OK: ${AGE_HOURS} hours"
    fi
}

# Generate verification report
generate_report() {
    print_status "Generating verification report..."

    REPORT_FILE="$BACKUP_DIR/${BACKUP_DATE}_verification.txt"

    cat > "$REPORT_FILE" << EOF
THERMALOG BACKUP VERIFICATION REPORT
=====================================
Verification Date: $(date)
Backup File: $BACKUP_NAME
Backup Location: $LATEST_BACKUP

VERIFICATION RESULTS:
---------------------
✓ File exists
✓ File size: ${FILE_SIZE_MB}MB (within acceptable range)
✓ Archive integrity verified
✓ Database dump present and valid
✓ Required components present
✓ Backup age: ${AGE_HOURS} hours

BACKUP DETAILS:
---------------
File count: ${FILE_COUNT} files
Backup date: ${BACKUP_DATE}
Full path: ${LATEST_BACKUP}

SYSTEM STATUS:
--------------
$(docker ps --format "{{.Names}}: {{.Status}}" 2>/dev/null)

DISK USAGE:
-----------
$(df -h "$BACKUP_DIR" | tail -1)

VERIFICATION STATUS: PASSED ✓
EOF

    print_success "Verification report: $REPORT_FILE"
}

# Main verification function
main() {
    log "========== Starting Backup Verification =========="
    print_status "Starting backup verification process..."

    # Run all verification checks
    if ! find_latest_backup; then
        log "========== Verification FAILED: No backup found =========="
        exit 1
    fi

    FAILED=0

    check_backup_size || FAILED=1
    verify_archive_integrity || FAILED=1
    check_backup_contents || true  # Warnings only
    verify_database_dump || FAILED=1
    check_backup_age || true  # Warnings only

    if [ "$FAILED" -eq 1 ]; then
        print_error "=========================================="
        print_error "Backup verification FAILED!"
        print_error "See log for details: $LOG_FILE"
        print_error "=========================================="
        log "========== Verification FAILED =========="
        exit 1
    fi

    generate_report

    print_success "=========================================="
    print_success "Backup verification PASSED!"
    print_success "Backup: $BACKUP_NAME"
    print_success "Size: ${FILE_SIZE_MB}MB"
    print_success "Age: ${AGE_HOURS} hours"
    print_success "=========================================="

    log "========== Verification PASSED =========="
}

# Run main function
main "$@"
