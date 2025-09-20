#!/bin/bash

# Thermalog Encrypted Backup Extraction Script
# Decrypts and extracts encrypted server backup archives

set -e

# Configuration
ENCRYPTION_KEY="ThermalogDigital!@#$"
BACKUP_DIR="/root/thermalog-infrastructure/backups"
EXTRACT_DIR="/tmp/thermalog_backup_extraction"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}🔓 Thermalog Backup Extraction Tool${NC}"
    echo -e "${BLUE}====================================${NC}"
    echo
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

show_usage() {
    echo "Usage: $0 [OPTIONS] <encrypted_backup_file>"
    echo
    echo "Options:"
    echo "  -o, --output-dir DIR    Extract to specific directory (default: ${EXTRACT_DIR})"
    echo "  -l, --list             List available backup files"
    echo "  -v, --verify           Verify backup integrity without extracting"
    echo "  -h, --help             Show this help message"
    echo
    echo "Examples:"
    echo "  $0 thermalog_server_backup_20250920_170516_encrypted.tar.gz.enc"
    echo "  $0 -o /tmp/restore backup.tar.gz.enc"
    echo "  $0 -l                  # List available backups"
    echo "  $0 -v backup.tar.gz.enc # Verify backup integrity"
}

list_backups() {
    echo -e "${BLUE}📋 Available Backup Files:${NC}"
    echo "=========================="
    
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A $BACKUP_DIR/*.enc 2>/dev/null)" ]; then
        for backup in "$BACKUP_DIR"/*.enc; do
            if [ -f "$backup" ]; then
                local filename=$(basename "$backup")
                local size=$(du -h "$backup" | cut -f1)
                local date=$(stat -c %y "$backup" | cut -d' ' -f1,2 | cut -d'.' -f1)
                echo -e "${GREEN}📁 $filename${NC}"
                echo -e "   Size: $size"
                echo -e "   Created: $date"
                echo
            fi
        done
    else
        print_warning "No encrypted backup files found in $BACKUP_DIR"
    fi
}

verify_backup() {
    local encrypted_file="$1"
    local temp_file="/tmp/verify_$(basename "$encrypted_file" .enc)"
    
    echo -e "${BLUE}🔍 Verifying backup integrity...${NC}"
    
    # Try to decrypt
    if openssl enc -aes-256-cbc -d -in "$encrypted_file" -out "$temp_file" -pass pass:"$ENCRYPTION_KEY" 2>/dev/null; then
        print_success "Decryption successful"
        
        # Verify it's a valid tar.gz
        if tar -tzf "$temp_file" >/dev/null 2>&1; then
            print_success "Archive structure valid"
            
            # Show archive contents summary
            local file_count=$(tar -tzf "$temp_file" | wc -l)
            local archive_size=$(du -h "$temp_file" | cut -f1)
            
            echo
            echo -e "${BLUE}📊 Archive Information:${NC}"
            echo "Files/directories: $file_count"
            echo "Uncompressed size: $archive_size"
            
            # Show top-level directories
            echo
            echo -e "${BLUE}📁 Top-level contents:${NC}"
            tar -tzf "$temp_file" | head -20 | sed 's/^/  /'
            
            if [ $file_count -gt 20 ]; then
                echo "  ... and $((file_count - 20)) more files"
            fi
            
        else
            print_error "Archive appears to be corrupted"
            rm -f "$temp_file"
            return 1
        fi
        
        rm -f "$temp_file"
        print_success "Backup verification completed successfully"
        return 0
    else
        print_error "Failed to decrypt backup - check encryption key"
        rm -f "$temp_file"
        return 1
    fi
}

extract_backup() {
    local encrypted_file="$1"
    local output_dir="$2"
    local temp_file="/tmp/decrypt_$(basename "$encrypted_file" .enc)"
    
    echo -e "${BLUE}🔓 Extracting encrypted backup...${NC}"
    echo "Source: $encrypted_file"
    echo "Output: $output_dir"
    echo
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Decrypt the file
    echo "🔐 Decrypting backup archive..."
    if ! openssl enc -aes-256-cbc -d -in "$encrypted_file" -out "$temp_file" -pass pass:"$ENCRYPTION_KEY"; then
        print_error "Failed to decrypt backup file"
        rm -f "$temp_file"
        return 1
    fi
    
    print_success "Decryption completed"
    
    # Extract the archive
    echo "📦 Extracting archive..."
    if tar -xzf "$temp_file" -C "$output_dir"; then
        print_success "Extraction completed"
        
        # Show extraction summary
        local extracted_size=$(du -sh "$output_dir" | cut -f1)
        local file_count=$(find "$output_dir" -type f | wc -l)
        
        echo
        echo -e "${BLUE}📊 Extraction Summary:${NC}"
        echo "Extracted to: $output_dir"
        echo "Total size: $extracted_size"
        echo "Files extracted: $file_count"
        
        # Show the manifest if it exists
        local manifest_file=$(find "$output_dir" -name "BACKUP_MANIFEST.txt" -type f | head -1)
        if [ -f "$manifest_file" ]; then
            echo
            echo -e "${BLUE}📋 Backup Manifest:${NC}"
            cat "$manifest_file"
        fi
        
        # Cleanup
        rm -f "$temp_file"
        
        print_success "Backup extraction completed successfully!"
        echo
        echo -e "${YELLOW}💡 Next Steps:${NC}"
        echo "1. Review the extracted files in: $output_dir"
        echo "2. Check the BACKUP_MANIFEST.txt for restoration instructions"
        echo "3. Copy files to their appropriate locations as needed"
        
        return 0
    else
        print_error "Failed to extract archive"
        rm -f "$temp_file"
        return 1
    fi
}

# Parse command line arguments
OUTPUT_DIR="$EXTRACT_DIR"
VERIFY_ONLY=false
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        -v|--verify)
            VERIFY_ONLY=true
            shift
            ;;
        -h|--help)
            print_header
            show_usage
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            BACKUP_FILE="$1"
            shift
            ;;
    esac
done

print_header

# Handle list option
if [ "$LIST_ONLY" = true ]; then
    list_backups
    exit 0
fi

# Validate backup file argument
if [ -z "$BACKUP_FILE" ]; then
    print_error "Please specify a backup file to extract"
    echo
    show_usage
    exit 1
fi

# Check if file exists (try relative and absolute paths)
if [ ! -f "$BACKUP_FILE" ]; then
    # Try in backup directory
    if [ -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
        BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
    else
        print_error "Backup file not found: $BACKUP_FILE"
        echo
        echo "Available backups:"
        list_backups
        exit 1
    fi
fi

# Verify it's an encrypted file
if [[ ! "$BACKUP_FILE" =~ \.enc$ ]]; then
    print_warning "File doesn't have .enc extension - are you sure it's encrypted?"
fi

# Check if openssl is available
if ! command -v openssl &> /dev/null; then
    print_error "OpenSSL is required but not installed"
    exit 1
fi

# Perform verification or extraction
if [ "$VERIFY_ONLY" = true ]; then
    verify_backup "$BACKUP_FILE"
else
    extract_backup "$BACKUP_FILE" "$OUTPUT_DIR"
fi