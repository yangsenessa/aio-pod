#!/bin/bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/domain_constants.sh
source "${ROOT}/scripts/domain_constants.sh"

echo "🔍 AIO-Pod 快速状态检查"
echo "========================"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查函数
check_service() {
    local service="$1"
    local name="$2"
    
    echo -n "检查 $name... "
    if systemctl is-active $service >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 运行中${NC}"
    else
        echo -e "${RED}❌ 未运行${NC}"
    fi
}

check_port() {
    local port="$1"
    local name="$2"
    
    echo -n "检查 $name (端口$port)... "
    if lsof -i :$port >/dev/null 2>&1; then
        echo -e "${GREEN}✅ 监听中${NC}"
    else
        echo -e "${RED}❌ 未监听${NC}"
    fi
}

check_ssl() {
    echo -n "检查SSL证书... "
    if [ -f "${LE_TLS_CERT}" ] && [ -f "${LE_TLS_KEY}" ]; then
        echo -e "${GREEN}✅ Let's Encrypt 证书文件存在${NC}"
    elif [ -f "${CF_ORIGIN_CERT}" ] && [ -f "${CF_ORIGIN_KEY}" ]; then
        echo -e "${GREEN}✅ Cloudflare Origin 证书文件存在${NC}"
    else
        echo -e "${RED}❌ 缺少 LE（${LE_TLS_CERT}）与 Origin（${CF_ORIGIN_CERT}）两套路径之一${NC}"
    fi
}

check_health() {
    echo -n "检查健康状态... "
    response=$(curl -s -k "${MCP_BASE_URL}/health" 2>/dev/null)
    if [[ $response == *"healthy"* ]]; then
        echo -e "${GREEN}✅ 正常${NC}"
    else
        echo -e "${RED}❌ 异常${NC}"
    fi
}

check_aio_pod() {
    echo -n "检查AIO-Pod服务... "
    if pgrep -f "uvicorn.*8000" >/dev/null && pgrep -f "uvicorn.*8001" >/dev/null; then
        echo -e "${GREEN}✅ 运行中${NC}"
    else
        echo -e "${RED}❌ 未运行${NC}"
    fi
}

# 执行检查
echo ""
check_service "nginx" "nginx服务"
check_aio_pod
echo ""
check_port "80" "HTTP端口"
check_port "443" "HTTPS端口"
check_port "8000" "执行服务器"
check_port "8001" "文件服务器"
echo ""
check_ssl
check_health

echo ""
echo "📊 快速测试"
echo "----------"

# 创建测试文件
echo "test content" > test.txt 2>/dev/null

# 快速API测试
echo -n "测试文件上传... "
upload_response=$(curl -s -k -X POST -F "file=@test.txt" "${MCP_BASE_URL}/upload/mcp" 2>/dev/null)
if [[ $upload_response == *"success"* ]]; then
    echo -e "${GREEN}✅ 正常${NC}"
else
    echo -e "${RED}❌ 异常${NC}"
fi

echo -n "测试RPC调用... "
rpc_response=$(curl -s -k -X POST "${MCP_BASE_URL}/api/v1/rpc/mcp/test.bin" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"test","params":{},"id":1}' 2>/dev/null)
if [[ $rpc_response == *"jsonrpc"* ]]; then
    echo -e "${GREEN}✅ 正常${NC}"
else
    echo -e "${RED}❌ 异常${NC}"
fi

# 清理测试文件
rm -f test.txt 2>/dev/null

echo ""
echo "🌐 访问地址"
echo "----------"
echo "HTTPS: ${MCP_BASE_URL}"
echo "健康检查: ${MCP_BASE_URL}/health"
echo "文件上传: ${MCP_BASE_URL}/upload/{type}"
echo "RPC调用: ${MCP_BASE_URL}/api/v1/rpc/{file_type}/{filename}"

echo ""
echo "📝 管理命令"
echo "----------"
echo "重启nginx: sudo systemctl restart nginx"
echo "重启AIO-Pod: ./stop_aio_pod.sh && ./start_aio_pod.sh"
echo "查看日志: sudo tail -f /var/log/nginx/error.log"
echo "更新证书: certbot（LE）或 sudo ./replace_ssl_cert.sh（Origin PEM 放入 certification/）"

echo ""
echo "✅ 检查完成！" 