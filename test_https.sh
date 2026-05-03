#!/bin/bash

# AIO-Pod HTTPS Test Script
# This script tests the HTTPS configuration and API endpoints

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/domain_constants.sh
source "${SCRIPT_DIR}/scripts/domain_constants.sh"
DOMAIN="$MCP_DOMAIN"
FILE_SERVER_PORT=8001
EXEC_SERVER_PORT=8000

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

# Test DNS resolution
test_dns() {
    print_info "Testing DNS resolution for $DOMAIN..."
    
    if nslookup "$DOMAIN" > /dev/null 2>&1; then
        print_success "DNS resolution successful"
        nslookup "$DOMAIN"
    else
        print_error "DNS resolution failed"
        return 1
    fi
}

# Test HTTP to HTTPS redirect
test_http_redirect() {
    print_info "Testing HTTP to HTTPS redirect..."
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN")
    if [[ "$response" == "301" ]]; then
        print_success "HTTP to HTTPS redirect working (301)"
    else
        print_warning "HTTP redirect may not be working (got $response)"
    fi
}

# Test HTTPS connection
test_https() {
    print_info "Testing HTTPS connection..."
    
    local response=$(curl -s -k -o /dev/null -w "%{http_code}" "https://$DOMAIN")
    if [[ "$response" == "200" ]]; then
        print_success "HTTPS connection successful (200)"
    else
        print_warning "HTTPS connection may not be working (got $response)"
    fi
}

# Test SSL certificate
test_ssl_certificate() {
    print_info "Testing SSL certificate..."
    
    if openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" < /dev/null 2>/dev/null | grep -q "Verify return code: 0"; then
        print_success "SSL certificate is valid"
    else
        print_warning "SSL certificate validation failed"
    fi
}

# Test health endpoint
test_health() {
    print_info "Testing health endpoint..."
    
    local response=$(curl -s -k "https://$DOMAIN/health")
    if echo "$response" | grep -q "healthy"; then
        print_success "Health endpoint working"
        echo "Response: $response"
    else
        print_warning "Health endpoint may not be working"
        echo "Response: $response"
    fi
}

# Test local services
test_local_services() {
    print_info "Testing local services..."
    
    # Test file server
    if curl -s "http://localhost:$FILE_SERVER_PORT/health" | grep -q "healthy"; then
        print_success "File server is running on port $FILE_SERVER_PORT"
    else
        print_warning "File server may not be running on port $FILE_SERVER_PORT"
    fi
    
    # Test exec server
    if curl -s "http://localhost:$EXEC_SERVER_PORT/health" | grep -q "healthy"; then
        print_success "Exec server is running on port $EXEC_SERVER_PORT"
    else
        print_warning "Exec server may not be running on port $EXEC_SERVER_PORT"
    fi
}

# Test nginx status
test_nginx() {
    print_info "Testing nginx status..."
    
    if systemctl is-active --quiet nginx; then
        print_success "Nginx is running"
    else
        print_error "Nginx is not running"
        return 1
    fi
}

# Test file upload (if test file exists)
test_file_upload() {
    print_info "Testing file upload..."
    
    # Create a test file if it doesn't exist
    if [[ ! -f "test_upload.txt" ]]; then
        echo "This is a test file for upload testing" > test_upload.txt
    fi
    
    local response=$(curl -s -k -X POST -F "file=@test_upload.txt" "https://$DOMAIN/api/v1/upload/mcp")
    if echo "$response" | grep -q "success"; then
        print_success "File upload test successful"
        echo "Response: $response"
    else
        print_warning "File upload test failed"
        echo "Response: $response"
    fi
}

# Test MCP execution (if test file exists)
test_mcp_execution() {
    print_info "Testing MCP execution..."
    
    # Check if there are any MCP files
    if [[ -d "aio_server/uploads/mcp" ]] && [[ $(ls aio_server/uploads/mcp/*.bin 2>/dev/null | wc -l) -gt 0 ]]; then
        local mcp_file=$(ls aio_server/uploads/mcp/*.bin | head -1 | xargs basename)
        print_info "Testing with MCP file: $mcp_file"
        
        local response=$(curl -s -k -X POST "https://$DOMAIN/api/v1/mcp/$mcp_file")
        if [[ $? -eq 0 ]]; then
            print_success "MCP execution test completed"
            echo "Response: $response"
        else
            print_warning "MCP execution test failed"
            echo "Response: $response"
        fi
    else
        print_info "No MCP files found for testing"
    fi
}

# Display comprehensive status
display_status() {
    echo
    print_info "=== HTTPS Test Results ==="
    echo
    echo "Domain: $DOMAIN"
    echo "HTTPS URL: https://$DOMAIN"
    echo "Health Check: https://$DOMAIN/health"
    echo
    echo "=== Service Status ==="
    echo "Nginx: $(systemctl is-active nginx 2>/dev/null || echo 'unknown')"
    echo "File Server: $(lsof -i :$FILE_SERVER_PORT > /dev/null 2>&1 && echo 'running' || echo 'stopped')"
    echo "Exec Server: $(lsof -i :$EXEC_SERVER_PORT > /dev/null 2>&1 && echo 'running' || echo 'stopped')"
    echo
    echo "=== SSL (Cloudflare edge / Origin PEM) ==="
    if [[ -f "${CF_ORIGIN_CERT}" ]]; then
        openssl x509 -in "${CF_ORIGIN_CERT}" -noout -subject -dates 2>/dev/null || echo "Cannot read origin certificate"
    else
        echo "Origin certificate not found at ${CF_ORIGIN_CERT}"
    fi
    echo
    echo "=== API Endpoints ==="
    echo "Health: https://$DOMAIN/health"
    echo "Upload: POST https://$DOMAIN/api/v1/upload/{type}"
    echo "Download: GET https://$DOMAIN/api/v1/?type={type}&filename={filename}"
    echo "MCP Execute: POST https://$DOMAIN/api/v1/mcp/{filename}"
    echo
    echo "=== Troubleshooting Commands ==="
    echo "Check nginx: sudo systemctl status nginx"
    echo "Check logs: sudo tail -f /var/log/nginx/error.log"
    echo "Test SSL: openssl s_client -connect $DOMAIN:443 -servername $DOMAIN"
    echo "Update origin cert: sudo ./replace_ssl_cert.sh"
}

# Main execution
main() {
    print_info "Starting HTTPS configuration test..."
    print_info "Domain: $DOMAIN"
    echo
    
    test_dns
    test_nginx
    test_http_redirect
    test_https
    test_ssl_certificate
    test_health
    test_local_services
    test_file_upload
    test_mcp_execution
    display_status
    
    echo
    print_success "HTTPS test completed!"
}

# Run main function
main "$@" 