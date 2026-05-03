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

# Step 2: Install Python dependencies
echo -e "${YELLOW}[2/5] 安装 Python 依赖...${NC}"
pip3 install -r aio_server/requirements.txt > /dev/null 2>&1 || {
    echo -e "${RED}✗ 依赖安装失败${NC}"
    exit 1
}
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
export OPENCLAW_GATEWAY_TOKEN="sk-lm-gyXsWZIS:opqYGydrY8dwynxrZNT6"
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
python3 generate_nginx_config.py > /dev/null 2>&1 || {
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
echo -e "   ${BLUE}python3 test_chat_router.py${NC}"
echo -e "   ${YELLOW}测试日志将保存到: ./log/test_chat_router_<时间戳>.log${NC}"
echo
echo "3. 部署 Nginx 配置（源站使用 Cloudflare Origin 证书）："
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
