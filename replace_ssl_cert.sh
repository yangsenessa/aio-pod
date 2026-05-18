#!/bin/bash

# 将 PEM/KEY 安装到 Cloudflare Origin 默认路径（橙云 + SSL Full strict 回源时使用）。
# 灰云 + Let's Encrypt：请用 certbot 等维护 /etc/letsencrypt/live/...，与 nginx 中 ssl_certificate 一致即可，通常不需要本脚本。
# 默认从仓库 certification/fullchain.pem 与 certification/certkey.pem 读取（沿用原文件名）

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/domain_constants.sh
source "${SCRIPT_DIR}/scripts/domain_constants.sh"

CERT_DIR="${CERT_DIR:-$SCRIPT_DIR/certification}"
NEW_FULLCHAIN="${CERT_DIR}/fullchain.pem"
NEW_PRIVKEY="${CERT_DIR}/certkey.pem"

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本必须以 root 权限运行"
        exit 1
    fi
}

check_cert_files() {
    print_info "检查证书文件..."
    if [[ ! -f "$NEW_FULLCHAIN" ]]; then
        print_error "证书文件不存在: $NEW_FULLCHAIN"
        exit 1
    fi
    if [[ ! -f "$NEW_PRIVKEY" ]]; then
        print_error "私钥文件不存在: $NEW_PRIVKEY"
        exit 1
    fi
    print_success "证书文件检查通过"
}

validate_certificates() {
    print_info "验证证书格式..."
    if ! openssl x509 -in "$NEW_FULLCHAIN" -text -noout > /dev/null 2>&1; then
        print_error "证书 PEM 无效"
        exit 1
    fi
    if openssl rsa -in "$NEW_PRIVKEY" -check -noout > /dev/null 2>&1; then
        :
    elif openssl ec -in "$NEW_PRIVKEY" -check -noout > /dev/null 2>&1; then
        :
    else
        print_error "私钥格式无效（非 RSA/EC）"
        exit 1
    fi

    local tmpd
    tmpd=$(mktemp -d)
    openssl x509 -in "$NEW_FULLCHAIN" -pubkey -noout > "$tmpd/pubcert.pem"
    if ! openssl pkey -in "$NEW_PRIVKEY" -pubout > "$tmpd/pubkey.pem" 2>/dev/null; then
        rm -rf "$tmpd"
        print_error "无法从私钥导出公钥"
        exit 1
    fi
    if ! cmp -s "$tmpd/pubcert.pem" "$tmpd/pubkey.pem"; then
        rm -rf "$tmpd"
        print_error "证书与私钥不匹配"
        exit 1
    fi
    rm -rf "$tmpd"
    print_success "证书与私钥匹配"
}

install_origin_files() {
    print_info "写入 Cloudflare Origin 证书到 ${CF_ORIGIN_CERT} / ${CF_ORIGIN_KEY}"
    mkdir -p "$(dirname "$CF_ORIGIN_CERT")"
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    if [[ -f "$CF_ORIGIN_CERT" ]]; then
        cp -a "$CF_ORIGIN_CERT" "${CF_ORIGIN_CERT}.bak.${ts}"
    fi
    if [[ -f "$CF_ORIGIN_KEY" ]]; then
        cp -a "$CF_ORIGIN_KEY" "${CF_ORIGIN_KEY}.bak.${ts}"
    fi
    install -m 0644 "$NEW_FULLCHAIN" "$CF_ORIGIN_CERT"
    install -m 0600 "$NEW_PRIVKEY" "$CF_ORIGIN_KEY"
    print_success "已安装 Origin 证书"
}

test_nginx_config() {
    print_info "测试 nginx 配置..."
    if nginx -t; then
        print_success "nginx -t 通过"
    else
        print_error "nginx -t 失败"
        exit 1
    fi
}

reload_nginx() {
    print_info "重新加载 nginx..."
    if systemctl reload nginx 2>/dev/null; then
        print_success "nginx 已 reload"
    elif systemctl restart nginx; then
        print_success "nginx 已 restart"
    else
        print_error "无法 reload/restart nginx"
        exit 1
    fi
}

verify_local_tls() {
    print_info "校验源站 443 呈现的证书（localhost）..."
    sleep 1
    if openssl s_client -connect "127.0.0.1:443" -servername "$MCP_DOMAIN" < /dev/null 2>/dev/null |
        openssl x509 -noout -subject -dates 2>/dev/null; then
        print_success "已读到源站证书"
    else
        print_warning "无法从 localhost:443 读取证书（检查 nginx 是否监听 443 / server_name）"
    fi
}

main() {
    print_info "安装到 Cloudflare Origin 路径（域名: ${MCP_DOMAIN} / ${WEBCHAT_DOMAIN}；橙云 Full strict 场景）"
    print_info "来源目录: $CERT_DIR"
    echo
    check_root
    check_cert_files
    validate_certificates
    install_origin_files
    test_nginx_config
    reload_nginx
    verify_local_tls
    echo
    print_success "完成。证书已写入 Origin 路径。橙云时边缘 HTTPS 由 Cloudflare 签发，回源须 Full (strict)。灰云 + Let's Encrypt 时请勿依赖本路径，改用 certbot 与 Nginx 中 LE 路径。"
    echo
    echo "验证命令:"
    echo "  curl -sS -o /dev/null -w '%{http_code}' ${MCP_BASE_URL}/health"
    echo "  openssl s_client -connect ${MCP_DOMAIN}:443 -servername ${MCP_DOMAIN} </dev/null 2>/dev/null | openssl x509 -noout -subject -dates"
}

main "$@"
