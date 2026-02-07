#!/bin/bash

# Chat Router 启动诊断脚本

set -e

echo "=========================================="
echo "Chat Router 启动诊断"
echo "=========================================="
echo

# 1. 检查 Python
echo "✓ 检查 Python..."
python3 --version

# 2. 检查依赖
echo
echo "✓ 检查 Python 依赖..."
MISSING_DEPS=""

for dep in uvicorn fastapi websockets httpx jinja2; do
    if python3 -c "import $dep" 2>/dev/null; then
        echo "  ✓ $dep"
    else
        echo "  ✗ $dep (缺失)"
        MISSING_DEPS="$MISSING_DEPS $dep"
    fi
done

# 3. 检查文件
echo
echo "✓ 检查必需文件..."
for file in \
    "aio_server/chat_router_server.py" \
    "aio_server/app/api/chat_router.py" \
    "aio_server/app/services/chat_router_service.py"; do
    if [[ -f "$file" ]]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file (缺失)"
    fi
done

# 4. 检查环境变量
echo
echo "✓ 检查环境变量..."
echo "  OPENCLAW_GATEWAY_HOST: ${OPENCLAW_GATEWAY_HOST:-未设置}"
echo "  OPENCLAW_GATEWAY_PORT: ${OPENCLAW_GATEWAY_PORT:-未设置}"
echo "  OPENCLAW_GATEWAY_TOKEN: ${OPENCLAW_GATEWAY_TOKEN:0:20}..."
echo "  CHAT_ROUTER_PORT: ${CHAT_ROUTER_PORT:-未设置 (默认 8002)}"

# 5. 检查端口占用
echo
echo "✓ 检查端口占用..."
if lsof -i :8002 > /dev/null 2>&1; then
    echo "  ⚠ 端口 8002 已被占用"
    lsof -i :8002
else
    echo "  ✓ 端口 8002 可用"
fi

# 6. 总结
echo
echo "=========================================="
echo "诊断总结"
echo "=========================================="

if [[ -n "$MISSING_DEPS" ]]; then
    echo "✗ 缺少依赖: $MISSING_DEPS"
    echo
    echo "请安装依赖："
    echo "  cd aio_server"
    echo "  pip3 install -r requirements.txt"
    echo
    echo "或者："
    echo "  pip3 install uvicorn fastapi websockets httpx jinja2"
    exit 1
else
    echo "✓ 所有依赖已安装"
    echo
    echo "可以启动服务："
    echo "  cd aio_server"
    echo "  python3 chat_router_server.py"
    echo
    echo "或者使用启动脚本："
    echo "  ./start_aio_pod.sh"
fi
