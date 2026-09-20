#!/bin/bash

# Quick Start Guide for Chat Router Service
# 快速启动 Chat Router 服务

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "${ENABLE_LEGACY_CHAT_ROUTER:-false}" != "true" ]]; then
    echo -e "${YELLOW}Legacy OpenClaw Chat Router is disabled.${NC}"
    echo "AIO-Pod now serves MCP only; Univoice IM calls AIO-Pod via JSON-RPC."
    echo "Set ENABLE_LEGACY_CHAT_ROUTER=true only for explicit legacy testing."
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Chat Router Service - Quick Start${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Step 1: Check dependencies
echo -e "${YELLOW}[1/5] 检查依赖...${NC}"
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Python3 未安装${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Python3 已安装${NC}"

# 与 start_aio_pod.sh 一致：始终使用项目级虚拟环境，不修改 ESP-IDF/base 环境。
AIO_VENV="${AIO_POD_VENV_DIR:-$SCRIPT_DIR/.venv}"
PYTHON_CMD="$AIO_VENV/bin/python3"

setup_python_env() {
    if [[ ! -x "$PYTHON_CMD" ]]; then
        local bootstrap_python="${AIO_POD_BOOTSTRAP_PYTHON:-}"
        if [[ -z "$bootstrap_python" ]]; then
            for candidate in "$HOME/miniconda3/bin/python3" "$HOME/anaconda3/bin/python3" "/opt/homebrew/bin/python3.12" "/usr/local/bin/python3.12" "/usr/bin/python3"; do
                if [[ -x "$candidate" ]]; then
                    bootstrap_python="$candidate"
                    break
                fi
            done
        fi
        if [[ -z "$bootstrap_python" || ! -x "$bootstrap_python" ]]; then
            echo -e "${RED}✗ 未找到 Python 3.9-3.12${NC}"
            exit 1
        fi
        "$bootstrap_python" -m venv "$AIO_VENV"
    fi
    echo -e "${GREEN}✓ 使用项目虚拟环境: ${PYTHON_CMD}${NC}"
}

# Step 2: Install Python dependencies
echo -e "${YELLOW}[2/5] 安装 Python 依赖...${NC}"
setup_python_env
if ! "$PYTHON_CMD" -m pip install -r aio_server/requirements.txt; then
    echo -e "${RED}✗ 依赖安装失败（请勿对 Homebrew 系统 Python 使用 pip3 install）${NC}"
    exit 1
fi
echo -e "${GREEN}✓ 依赖已安装${NC}"

# Step 3: Check environment configuration
echo -e "${YELLOW}[3/5] 检查环境配置...${NC}"
if [[ ! -f "export_env_local.sh" ]]; then
    echo -e "${YELLOW}⚠ export_env_local.sh 不存在，创建模板...${NC}"
    cat > export_env_local.sh << 'EOF'
#!/bin/bash

# OpenClaw Gateway 配置
export OPENCLAW_GATEWAY_HOST="127.0.0.1"
export OPENCLAW_GATEWAY_PORT="18789"
export OPENCLAW_GATEWAY_TOKEN="your-actual-token"
export OPENCLAW_DEFAULT_AGENT="main"

# Chat Router 服务配置
export CHAT_ROUTER_HOST="0.0.0.0"
export CHAT_ROUTER_PORT="8002"
EOF
    chmod +x export_env_local.sh
    echo -e "${GREEN}✓ 环境配置模板已创建${NC}"
    echo -e "${YELLOW}  请编辑 export_env_local.sh 配置实际的 Gateway token${NC}"
else
    echo -e "${GREEN}✓ 环境配置已存在${NC}"
fi

# Step 4: Generate Nginx configuration
echo -e "${YELLOW}[4/5] 生成 Nginx 配置...${NC}"
"$PYTHON_CMD" generate_nginx_config.py > /dev/null 2>&1 || {
    echo -e "${RED}✗ Nginx 配置生成失败${NC}"
    exit 1
}
echo -e "${GREEN}✓ Nginx 配置已生成: nginx_webchat.conf${NC}"

# Step 5: Start services
echo -e "${YELLOW}[5/5] 启动服务...${NC}"
if [[ -f "start_aio_pod.sh" ]]; then
    echo -e "${BLUE}运行: ./start_aio_pod.sh${NC}"
    echo -e "${YELLOW}注意: 这将启动所有 AIO-Pod 服务（包括 Chat Router）${NC}"
    echo
else
    echo -e "${RED}✗ start_aio_pod.sh 不存在${NC}"
    exit 1
fi

echo
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}快速启动完成！${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "${YELLOW}下一步操作：${NC}"
echo
echo "1. 启动服务："
echo -e "   ${BLUE}./start_aio_pod.sh${NC}"
echo
echo "2. 测试服务："
echo -e "   ${BLUE}${PYTHON_CMD} test_chat_router.py${NC}"
echo -e "   ${YELLOW}测试日志将保存到: ./log/test_chat_router_<时间戳>.log${NC}"
echo
echo "3. 部署 Nginx 配置（源站 TLS：与 MCP 一致的 Let's Encrypt 路径，见 nginx_webchat.conf）："
echo -e "   ${BLUE}sudo cp nginx_webchat.conf /etc/nginx/sites-available/webchat.univoices.club.conf${NC}"
echo -e "   ${BLUE}sudo ln -sf /etc/nginx/sites-available/webchat.univoices.club.conf /etc/nginx/sites-enabled/${NC}"
echo -e "   ${BLUE}sudo nginx -t${NC}"
echo -e "   ${BLUE}sudo systemctl reload nginx${NC}"
echo
echo "4. 测试 HTTPS 访问："
echo -e "   ${BLUE}curl https://webchat.univoices.club/health${NC}"
echo
echo -e "${YELLOW}详细文档：${NC}"
echo -e "   ${BLUE}CHAT_ROUTER_DEPLOYMENT.md${NC}"
echo
