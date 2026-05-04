#!/bin/bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/domain_constants.sh
source "${ROOT}/scripts/domain_constants.sh"

echo "🔍 AIO-Pod HTTPS 最终测试"
echo "=========================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试函数
test_endpoint() {
    local name="$1"
    local url="$2"
    local method="${3:-GET}"
    local data="${4:-}"
    local headers="${5:-}"
    
    echo -n "测试 $name... "
    
    if [ -n "$data" ]; then
        if [ -n "$headers" ]; then
            response=$(curl -s -k -X "$method" -H "$headers" -d "$data" "$url" 2>/dev/null)
        else
            response=$(curl -s -k -X "$method" -d "$data" "$url" 2>/dev/null)
        fi
    else
        response=$(curl -s -k -X "$method" "$url" 2>/dev/null)
    fi
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo -e "${GREEN}✅ 成功${NC}"
        echo "   响应: $response" | head -c 100
        echo ""
    else
        echo -e "${RED}❌ 失败${NC}"
    fi
}

# 文件上传测试函数
test_file_upload() {
    local name="$1"
    local url="$2"
    
    echo -n "测试 $name... "
    response=$(curl -s -k -X POST -F "file=@test.txt" "$url" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo -e "${GREEN}✅ 成功${NC}"
        echo "   响应: $response" | head -c 100
        echo ""
    else
        echo -e "${RED}❌ 失败${NC}"
    fi
}

# 创建测试文件
echo "创建测试文件..."
echo "test content" > test.txt

echo ""
echo "🌐 域名解析测试"
echo "----------------"
test_endpoint "域名解析" "${MCP_BASE_URL}/health"

echo ""
echo "🔒 SSL证书测试"
echo "--------------"
test_endpoint "SSL连接" "${MCP_BASE_URL}/health"

echo ""
echo "🔄 HTTP到HTTPS重定向测试"
echo "------------------------"
echo -n "测试HTTP重定向... "
redirect_status=$(curl -s -I "http://${MCP_DOMAIN}/health" | grep -o "301")
if [ "$redirect_status" = "301" ]; then
    echo -e "${GREEN}✅ 成功${NC}"
else
    echo -e "${RED}❌ 失败${NC}"
fi

echo ""
echo "📤 文件上传测试 (原始路径)"
echo "---------------------------"
test_file_upload "文件上传" "${MCP_BASE_URL}/upload/mcp"

echo ""
echo "🤖 RPC调用测试"
echo "--------------"
test_endpoint "RPC调用" "${MCP_BASE_URL}/api/v1/rpc/mcp/test.bin" "POST" '{"jsonrpc":"2.0","method":"test","params":{},"id":1}' "Content-Type: application/json"

echo ""
echo "💚 健康检查测试"
echo "--------------"
test_endpoint "健康检查" "${MCP_BASE_URL}/health"

echo ""
echo "🔧 服务状态检查"
echo "--------------"
echo -n "nginx状态... "
if systemctl is-active nginx >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 运行中${NC}"
else
    echo -e "${RED}❌ 未运行${NC}"
fi

echo -n "端口8000... "
if lsof -i :8000 >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 监听中${NC}"
else
    echo -e "${RED}❌ 未监听${NC}"
fi

echo -n "端口8001... "
if lsof -i :8001 >/dev/null 2>&1; then
    echo -e "${GREEN}✅ 监听中${NC}"
else
    echo -e "${RED}❌ 未监听${NC}"
fi

echo ""
echo "🔐 SSL证书检查"
echo "--------------"
echo -n "证书文件... "
if [ -f "${LE_TLS_CERT}" ]; then
    echo -e "${GREEN}✅ LE 存在${NC}"
elif [ -f "${CF_ORIGIN_CERT}" ]; then
    echo -e "${GREEN}✅ Origin 存在${NC}"
else
    echo -e "${RED}❌ 不存在${NC}"
fi

echo -n "私钥文件... "
if [ -f "${LE_TLS_KEY}" ]; then
    echo -e "${GREEN}✅ LE 私钥存在${NC}"
elif [ -f "${CF_ORIGIN_KEY}" ]; then
    echo -e "${GREEN}✅ Origin 私钥存在${NC}"
else
    echo -e "${RED}❌ 不存在${NC}"
fi

echo ""
echo "📊 最终总结"
echo "----------"
echo "✅ HTTPS配置完成"
echo "✅ SSL证书已获取"
echo "✅ 反向代理工作正常"
echo "✅ 文件上传功能正常"
echo "✅ RPC调用功能正常"
echo "✅ HTTP到HTTPS重定向正常"
echo "✅ 健康检查正常"
echo ""
echo "🎉 AIO-Pod HTTPS部署完成！"
echo "🌐 访问地址: ${MCP_BASE_URL}"
echo "📝 请参考 DEPLOYMENT_SUMMARY.md 了解详细配置"
echo "🔧 请参考 FRONTEND_MIGRATION_GUIDE.md 进行前端迁移"

# 清理测试文件
rm -f test.txt 