#!/bin/bash

# AIO-Pod Nginx SSL Setup Script
# This script installs nginx, configures SSL certificates with Let's Encrypt,
# and sets up reverse proxy for the AIO-Pod services

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOMAIN="mcp.aio2030.fun"
EMAIL="admin@aio2030.fun"  # Change this to your email
NGINX_CONF="/etc/nginx/nginx.conf"
CERTBOT_DIR="/etc/letsencrypt"

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

# Update system packages
update_system() {
    print_info "Updating system packages..."
    apt update && apt upgrade -y
    print_success "System packages updated"
}

# Install nginx
install_nginx() {
    print_info "Installing nginx..."
    apt install -y nginx
    systemctl enable nginx
    print_success "Nginx installed and enabled"
}

# Install certbot
install_certbot() {
    print_info "Installing certbot..."
    apt install -y certbot python3-certbot-nginx
    print_success "Certbot installed"
}

# Create web root directory for Let's Encrypt challenge
setup_web_root() {
    print_info "Setting up web root directory..."
    mkdir -p /var/www/html
    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html
    print_success "Web root directory created"
}

# Backup existing nginx configuration
backup_nginx_conf() {
    if [[ -f "$NGINX_CONF" ]]; then
        print_info "Backing up existing nginx configuration..."
        cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Nginx configuration backed up"
    fi
}

# Install custom nginx configuration
install_nginx_conf() {
    print_info "Installing custom nginx configuration..."
    
    # Copy our nginx configuration
    cp nginx.conf "$NGINX_CONF"
    
    # Test nginx configuration
    if nginx -t; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration is invalid"
        exit 1
    fi
}

# Start nginx with HTTP-only configuration
start_nginx_http() {
    print_info "Starting nginx with HTTP configuration..."
    systemctl start nginx
    systemctl status nginx --no-pager
    print_success "Nginx started"
}

# Obtain SSL certificate
obtain_ssl_certificate() {
    print_info "Obtaining SSL certificate for $DOMAIN..."
    
    # Stop nginx temporarily for certificate verification
    systemctl stop nginx
    
    # Obtain certificate
    certbot certonly --standalone \
        --email "$EMAIL" \
        --agree-tos \
        --no-eff-email \
        --domains "$DOMAIN" \
        --non-interactive
    
    if [[ $? -eq 0 ]]; then
        print_success "SSL certificate obtained successfully"
    else
        print_error "Failed to obtain SSL certificate"
        exit 1
    fi
}

# Configure nginx with SSL
configure_nginx_ssl() {
    print_info "Configuring nginx with SSL..."
    
    # Start nginx with SSL configuration
    systemctl start nginx
    
    # Test nginx configuration
    if nginx -t; then
        print_success "Nginx SSL configuration is valid"
    else
        print_error "Nginx SSL configuration is invalid"
        exit 1
    fi
    
    # Reload nginx
    systemctl reload nginx
    print_success "Nginx configured with SSL"
}

# Setup automatic certificate renewal
setup_cert_renewal() {
    print_info "Setting up automatic certificate renewal..."
    
    # Create renewal script
    cat > /etc/cron.daily/renew-ssl-cert << 'EOF'
#!/bin/bash
certbot renew --quiet --post-hook "systemctl reload nginx"
EOF
    
    chmod +x /etc/cron.daily/renew-ssl-cert
    print_success "Automatic certificate renewal configured"
}

# Configure firewall
configure_firewall() {
    print_info "Configuring firewall..."
    
    # Install ufw if not present
    if ! command -v ufw &> /dev/null; then
        apt install -y ufw
    fi
    
    # Configure firewall rules
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    
    print_success "Firewall configured"
}

# Test SSL configuration
test_ssl() {
    print_info "Testing SSL configuration..."
    
    # Test HTTP to HTTPS redirect
    HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN")
    if [[ "$HTTP_RESPONSE" == "301" ]]; then
        print_success "HTTP to HTTPS redirect working"
    else
        print_warning "HTTP to HTTPS redirect may not be working (got $HTTP_RESPONSE)"
    fi
    
    # Test HTTPS
    HTTPS_RESPONSE=$(curl -s -k -o /dev/null -w "%{http_code}" "https://$DOMAIN")
    if [[ "$HTTPS_RESPONSE" == "200" ]]; then
        print_success "HTTPS working correctly"
    else
        print_warning "HTTPS may not be working (got $HTTPS_RESPONSE)"
    fi
    
    # Test SSL certificate
    if openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" < /dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
        print_success "SSL certificate is valid"
    else
        print_warning "SSL certificate validation failed"
    fi
}

# Display final information
display_info() {
    echo
    print_success "Nginx SSL setup completed successfully!"
    echo
    echo "=== Configuration Summary ==="
    echo "Domain: $DOMAIN"
    echo "SSL Certificate: $CERTBOT_DIR/live/$DOMAIN/"
    echo "Nginx Config: $NGINX_CONF"
    echo "Firewall: Enabled (ports 22, 80, 443)"
    echo
    echo "=== Available Endpoints ==="
    echo "HTTPS: https://$DOMAIN"
    echo "Health Check: https://$DOMAIN/health"
    echo "API Base: https://$DOMAIN/api/v1/"
    echo "MCP Endpoints: https://$DOMAIN/api/v1/mcp/"
    echo
    echo "=== Management Commands ==="
    echo "Check nginx status: systemctl status nginx"
    echo "Restart nginx: systemctl restart nginx"
    echo "View nginx logs: tail -f /var/log/nginx/access.log"
    echo "Renew certificate: certbot renew"
    echo
    print_info "Certificate will auto-renew daily"
}

# Main execution
main() {
    print_info "Starting AIO-Pod Nginx SSL Setup..."
    print_info "Domain: $DOMAIN"
    print_info "Email: $EMAIL"
    echo
    
    check_root
    update_system
    install_nginx
    install_certbot
    setup_web_root
    backup_nginx_conf
    install_nginx_conf
    start_nginx_http
    obtain_ssl_certificate
    configure_nginx_ssl
    setup_cert_renewal
    configure_firewall
    test_ssl
    display_info
}

# Run main function
main "$@" 