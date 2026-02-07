#!/bin/bash

# SSL证书替换脚本
# 用于替换nginx的SSL证书

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
DOMAIN="mcp.aio2030.fun"
CERT_DIR="/root/AIO-2030/aio-pod/certification"
LIVE_DIR="/etc/letsencrypt/live/${DOMAIN}"
ARCHIVE_DIR="/etc/letsencrypt/archive/${DOMAIN}"
NEW_FULLCHAIN="${CERT_DIR}/fullchain.pem"
NEW_PRIVKEY="${CERT_DIR}/certkey.pem"

# 打印函数
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

# 检查是否以root运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本必须以root权限运行"
        exit 1
    fi
}

# 检查证书文件是否存在
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

# 验证证书格式
validate_certificates() {
    print_info "验证证书格式..."
    
    # 验证证书文件
    if ! openssl x509 -in "$NEW_FULLCHAIN" -text -noout > /dev/null 2>&1; then
        print_error "证书文件格式无效"
        exit 1
    fi
    
    # 验证私钥文件
    if ! openssl rsa -in "$NEW_PRIVKEY" -check -noout > /dev/null 2>&1; then
        print_error "私钥文件格式无效"
        exit 1
    fi
    
    # 验证证书和私钥是否匹配
    CERT_HASH=$(openssl x509 -noout -modulus -in "$NEW_FULLCHAIN" | openssl md5)
    KEY_HASH=$(openssl rsa -noout -modulus -in "$NEW_PRIVKEY" | openssl md5)
    
    if [[ "$CERT_HASH" != "$KEY_HASH" ]]; then
        print_error "证书和私钥不匹配！"
        exit 1
    fi
    
    print_success "证书格式验证通过"
}

# 备份现有证书
backup_existing_certs() {
    print_info "备份现有证书..."
    
    BACKUP_DIR="/etc/letsencrypt/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    if [[ -d "$LIVE_DIR" ]]; then
        cp -r "$LIVE_DIR" "$BACKUP_DIR/live" 2>/dev/null || true
        print_success "已备份到: $BACKUP_DIR"
    fi
    
    if [[ -d "$ARCHIVE_DIR" ]]; then
        cp -r "$ARCHIVE_DIR" "$BACKUP_DIR/archive" 2>/dev/null || true
    fi
}

# 创建必要的目录
create_directories() {
    print_info "创建必要的目录..."
    
    mkdir -p "$ARCHIVE_DIR"
    mkdir -p "$LIVE_DIR"
    
    print_success "目录创建完成"
}

# 查找下一个版本号
get_next_version() {
    local max_version=1
    
    if [[ -d "$ARCHIVE_DIR" ]]; then
        for file in "$ARCHIVE_DIR"/fullchain*.pem; do
            if [[ -f "$file" ]]; then
                version=$(basename "$file" | sed 's/fullchain\([0-9]*\)\.pem/\1/')
                if [[ "$version" =~ ^[0-9]+$ ]] && [[ "$version" -gt "$max_version" ]]; then
                    max_version=$version
                fi
            fi
        done
    fi
    
    echo $((max_version + 1))
}

# 复制新证书到归档目录
copy_certificates() {
    local version=$1
    print_info "复制新证书到归档目录..."
    print_info "使用版本号: $version"
    
    # 复制证书文件
    cp "$NEW_FULLCHAIN" "${ARCHIVE_DIR}/fullchain${version}.pem"
    cp "$NEW_PRIVKEY" "${ARCHIVE_DIR}/privkey${version}.pem"
    
    # 提取证书和链（如果需要）
    openssl x509 -in "$NEW_FULLCHAIN" -out "${ARCHIVE_DIR}/cert${version}.pem" 2>/dev/null || true
    
    # 设置正确的权限
    chmod 644 "${ARCHIVE_DIR}/fullchain${version}.pem"
    chmod 600 "${ARCHIVE_DIR}/privkey${version}.pem"
    chmod 644 "${ARCHIVE_DIR}/cert${version}.pem" 2>/dev/null || true
    
    print_success "证书已复制到归档目录"
}

# 更新符号链接
update_symlinks() {
    local version=$1
    print_info "更新符号链接..."
    print_info "链接到版本号: $version"
    
    # 删除旧的符号链接
    rm -f "${LIVE_DIR}/fullchain.pem"
    rm -f "${LIVE_DIR}/privkey.pem"
    rm -f "${LIVE_DIR}/cert.pem" 2>/dev/null || true
    rm -f "${LIVE_DIR}/chain.pem" 2>/dev/null || true
    
    # 创建新的符号链接
    ln -s "${ARCHIVE_DIR}/fullchain${version}.pem" "${LIVE_DIR}/fullchain.pem"
    ln -s "${ARCHIVE_DIR}/privkey${version}.pem" "${LIVE_DIR}/privkey.pem"
    
    if [[ -f "${ARCHIVE_DIR}/cert${version}.pem" ]]; then
        ln -s "${ARCHIVE_DIR}/cert${version}.pem" "${LIVE_DIR}/cert.pem" 2>/dev/null || true
    fi
    
    print_success "符号链接已更新"
}

# 测试nginx配置
test_nginx_config() {
    print_info "测试nginx配置..."
    
    if nginx -t; then
        print_success "Nginx配置测试通过"
    else
        print_error "Nginx配置测试失败！"
        exit 1
    fi
}

# 重新加载nginx
reload_nginx() {
    print_info "重新加载nginx..."
    
    if systemctl reload nginx; then
        print_success "Nginx已重新加载"
    else
        print_warning "Nginx重新加载失败，尝试重启..."
        if systemctl restart nginx; then
            print_success "Nginx已重启"
        else
            print_error "Nginx重启失败！"
            exit 1
        fi
    fi
}

# 验证证书
verify_certificate() {
    print_info "验证新证书..."
    
    sleep 2  # 等待nginx完全加载
    
    # 检查证书信息
    CERT_INFO=$(openssl s_client -connect localhost:443 -servername "$DOMAIN" < /dev/null 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null)
    
    if [[ -n "$CERT_INFO" ]]; then
        print_success "证书验证成功"
        echo "$CERT_INFO"
    else
        print_warning "无法验证证书（可能nginx未运行或配置问题）"
    fi
}

# 主函数
main() {
    print_info "开始替换SSL证书..."
    print_info "域名: $DOMAIN"
    print_info "新证书位置: $CERT_DIR"
    echo
    
    check_root
    check_cert_files
    validate_certificates
    backup_existing_certs
    create_directories
    
    # 获取并统一使用版本号
    CERT_VERSION=$(get_next_version)
    copy_certificates "$CERT_VERSION"
    update_symlinks "$CERT_VERSION"
    
    test_nginx_config
    reload_nginx
    verify_certificate
    
    echo
    print_success "SSL证书替换完成！"
    echo
    echo "=== 证书信息 ==="
    echo "证书文件: ${LIVE_DIR}/fullchain.pem"
    echo "私钥文件: ${LIVE_DIR}/privkey.pem"
    echo "归档目录: ${ARCHIVE_DIR}"
    echo
    echo "=== 验证命令 ==="
    echo "查看证书: openssl s_client -connect $DOMAIN:443 -servername $DOMAIN"
    echo "测试HTTPS: curl -I https://$DOMAIN"
}

# 运行主函数
main "$@"
