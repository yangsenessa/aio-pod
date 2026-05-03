#!/bin/bash

# AIO-Pod Nginx 安装：使用仓库内 nginx_ssl.conf + Cloudflare Origin Certificate（推荐 SSL Full Strict）

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/domain_constants.sh
source "${SCRIPT_DIR}/scripts/domain_constants.sh"

DOMAIN="$MCP_DOMAIN"
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_SSL_SRC="${SCRIPT_DIR}/nginx_ssl.conf"

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

update_system() {
    print_info "Updating system packages..."
    apt-get update && apt-get upgrade -y
    print_success "System packages updated"
}

install_nginx() {
    print_info "Installing nginx..."
    apt-get install -y nginx
    systemctl enable nginx
    print_success "Nginx installed and enabled"
}

setup_web_root() {
    print_info "Setting up web root directory..."
    mkdir -p /var/www/html
    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html
    print_success "Web root directory created"
}

ensure_cloudflare_origin() {
    print_info "Checking Cloudflare Origin Certificate files..."
    if [[ ! -f "$CF_ORIGIN_CERT" ]] || [[ ! -f "$CF_ORIGIN_KEY" ]]; then
        print_error "缺少源站证书。请在 Cloudflare 控制台创建 Origin Certificate，然后执行其一："
        print_error "  1) sudo ./replace_ssl_cert.sh   （将 certification/fullchain.pem 与 certification/certkey.pem 安装到默认路径）"
        print_error "  2) 手动复制 PEM 到: $CF_ORIGIN_CERT 与 $CF_ORIGIN_KEY"
        exit 1
    fi
    print_success "Origin 证书文件已存在"
}

backup_nginx_conf() {
    if [[ -f "$NGINX_CONF" ]]; then
        print_info "Backing up existing nginx configuration..."
        cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Nginx configuration backed up"
    fi
}

install_nginx_conf() {
    print_info "Installing nginx_ssl.conf as ${NGINX_CONF}..."
    if [[ ! -f "$NGINX_SSL_SRC" ]]; then
        print_error "Missing $NGINX_SSL_SRC"
        exit 1
    fi
    cp "$NGINX_SSL_SRC" "$NGINX_CONF"
    if nginx -t; then
        print_success "Nginx configuration is valid"
    else
        print_error "Nginx configuration is invalid"
        exit 1
    fi
}

start_or_reload_nginx() {
    print_info "Starting/reloading nginx..."
    systemctl enable nginx
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx
    else
        systemctl start nginx
    fi
    systemctl status nginx --no-pager || true
    print_success "Nginx is running"
}

configure_firewall() {
    print_info "Configuring firewall..."
    if ! command -v ufw &> /dev/null; then
        apt-get install -y ufw
    fi
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    print_success "Firewall configured"
}

test_ssl() {
    print_info "Testing HTTPS (via Cloudflare edge, hostname ${DOMAIN})..."
    local HTTPS_RESPONSE
    HTTPS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN}/health" || true)
    if [[ "$HTTPS_RESPONSE" == "200" ]]; then
        print_success "HTTPS health check OK"
    else
        print_warning "HTTPS health returned HTTP $HTTPS_RESPONSE (确认 DNS/CF 代理/后端服务已就绪)"
    fi
}

display_info() {
    echo
    print_success "Nginx + Cloudflare Origin 路径配置完成"
    echo
    echo "=== Summary ==="
    echo "MCP domain: $DOMAIN"
    echo "Webchat domain: $WEBCHAT_DOMAIN"
    echo "Origin cert: $CF_ORIGIN_CERT"
    echo "Origin key:  $CF_ORIGIN_KEY"
    echo "Nginx main:  $NGINX_CONF"
    echo
    echo "=== Chat 站点 ==="
    echo "生成 Chat Nginx 片段: python3 ${SCRIPT_DIR}/generate_nginx_config.py"
    echo "然后 sudo cp ${SCRIPT_DIR}/nginx_webchat.conf /etc/nginx/sites-available/${WEBCHAT_DOMAIN}.conf"
    echo "     sudo ln -sf /etc/nginx/sites-available/${WEBCHAT_DOMAIN}.conf /etc/nginx/sites-enabled/"
    echo "     sudo nginx -t && sudo systemctl reload nginx"
    echo
    echo "Cloudflare: SSL/TLS 建议使用 Full (strict)，边缘证书由 CF 管理。"
    echo
}

main() {
    print_info "AIO-Pod Nginx setup (Cloudflare origin TLS)"
    print_info "Domain: $DOMAIN"
    echo
    check_root
    ensure_cloudflare_origin
    update_system
    install_nginx
    setup_web_root
    backup_nginx_conf
    install_nginx_conf
    start_or_reload_nginx
    configure_firewall
    test_ssl
    display_info
}

main "$@"
