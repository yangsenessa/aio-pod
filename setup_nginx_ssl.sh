#!/bin/bash

# AIO-Pod Nginx 安装：使用仓库内 nginx_ssl.conf；源站 TLS 默认 Let's Encrypt（灰云直连），可选 Cloudflare Origin（橙云 Full strict）

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
MCP_SITE_SRC="${SCRIPT_DIR}/nginx/sites-available/mcp.univoices.club"
MCP_SITE_DST="/etc/nginx/sites-available/mcp.univoices.club"

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

ensure_tls_material() {
    print_info "Checking TLS certificate files (Let's Encrypt 或 Cloudflare Origin)..."
    if [[ -f "$LE_TLS_CERT" && -f "$LE_TLS_KEY" ]]; then
        print_success "Let's Encrypt 证书已存在: $LE_TLS_CERT"
        export AIO_TLS_MODE="letsencrypt"
        return 0
    fi
    if [[ -f "$CF_ORIGIN_CERT" && -f "$CF_ORIGIN_KEY" ]]; then
        print_success "Cloudflare Origin 证书已存在: $CF_ORIGIN_CERT"
        export AIO_TLS_MODE="cloudflare_origin"
        return 0
    fi
    print_error "未找到源站 TLS 文件。当前仓库默认：灰云 + Let's Encrypt（与线上 *.univoices.club 链一致），请执行其一："
    print_error "  1) certbot 签发后确认存在: $LE_TLS_CERT 与 $LE_TLS_KEY（live 目录名非 univoices.club 时设置 LE_TLS_CERT / LE_TLS_KEY）"
    print_error "  2) 橙云 Full (strict)：在 Cloudflare 创建 Origin Certificate 后 sudo ./replace_ssl_cert.sh 或手动放到 $CF_ORIGIN_CERT / $CF_ORIGIN_KEY"
    exit 1
}

backup_nginx_conf() {
    if [[ -f "$NGINX_CONF" ]]; then
        print_info "Backing up existing nginx configuration..."
        cp "$NGINX_CONF" "${NGINX_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Nginx configuration backed up"
    fi
}

install_mcp_site() {
    print_info "Installing MCP vhost (mcp.univoices.club) to sites-available + sites-enabled..."
    if [[ ! -f "$MCP_SITE_SRC" ]]; then
        print_error "Missing $MCP_SITE_SRC"
        exit 1
    fi
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    cp "$MCP_SITE_SRC" "$MCP_SITE_DST"
    ln -sf "$MCP_SITE_DST" /etc/nginx/sites-enabled/mcp.univoices.club
    print_success "MCP site installed and enabled"
}

# 旧配置曾用「http2 off」试图规避 CF，反而易导致回源 ALPN 与 CF 不重叠 → 525；且多份相同 server_name 时先加载的块生效
warn_if_http2_off_directive() {
    local f found=0
    shopt -s nullglob
    for f in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
        [[ -f "$f" ]] || continue
        if grep -qE '^[[:space:]]*http2[[:space:]]+off[[:space:]]*;' "$f" 2>/dev/null; then
            found=1
            print_warning "仍发现指令「http2 off」: $f — 易导致 TLS/ALPN 握手失败；经 Cloudflare 橙云回源时常表现为 525。请改为 http2 on（或 listen 443 ssl http2），并删除重复的 MCP server 块。"
        fi
    done
    shopt -u nullglob
    [[ "$found" -eq 1 ]] || true
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
    print_info "Testing HTTPS (hostname ${DOMAIN}；灰云为直连源站解析，橙云则经 CF 边缘)..."
    local HTTPS_RESPONSE
    HTTPS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN}/health" || true)
    if [[ "$HTTPS_RESPONSE" == "200" ]]; then
        print_success "HTTPS health check OK"
    else
        print_warning "HTTPS health returned HTTP $HTTPS_RESPONSE (确认 DNS/灰云或橙云/后端服务已就绪)"
    fi
}

display_info() {
    echo
    print_success "Nginx + TLS 路径配置完成"
    echo
    echo "=== Summary ==="
    echo "MCP domain: $DOMAIN"
    echo "Webchat domain: $WEBCHAT_DOMAIN"
    echo "TLS mode: ${AIO_TLS_MODE:-unknown}"
    echo "LE cert: $LE_TLS_CERT"
    echo "LE key:  $LE_TLS_KEY"
    echo "CF Origin cert (可选): $CF_ORIGIN_CERT"
    echo "CF Origin key (可选): $CF_ORIGIN_KEY"
    echo "Nginx main:  $NGINX_CONF"
    echo "MCP vhost:   $MCP_SITE_DST (sites-enabled)"
    echo
    echo "=== Chat 站点 ==="
    echo "生成 Chat Nginx 片段: python3 ${SCRIPT_DIR}/generate_nginx_config.py"
    echo "然后 sudo cp ${SCRIPT_DIR}/nginx_webchat.conf /etc/nginx/sites-available/${WEBCHAT_DOMAIN}.conf"
    echo "     sudo ln -sf /etc/nginx/sites-available/${WEBCHAT_DOMAIN}.conf /etc/nginx/sites-enabled/"
    echo "     sudo nginx -t && sudo systemctl reload nginx"
    echo
    echo "Cloudflare: 灰云仅 DNS；橙云回源且 Full (strict) 时须源站 Origin 与面板策略一致。"
    echo
}

main() {
    print_info "AIO-Pod Nginx setup (TLS: Let's Encrypt 默认，可选 Cloudflare Origin)"
    print_info "Domain: $DOMAIN"
    echo
    check_root
    ensure_tls_material
    update_system
    install_nginx
    setup_web_root
    backup_nginx_conf
    install_mcp_site
    install_nginx_conf
    warn_if_http2_off_directive
    start_or_reload_nginx
    configure_firewall
    test_ssl
    display_info
}

main "$@"
