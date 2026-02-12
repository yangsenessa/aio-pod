#!/bin/bash
# 本地开发：仅启动 Chat Router 服务（端口 8002）
# 用于前端连接 http://127.0.0.1:8002，无需 HTTPS 和域名

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 加载环境变量
if [[ -f "export_env_local.sh" ]]; then
    source export_env_local.sh
fi

# 默认端口
CHAT_ROUTER_PORT="${CHAT_ROUTER_PORT:-8002}"
AIO_SERVER_DIR="$SCRIPT_DIR/aio_server"

# 确定使用哪个 Python（优先使用已安装 uvicorn 的 aiopod 环境）
PYTHON_CMD=""
for conda_base in "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/conda" "/opt/conda" "/opt/miniconda3" "/opt/anaconda3"; do
    if [[ -x "$conda_base/envs/aiopod/bin/python3" ]]; then
        if "$conda_base/envs/aiopod/bin/python3" -c "import uvicorn" 2>/dev/null; then
            PYTHON_CMD="$conda_base/envs/aiopod/bin/python3"
            break
        fi
    fi
done

if [[ -z "$PYTHON_CMD" ]]; then
    if [[ -n "$CONDA_PREFIX" ]]; then
        if "$CONDA_PREFIX/bin/python3" -c "import uvicorn" 2>/dev/null; then
            PYTHON_CMD="$CONDA_PREFIX/bin/python3"
        fi
    fi
fi

if [[ -z "$PYTHON_CMD" ]]; then
    if python3 -c "import uvicorn" 2>/dev/null; then
        PYTHON_CMD="python3"
    fi
fi

if [[ -z "$PYTHON_CMD" ]]; then
    echo "错误: 未找到已安装 uvicorn 的 Python。"
    echo "请先执行以下之一："
    echo "  conda activate aiopod && pip install -r aio_server/requirements.txt"
    echo "  或运行 ./start_aio_pod.sh（会自动安装依赖并启动所有服务）"
    exit 1
fi

echo "=========================================="
echo "本地 Chat Router 启动 (仅端口 $CHAT_ROUTER_PORT)"
echo "=========================================="
echo "使用 Python: $PYTHON_CMD"
echo "API 地址: http://127.0.0.1:$CHAT_ROUTER_PORT"
echo "  - 健康检查: http://127.0.0.1:$CHAT_ROUTER_PORT/health"
echo "  - 对话接口: http://127.0.0.1:$CHAT_ROUTER_PORT/v1/chat/completions"
echo "  - 模型列表: http://127.0.0.1:$CHAT_ROUTER_PORT/v1/models"
echo "=========================================="
echo ""

# 检查端口是否被占用
if lsof -i :$CHAT_ROUTER_PORT > /dev/null 2>&1; then
    echo "端口 $CHAT_ROUTER_PORT 已被占用。若需重启，请先执行: ./stop_aio_pod.sh"
    echo "或手动停止: lsof -ti:$CHAT_ROUTER_PORT | xargs kill"
    exit 1
fi

# 进入 aio_server 目录并启动（前台运行，便于看日志）
cd "$AIO_SERVER_DIR"

if [[ ! -f "chat_router_server.py" ]]; then
    echo "错误: 未找到 chat_router_server.py"
    exit 1
fi

echo "正在启动 Chat Router..."
echo "按 Ctrl+C 停止服务"
echo ""

exec $PYTHON_CMD chat_router_server.py
