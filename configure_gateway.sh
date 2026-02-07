#!/bin/bash

# OpenClaw Gateway 配置向导
# 帮助用户快速配置 export_env_local.sh

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OpenClaw Gateway 配置向导${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# 检查是否已有配置文件
if [[ -f export_env_local.sh ]]; then
    echo -e "${YELLOW}⚠ 检测到已存在的配置文件: export_env_local.sh${NC}"
    echo
    read -p "是否要备份并创建新配置? (y/N): " -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        BACKUP_FILE="export_env_local.sh.backup.$(date +%Y%m%d_%H%M%S)"
        cp export_env_local.sh "$BACKUP_FILE"
        echo -e "${GREEN}✓ 已备份到: $BACKUP_FILE${NC}"
        echo
    else
        echo "配置已取消"
        exit 0
    fi
fi

# 询问用户配置
echo "请输入以下配置信息（按回车使用默认值）："
echo

# Gateway Host
read -p "Gateway 地址 [127.0.0.1]: " gateway_host
gateway_host=${gateway_host:-127.0.0.1}

# Gateway Port
read -p "Gateway 端口 [18789]: " gateway_port
gateway_port=${gateway_port:-18789}

# Gateway Token
echo
echo -e "${YELLOW}重要：请输入你的 Gateway Token${NC}"
echo "（从 OpenClaw Gateway 配置文件或管理界面获取）"
read -p "Gateway Token: " gateway_token

if [[ -z "$gateway_token" ]]; then
    echo -e "${YELLOW}⚠ 未输入 Token，将使用占位符${NC}"
    gateway_token="your-actual-token-here"
fi

# Default Agent
echo
read -p "默认 Agent ID [main]: " default_agent
default_agent=${default_agent:-main}

# Chat Router Port
read -p "Chat Router 端口 [8002]: " chat_router_port
chat_router_port=${chat_router_port:-8002}

# 生成配置文件
echo
echo -e "${BLUE}生成配置文件...${NC}"

cat > export_env_local.sh << EOF
#!/bin/bash

# =============================================================================
# AIO-Pod 本地环境配置文件
# 由配置向导自动生成于: $(date)
# =============================================================================

# =============================================================================
# OpenClaw Gateway 配置 - Chat Router 服务需要
# =============================================================================

# OpenClaw Gateway 地址
export OPENCLAW_GATEWAY_HOST="$gateway_host"

# OpenClaw Gateway 端口
export OPENCLAW_GATEWAY_PORT="$gateway_port"

# OpenClaw Gateway 认证 Token
export OPENCLAW_GATEWAY_TOKEN="$gateway_token"

# 默认 Agent ID
export OPENCLAW_DEFAULT_AGENT="$default_agent"

# Chat Router 服务端口
export CHAT_ROUTER_PORT="$chat_router_port"

# =============================================================================
# 腾讯云配置 - 根据需要配置
# =============================================================================

# IoT 角色 ARN
export IOT_ROLE_ARN="\${IOT_ROLE_ARN:-qcs::cam::uin/YOUR_UIN:roleName/YOUR_ROLE_NAME}"

# 腾讯云访问凭证
export TC_SECRET_ID="\${TC_SECRET_ID:-YOUR_SECRET_ID}"
export TC_SECRET_KEY="\${TC_SECRET_KEY:-YOUR_SECRET_KEY}"

# COS 对象存储配置
export COS_OWNER_UIN="\${COS_OWNER_UIN:-YOUR_UIN}"
export COS_BUCKET_NAME="\${COS_BUCKET_NAME:-your-bucket-name}"
export COS_REGION="\${COS_REGION:-ap-guangzhou}"
export COS_BUCKET="\${COS_BUCKET:-pixelmug-assets}"

# 通用配置
export DEFAULT_REGION="\${DEFAULT_REGION:-ap-guangzhou}"
export LOG_LEVEL="\${LOG_LEVEL:-INFO}"
EOF

chmod +x export_env_local.sh

echo -e "${GREEN}✓ 配置文件已创建: export_env_local.sh${NC}"
echo

# 显示配置摘要
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}配置摘要${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Gateway 地址: $gateway_host"
echo "Gateway 端口: $gateway_port"
echo "Gateway Token: ${gateway_token:0:15}..."
echo "默认 Agent: $default_agent"
echo "Chat Router 端口: $chat_router_port"
echo

# 提示下一步
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}下一步操作${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "1. 如果需要修改配置："
echo "   vim export_env_local.sh"
echo
echo "2. 启动服务："
echo "   ./start_aio_pod.sh"
echo
echo "3. 测试服务："
echo "   python3 test_chat_router.py"
echo
echo -e "${YELLOW}注意：确保 OpenClaw Gateway 已在 $gateway_host:$gateway_port 上运行${NC}"
echo
