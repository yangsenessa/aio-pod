#!/bin/bash

# AIO-Pod 快速测试脚本
# 验证所有服务是否正常工作

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

# Test local services
test_local_services() {
    print_info "Testing local services..."
    
    # Test file server
    if curl -s "http://localhost:$FILE_SERVER_PORT/health" | grep -q "healthy"; then
        print_success "File server is running on port $FILE_SERVER_PORT"
    else
        print_error "File server is not responding on port $FILE_SERVER_PORT"
        return 1
    fi
    
    # Test exec server
    if curl -s "http://localhost:$EXEC_SERVER_PORT/health" | grep -q "healthy"; then
        print_success "Exec server is running on port $EXEC_SERVER_PORT"
    else
        print_error "Exec server is not responding on port $EXEC_SERVER_PORT"
        return 1
    fi
}

# Test nginx
test_nginx() {
    print_info "Testing nginx..."
    
    if systemctl is-active --quiet nginx; then
        print_success "Nginx is running"
    else
        print_error "Nginx is not running"
        return 1
    fi
}

# Test HTTPS
test_https() {
    print_info "Testing HTTPS access..."
    
    # Test health endpoint
    local response=$(curl -s -k -o /dev/null -w "%{http_code}" "https://$DOMAIN/health")
    if [[ "$response" == "200" ]]; then
        print_success "HTTPS health check working (200)"
    else
        print_error "HTTPS health check failed (got $response)"
        return 1
    fi
    
    # Test HTTP to HTTPS redirect
    local redirect_response=$(curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN/health")
    if [[ "$redirect_response" == "301" ]]; then
        print_success "HTTP to HTTPS redirect working (301)"
    else
        print_warning "HTTP redirect may not be working (got $redirect_response)"
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

# Test API endpoints
test_api_endpoints() {
    print_info "Testing API endpoints..."
    
    # Test file upload endpoint
    local upload_response=$(curl -s -k -o /dev/null -w "%{http_code}" "https://$DOMAIN/api/v1/upload/mcp")
    if [[ "$upload_response" == "400" ]] || [[ "$upload_response" == "200" ]]; then
        print_success "File upload endpoint accessible ($upload_response)"
    else
        print_warning "File upload endpoint may not be working (got $upload_response)"
    fi
    
    # Test MCP endpoint
    local mcp_response=$(curl -s -k -o /dev/null -w "%{http_code}" "https://$DOMAIN/api/v1/mcp/test")
    if [[ "$mcp_response" == "404" ]] || [[ "$mcp_response" == "200" ]]; then
        print_success "MCP endpoint accessible ($mcp_response)"
    else
        print_warning "MCP endpoint may not be working (got $mcp_response)"
    fi
}

# Test file upload (if test file exists)
test_file_upload() {
    print_info "Testing file upload..."
    
    # Create a test file
    echo "This is a test file for upload testing" > test_upload.txt
    
    local upload_response=$(curl -s -k -X POST -F "file=@test_upload.txt" "https://$DOMAIN/api/v1/upload/mcp")
    if echo "$upload_response" | grep -q "success"; then
        print_success "File upload test successful"
    else
        print_warning "File upload test failed: $upload_response"
    fi
    
    # Clean up test file
    rm -f test_upload.txt
}

# Display service status
display_status() {
    echo
    print_info "=== Service Status Summary ==="
    echo
    echo "Domain: $DOMAIN"
    echo "HTTPS: https://$DOMAIN"
    echo "Health: https://$DOMAIN/health"
    echo
    echo "=== Local Services ==="
    echo "File Server: $(lsof -i :$FILE_SERVER_PORT > /dev/null 2>&1 && echo 'RUNNING' || echo 'STOPPED')"
    echo "Exec Server: $(lsof -i :$EXEC_SERVER_PORT > /dev/null 2>&1 && echo 'RUNNING' || echo 'STOPPED')"
    echo "Nginx: $(systemctl is-active nginx 2>/dev/null || echo 'UNKNOWN')"
    echo
    echo "=== API Endpoints ==="
    echo "Health: https://$DOMAIN/health"
    echo "Upload: https://$DOMAIN/api/v1/upload/{type}"
    echo "Download: https://$DOMAIN/api/v1/?type={type}&filename={filename}"
    echo "MCP: https://$DOMAIN/api/v1/mcp/{filename}"
    echo "RPC: https://$DOMAIN/api/v1/rpc/"
    echo
    echo "=== Management Commands ==="
    echo "Check nginx: systemctl status nginx"
    echo "Check logs: tail -f /var/log/nginx/error.log"
    echo "Test SSL: openssl s_client -connect $DOMAIN:443"
    echo "TLS: certbot 维护 LE；橙云 Origin: sudo ./replace_ssl_cert.sh → ${CF_ORIGIN_CERT}"
}

# Main execution
main() {
    print_info "Starting AIO-Pod quick test..."
    print_info "Domain: $DOMAIN"
    echo
    
    test_local_services
    test_nginx
    test_https
    test_ssl_certificate
    test_api_endpoints
    test_file_upload
    display_status
    
    echo
    print_success "Quick test completed!"
    print_info "If all tests passed, your AIO-Pod HTTPS setup is working correctly!"
}

# Run main function
main "$@" 