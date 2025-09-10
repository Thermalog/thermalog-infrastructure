#!/bin/bash
# Complete server setup script for Thermalog
# Run this script on a fresh Ubuntu server to set up the entire infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOMAIN="dashboard.thermalog.com.au"
EMAIL="admin@thermalog.com.au"
APP_DIR="/root/thermalog-app"

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Update system
update_system() {
    print_status "Updating system packages..."
    apt update && apt upgrade -y
    print_success "System updated"
}

# Install Docker
install_docker() {
    print_status "Installing Docker..."
    
    # Install prerequisites
    apt install -y apt-transport-https ca-certificates curl software-properties-common
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker installed and started"
}

# Install Certbot
install_certbot() {
    print_status "Installing Certbot for SSL certificates..."
    snap install --classic certbot
    ln -sf /snap/bin/certbot /usr/bin/certbot
    print_success "Certbot installed"
}

# Clone application repositories
clone_repos() {
    print_status "Cloning application repositories..."
    
    mkdir -p $APP_DIR
    cd $APP_DIR
    
    # Clone your repositories (replace with actual repo URLs)
    git clone https://github.com/yourusername/Thermalog-Backend.git
    git clone https://github.com/yourusername/Thermalog-frontend.git
    git clone https://github.com/yourusername/thermalog-infrastructure.git
    
    print_success "Repositories cloned"
}

# Setup environment files
setup_environment() {
    print_status "Setting up environment files..."
    
    # Copy environment templates
    cp thermalog-infrastructure/configs/.env.backend.template Thermalog-Backend/.env
    cp thermalog-infrastructure/configs/.env.frontend.template Thermalog-frontend/.env
    
    print_warning "Please edit the .env files with your actual configuration:"
    print_warning "- $APP_DIR/Thermalog-Backend/.env"
    print_warning "- $APP_DIR/Thermalog-frontend/.env"
    
    read -p "Press Enter after you have configured the .env files..."
}

# Copy Docker configuration
setup_docker() {
    print_status "Setting up Docker configuration..."
    
    # Copy docker-compose files
    cp thermalog-infrastructure/docker/docker-compose.yml .
    cp thermalog-infrastructure/docker/docker-compose.prod.yml .
    
    # Copy nginx config
    mkdir -p nginx
    cp thermalog-infrastructure/nginx/default.conf nginx/
    
    print_success "Docker configuration set up"
}

# Build and start containers
start_application() {
    print_status "Building and starting application..."
    
    # Build and start containers
    docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
    
    print_success "Application started"
}

# Setup SSL certificate
setup_ssl() {
    print_status "Setting up SSL certificate..."
    
    # Stop nginx to free port 80
    docker stop nginx || true
    
    # Generate SSL certificate
    certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --email $EMAIL
    
    # Install SSL hooks
    cd thermalog-infrastructure
    ./scripts/install-ssl-hooks.sh
    
    # Start nginx with SSL
    docker start nginx
    
    print_success "SSL certificate configured"
}

# Main installation
main() {
    print_status "Starting Thermalog server setup..."
    
    check_root
    update_system
    install_docker
    install_certbot
    clone_repos
    setup_environment
    setup_docker
    start_application
    setup_ssl
    
    print_success "Thermalog server setup completed!"
    print_success "Your application should now be available at: https://$DOMAIN"
    
    print_status "Next steps:"
    echo "1. Verify your application is running: docker ps"
    echo "2. Check logs if needed: docker logs thermalog-backend"
    echo "3. Test SSL renewal: certbot renew --dry-run"
    echo "4. Monitor your application and set up additional monitoring as needed"
}

# Run main function
main "$@"