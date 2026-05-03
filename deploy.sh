#!/bin/bash

# AIO-Pod Complete Deployment Script
# This script performs a complete deployment of AIO-Pod with nginx and SSL

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (Cloudflare + Origin cert paths)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR"
# shellcheck source=scripts/domain_constants.sh
source "${SCRIPT_DIR}/scripts/domain_constants.sh"
DOMAIN="$MCP_DOMAIN"
EMAIL="${DEPLOY_EMAIL:-admin@univoices.club}"

# Print colored text
print_info() {
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

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if we're in the right directory
    if [[ ! -f "nginx_ssl.conf" ]]; then
        print_error "nginx_ssl.conf not found. Please run this script from the project root."
        exit 1
    fi
    
    # Check if domain is reachable
    if ! nslookup "$DOMAIN" > /dev/null 2>&1; then
        print_warning "Domain $DOMAIN may not be properly configured"
        print_info "Please ensure DNS is pointing to this server's IP address"
    fi
    
    print_success "Prerequisites check completed"
}

# Make scripts executable
make_executable() {
    print_info "Making scripts executable..."
    
    chmod +x setup_nginx_ssl.sh
    chmod +x replace_ssl_cert.sh
    chmod +x start_aio_pod.sh
    chmod +x stop_aio_pod.sh
    
    print_success "Scripts made executable"
}

# Install nginx and SSL
install_nginx_ssl() {
    print_info "Installing nginx and SSL certificates..."
    
    # Run the nginx SSL setup script
    ./setup_nginx_ssl.sh
    
    if [[ $? -eq 0 ]]; then
        print_success "Nginx and SSL setup completed"
    else
        print_error "Nginx and SSL setup failed"
        exit 1
    fi
}

# Install system service
install_system_service() {
    print_info "Installing system service..."
    
    # Copy service file
    cp aio-pod.service /etc/systemd/system/
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable service
    systemctl enable aio-pod.service
    
    print_success "System service installed and enabled"
}

# Start services
start_services() {
    print_info "Starting services..."
    
    # Start nginx
    systemctl start nginx
    systemctl status nginx --no-pager
    
    # Start AIO-Pod services
    ./start_aio_pod.sh
    
    print_success "Services started"
}

# Test deployment
test_deployment() {
    print_info "Testing deployment..."
    
    # Test nginx
    if systemctl is-active --quiet nginx; then
        print_success "Nginx is running"
    else
        print_error "Nginx is not running"
        return 1
    fi
    
    # Test file server
    if curl -s "http://localhost:8001/health" | grep -q "healthy"; then
        print_success "File server is running"
    else
        print_warning "File server may not be running"
    fi
    
    # Test HTTPS
    if curl -s -k "https://$DOMAIN/health" | grep -q "healthy"; then
        print_success "HTTPS is working"
    else
        print_warning "HTTPS may not be working"
    fi
    
    # Test SSL certificate
    if openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" < /dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
        print_success "SSL certificate is valid"
    else
        print_warning "SSL certificate validation failed"
    fi
}

# Display final information
display_final_info() {
    echo
    print_success "AIO-Pod deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Domain: $DOMAIN"
    echo "HTTPS: https://$DOMAIN"
    echo "Health Check: https://$DOMAIN/health"
    echo "API Base: https://$DOMAIN/api/v1/"
    echo
    echo "=== Service Management ==="
    echo "Check status: systemctl status aio-pod"
    echo "Start services: systemctl start aio-pod"
    echo "Stop services: systemctl stop aio-pod"
    echo "Restart services: systemctl restart aio-pod"
    echo "View logs: journalctl -u aio-pod -f"
    echo
    echo "=== Nginx Management ==="
    echo "Check nginx status: systemctl status nginx"
    echo "Restart nginx: systemctl restart nginx"
    echo "View nginx logs: tail -f /var/log/nginx/access.log"
    echo
    echo "=== SSL (origin) ==="
    echo "Origin PEM: $CF_ORIGIN_CERT"
    echo "Origin KEY: $CF_ORIGIN_KEY"
    echo "Install/update: sudo ./replace_ssl_cert.sh"
    echo
    echo "=== API Endpoints ==="
    echo "File Upload: POST https://$DOMAIN/api/v1/upload/{type}"
    echo "File Download: GET https://$DOMAIN/api/v1/?type={type}&filename={filename}"
    echo "MCP Execute: POST https://$DOMAIN/api/v1/mcp/{filename}"
    echo
    echo "=== Troubleshooting ==="
    echo "Check service logs: journalctl -u aio-pod -n 50"
    echo "Check nginx logs: tail -f /var/log/nginx/error.log"
    echo "Test endpoints: curl -k https://$DOMAIN/health"
    echo
    print_info "Services will auto-start on system boot"
}

# Main execution
main() {
    print_info "Starting AIO-Pod complete deployment..."
    print_info "Domain: $DOMAIN"
    print_info "Email (notifications): $EMAIL"
    print_info "Workspace: $WORKSPACE_ROOT"
    echo
    
    check_root
    check_prerequisites
    make_executable
    install_nginx_ssl
    install_system_service
    start_services
    test_deployment
    display_final_info
}

# Run main function
main "$@" 