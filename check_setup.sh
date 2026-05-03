#!/bin/bash

# AIO-Pod Setup Check Script
# This script checks if all required files are present and properly configured

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR"
# shellcheck source=scripts/domain_constants.sh
source "${SCRIPT_DIR}/scripts/domain_constants.sh"
DOMAIN="$MCP_DOMAIN"

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

# Check if file exists and is executable
check_file() {
    local file=$1
    local description=$2
    local should_be_executable=${3:-false}
    
    if [[ -f "$file" ]]; then
        if [[ "$should_be_executable" == "true" ]]; then
            if [[ -x "$file" ]]; then
                print_success "$description exists and is executable"
            else
                print_warning "$description exists but is not executable"
                chmod +x "$file"
                print_info "Made $file executable"
            fi
        else
            print_success "$description exists"
        fi
    else
        print_error "$description is missing"
        return 1
    fi
}

# Check nginx configuration
check_nginx_conf() {
    print_info "Checking nginx configuration..."
    
    local nginx_src="nginx_ssl.conf"
    if [[ -f "$nginx_src" ]]; then
        if grep -q "$DOMAIN" "$nginx_src"; then
            print_success "$nginx_src contains domain $DOMAIN"
        else
            print_warning "$nginx_src exists but domain $DOMAIN not found"
        fi
        if grep -q "ssl_certificate" "$nginx_src"; then
            print_success "SSL configuration found in $nginx_src"
        else
            print_warning "SSL configuration not found in $nginx_src"
        fi
    else
        print_error "$nginx_src is missing"
        return 1
    fi
}

# Check system requirements
check_system() {
    print_info "Checking system requirements..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_success "Running as root"
    else
        print_warning "Not running as root (some operations may fail)"
    fi
    
    # Check if domain resolves
    if nslookup "$DOMAIN" > /dev/null 2>&1; then
        print_success "Domain $DOMAIN resolves"
    else
        print_warning "Domain $DOMAIN may not resolve properly"
    fi
    
    # Check if ports are available
    if ! lsof -i :80 > /dev/null 2>&1; then
        print_success "Port 80 is available"
    else
        print_warning "Port 80 is in use"
    fi
    
    if ! lsof -i :443 > /dev/null 2>&1; then
        print_success "Port 443 is available"
    else
        print_warning "Port 443 is in use"
    fi
}

# Check AIO-Pod services
check_aio_services() {
    print_info "Checking AIO-Pod services..."
    
    # Check if aio_server directory exists
    if [[ -d "aio_server" ]]; then
        print_success "aio_server directory exists"
        
        # Check if server.py exists
        if [[ -f "aio_server/server.py" ]]; then
            print_success "server.py exists"
        else
            print_warning "server.py not found in aio_server directory"
        fi
        
        # Check if requirements.txt exists
        if [[ -f "aio_server/requirements.txt" ]]; then
            print_success "requirements.txt exists"
        else
            print_warning "requirements.txt not found"
        fi
    else
        print_error "aio_server directory is missing"
        return 1
    fi
}

# Check conda environment
check_conda() {
    print_info "Checking conda environment..."
    
    if command -v conda &> /dev/null; then
        print_success "conda is installed"
        
        # Check if aiopod environment exists
        if conda env list | grep -q "aiopod"; then
            print_success "aiopod conda environment exists"
        else
            print_warning "aiopod conda environment not found"
            print_info "You may need to create it: conda create -n aiopod python=3.9"
        fi
    else
        print_warning "conda not found"
    fi
}

# Check network connectivity
check_network() {
    print_info "Checking network connectivity..."
    
    # Check if we can reach the internet
    if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        print_success "Internet connectivity available"
    else
        print_warning "Internet connectivity may be limited"
    fi
    
    # Check if we can reach Let's Encrypt
    if curl -s https://acme-v02.api.letsencrypt.org/directory > /dev/null 2>&1; then
        print_success "Let's Encrypt API accessible"
    else
        print_warning "Let's Encrypt API may not be accessible"
    fi
}

# Display summary
display_summary() {
    echo
    print_info "=== Setup Check Summary ==="
    echo
    echo "Domain: $DOMAIN"
    echo "Workspace: $WORKSPACE_ROOT"
    echo
    echo "=== Required Files ==="
    echo "✓ nginx_ssl.conf - Nginx configuration (MCP)"
    echo "✓ setup_nginx_ssl.sh - SSL setup script"
    echo "✓ start_aio_pod.sh - Service start script"
    echo "✓ stop_aio_pod.sh - Service stop script"
    echo "✓ deploy.sh - Complete deployment script"
    echo "✓ test_https.sh - HTTPS test script"
    echo "✓ aio-pod.service - System service file"
    echo
    echo "=== Documentation ==="
    echo "✓ NGINX_SSL_SETUP.md - Detailed setup guide"
    echo "✓ README_NGINX_SSL.md - Quick reference"
    echo
    echo "=== Next Steps ==="
    echo "1. Ensure domain $DOMAIN points to this server"
    echo "2. Run: sudo ./deploy.sh"
    echo "3. Run: ./test_https.sh"
    echo "4. Access: https://$DOMAIN"
    echo
    print_success "Setup check completed!"
}

# Main execution
main() {
    print_info "Starting AIO-Pod setup check..."
    print_info "Domain: $DOMAIN"
    print_info "Workspace: $WORKSPACE_ROOT"
    echo
    
    # Check all required files
    check_file "nginx_ssl.conf" "Nginx configuration file"
    check_file "setup_nginx_ssl.sh" "SSL setup script" true
    check_file "start_aio_pod.sh" "Service start script" true
    check_file "stop_aio_pod.sh" "Service stop script" true
    check_file "deploy.sh" "Deployment script" true
    check_file "test_https.sh" "HTTPS test script" true
    check_file "aio-pod.service" "System service file"
    
    # Check documentation
    check_file "NGINX_SSL_SETUP.md" "Detailed setup documentation"
    check_file "README_NGINX_SSL.md" "Quick reference documentation"
    
    # Check configuration
    check_nginx_conf
    
    # Check system requirements
    check_system
    check_aio_services
    check_conda
    check_network
    
    # Display summary
    display_summary
}

# Run main function
main "$@" 