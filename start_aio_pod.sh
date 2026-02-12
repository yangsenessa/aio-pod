#!/bin/bash

# AIO-Pod Service Startup Script
# This script starts the AIO-Pod services after nginx is configured

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR"
AIO_SERVER_DIR="$WORKSPACE_ROOT/aio_server"
FILE_SERVER_PORT=8001
EXEC_SERVER_PORT=8000
CHAT_ROUTER_PORT=8002
CONDA_ENV="aiopod"

# Environment variables for PixelMug MCP Service
# =============================================================================
# 必需的环境变量 - 必须配置
# =============================================================================

# IoT角色ARN - 用于STS临时凭证申请
# 格式: qcs::cam::uin/{UIN}:roleName/{角色名称}
export IOT_ROLE_ARN="${IOT_ROLE_ARN:-qcs::cam::uin/YOUR_UIN:roleName/YOUR_ROLE_NAME}"

# =============================================================================
# 腾讯云访问凭证 - 必须配置
# =============================================================================

# 推荐使用子账号密钥，比主账号密钥更安全
export TC_SECRET_ID="${TC_SECRET_ID:-YOUR_SECRET_ID}"
export TC_SECRET_KEY="${TC_SECRET_KEY:-YOUR_SECRET_KEY}"

# =============================================================================
# COS对象存储配置 - 可选，如果使用COS功能需要配置
# =============================================================================

# COS存储桶拥有者UIN - 拥有COS存储桶的腾讯云账号UIN
export COS_OWNER_UIN="${COS_OWNER_UIN:-YOUR_UIN}"

# COS存储桶名称 - 用于存储像素图片和GIF动画
export COS_BUCKET_NAME="${COS_BUCKET_NAME:-your-bucket-name}"

# COS地域 - 存储桶所在的地域
export COS_REGION="${COS_REGION:-ap-guangzhou}"

# =============================================================================
# OpenClaw Gateway 配置 - Chat Router 服务需要
# =============================================================================

# OpenClaw Gateway 地址和端口
export OPENCLAW_GATEWAY_HOST="${OPENCLAW_GATEWAY_HOST:-127.0.0.1}"
export OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"

# OpenClaw Gateway 认证 Token
export OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-sk-lm-gyXsWZIS:opqYGydrY8dwynxrZNT6}"

# 默认 Agent ID
export OPENCLAW_DEFAULT_AGENT="${OPENCLAW_DEFAULT_AGENT:-main}"

# Chat Router 服务配置
export CHAT_ROUTER_HOST="${CHAT_ROUTER_HOST:-0.0.0.0}"
export CHAT_ROUTER_PORT="${CHAT_ROUTER_PORT:-8002}"

# =============================================================================
# 服务配置 - 可选，有默认值
# =============================================================================

# 默认地域 - 腾讯云服务默认地域
export DEFAULT_REGION="${DEFAULT_REGION:-ap-guangzhou}"

# COS存储桶名称（兼容旧版本）
export COS_BUCKET="${COS_BUCKET:-pixelmug-assets}"

# 日志级别 - DEBUG, INFO, WARNING, ERROR
export LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Print colored text
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

# Check if ports are available
check_ports() {
    print_info "Checking if ports are available..."
    
    if lsof -i :$FILE_SERVER_PORT > /dev/null 2>&1; then
        print_warning "Port $FILE_SERVER_PORT is already in use"
        return 1
    fi
    
    if lsof -i :$EXEC_SERVER_PORT > /dev/null 2>&1; then
        print_warning "Port $EXEC_SERVER_PORT is already in use"
        return 1
    fi
    
    if lsof -i :$CHAT_ROUTER_PORT > /dev/null 2>&1; then
        print_warning "Port $CHAT_ROUTER_PORT is already in use"
        return 1
    fi
    
    print_success "Ports $FILE_SERVER_PORT, $EXEC_SERVER_PORT and $CHAT_ROUTER_PORT are available"
    return 0
}

# Kill existing processes on ports
kill_existing_processes() {
    print_info "Cleaning up existing processes..."
    
    # Kill processes on our ports (compatible with both Linux and macOS)
    local pids=$(lsof -ti:$FILE_SERVER_PORT,$EXEC_SERVER_PORT,$CHAT_ROUTER_PORT 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        echo "$pids" | xargs kill -9 2>/dev/null || true
        print_info "Killed existing processes on ports $FILE_SERVER_PORT, $EXEC_SERVER_PORT, $CHAT_ROUTER_PORT"
    else
        print_info "No existing processes found on ports"
    fi
    
    print_success "Existing processes cleaned up"
}

# Setup conda environment
setup_conda() {
    print_info "Setting up conda environment..."
    
    # Add conda to PATH if not available
    if ! command -v conda &> /dev/null; then
        print_info "Conda not in PATH, searching for conda installation..."
        
        # Common conda installation locations
        CONDA_PATHS=(
            "$HOME/miniconda3"
            "$HOME/anaconda3"
            "$HOME/conda"
            "/opt/conda"
            "/opt/miniconda3"
            "/opt/anaconda3"
        )
        
        CONDA_FOUND=false
        for conda_path in "${CONDA_PATHS[@]}"; do
            if [[ -f "$conda_path/bin/conda" ]]; then
                print_info "Found conda at: $conda_path"
                export PATH="$conda_path/bin:$PATH"
                eval "$($conda_path/bin/conda shell.bash hook)"
                CONDA_FOUND=true
                break
            fi
        done
        
        if [[ "$CONDA_FOUND" == false ]]; then
            print_error "conda not found. Please install Anaconda or Miniconda"
            print_info "Common installation locations checked:"
            for conda_path in "${CONDA_PATHS[@]}"; do
                print_info "  - $conda_path"
            done
            exit 1
        fi
    fi
    
    # Check if conda is now available
    if ! command -v conda &> /dev/null; then
        print_error "conda not found. Please install Anaconda or Miniconda"
        exit 1
    fi
    
    # Activate conda environment
    eval "$(conda shell.bash hook)"
    conda activate $CONDA_ENV || {
        print_warning "Failed to activate conda environment $CONDA_ENV"
        print_info "Creating new conda environment..."
        conda create -n $CONDA_ENV python=3.9 -y
        conda activate $CONDA_ENV
    }
    
    print_success "Conda environment activated"
}

# Install dependencies
install_dependencies() {
    print_info "Installing Python dependencies..."
    
    cd "$AIO_SERVER_DIR"
    
    # Install requirements
    if [[ -f "requirements.txt" ]]; then
        pip install -r requirements.txt
        print_success "Dependencies installed"
    else
        print_warning "requirements.txt not found, installing basic dependencies"
        pip install fastapi uvicorn python-multipart
    fi
}

# Create upload directories
create_directories() {
    print_info "Creating upload directories..."
    
    cd "$AIO_SERVER_DIR"
    
    # Create upload directories
    for dir_name in ["agent", "mcp", "img", "video"]; do
        mkdir -p "uploads/$dir_name"
    done
    
    print_success "Upload directories created"
}

# Start file server
start_file_server() {
    print_info "Starting file server on port $FILE_SERVER_PORT..."
    
    cd "$AIO_SERVER_DIR"
    
    # Start file server in background
    nohup uvicorn server:app \
        --host 0.0.0.0 \
        --port $FILE_SERVER_PORT \
        --log-level debug > file_server.log 2>&1 &
    
    FILE_SERVER_PID=$!
    echo $FILE_SERVER_PID > file_server.pid
    
    print_success "File server started (PID: $FILE_SERVER_PID)"
}

# Start exec server (if exists)
start_exec_server() {
    print_info "Starting exec server on port $EXEC_SERVER_PORT..."
    
    cd "$AIO_SERVER_DIR"
    
    # Check if exec server exists, otherwise use main.py
    if [[ -f "exec_server.py" ]]; then
        nohup uvicorn exec_server:app \
            --host 0.0.0.0 \
            --port $EXEC_SERVER_PORT \
            --log-level debug > exec_server.log 2>&1 &
        
        EXEC_SERVER_PID=$!
        echo $EXEC_SERVER_PID > exec_server.pid
        
        print_success "Exec server started (PID: $EXEC_SERVER_PID)"
    elif [[ -f "main.py" ]]; then
        # Use main.py to start the server on port 8000
        nohup python3 main.py > exec_server.log 2>&1 &
        
        EXEC_SERVER_PID=$!
        echo $EXEC_SERVER_PID > exec_server.pid
        
        print_success "Main server started on port $EXEC_SERVER_PORT (PID: $EXEC_SERVER_PID)"
    else
        print_warning "Neither exec_server.py nor main.py found, skipping exec server"
    fi
}

# Start chat router server
start_chat_router() {
    print_info "Starting chat router server on port $CHAT_ROUTER_PORT..."
    
    cd "$AIO_SERVER_DIR"
    
    if [[ ! -f "chat_router_server.py" ]]; then
        print_warning "chat_router_server.py not found, skipping chat router server"
        return
    fi
    
    # 使用当前已激活的 conda 环境中的 Python（确保有 uvicorn）
    local python_cmd="python3"
    if [[ -n "$CONDA_PREFIX" ]]; then
        python_cmd="$CONDA_PREFIX/bin/python3"
        if [[ ! -x "$python_cmd" ]]; then
            python_cmd="python3"
        fi
    fi
    
    # 启动前检查 uvicorn 是否可用
    if ! $python_cmd -c "import uvicorn" 2>/dev/null; then
        print_warning "当前 Python 环境缺少 uvicorn，尝试使用 aiopod 环境..."
        if [[ -n "$CONDA_PREFIX" ]]; then
            python_cmd="$CONDA_PREFIX/bin/python3"
        fi
        for conda_base in "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/conda" "/opt/conda" "/opt/miniconda3" "/opt/anaconda3"; do
            if [[ -x "$conda_base/envs/aiopod/bin/python3" ]]; then
                python_cmd="$conda_base/envs/aiopod/bin/python3"
                if $python_cmd -c "import uvicorn" 2>/dev/null; then
                    print_success "使用 aiopod 环境: $python_cmd"
                    break
                fi
            fi
        done
    fi
    
    if ! $python_cmd -c "import uvicorn" 2>/dev/null; then
        print_error "Chat Router 启动失败: 未找到已安装 uvicorn 的 Python"
        print_info "请先执行: conda activate aiopod && pip install -r aio_server/requirements.txt"
        print_info "或直接在本脚本中已激活 aiopod 的情况下重新运行 ./start_aio_pod.sh"
        return
    fi
    
    nohup $python_cmd chat_router_server.py > chat_router.log 2>&1 &
    
    CHAT_ROUTER_PID=$!
    echo $CHAT_ROUTER_PID > chat_router.pid
    
    print_success "Chat router server started (PID: $CHAT_ROUTER_PID)"
}

# Wait for servers to be ready
wait_for_servers() {
    print_info "Waiting for servers to be ready..."
    
    local max_attempts=30
    local attempt=1
    
    # Wait for file server
    while [ $attempt -le $max_attempts ]; do
        if curl -s "http://localhost:$FILE_SERVER_PORT/health" > /dev/null 2>&1; then
            print_success "File server is ready"
            break
        fi
        
        sleep 1
        attempt=$((attempt + 1))
        print_info "Waiting for file server (attempt $attempt/$max_attempts)..."
    done
    
    if [ $attempt -gt $max_attempts ]; then
        print_error "File server failed to start"
        exit 1
    fi
    
    # Wait for exec server if it exists
    if [[ -f "$AIO_SERVER_DIR/exec_server.py" || -f "$AIO_SERVER_DIR/main.py" ]]; then
        attempt=1
        while [ $attempt -le $max_attempts ]; do
            if curl -s "http://localhost:$EXEC_SERVER_PORT/health" > /dev/null 2>&1; then
                print_success "Exec server is ready"
                break
            fi
            
            sleep 1
            attempt=$((attempt + 1))
            print_info "Waiting for exec server (attempt $attempt/$max_attempts)..."
        done
        
        if [ $attempt -gt $max_attempts ]; then
            print_warning "Exec server may not be ready"
        fi
    fi
    
    # Wait for chat router server if it exists
    if [[ -f "$AIO_SERVER_DIR/chat_router_server.py" ]]; then
        attempt=1
        while [ $attempt -le $max_attempts ]; do
            if curl -s "http://localhost:$CHAT_ROUTER_PORT/health" > /dev/null 2>&1; then
                print_success "Chat router server is ready"
                break
            fi
            
            sleep 1
            attempt=$((attempt + 1))
            print_info "Waiting for chat router server (attempt $attempt/$max_attempts)..."
        done
        
        if [ $attempt -gt $max_attempts ]; then
            print_warning "Chat router server may not be ready"
        fi
    fi
}

# Test endpoints
test_endpoints() {
    print_info "Testing endpoints..."
    
    # Test file server health
    if curl -s "http://localhost:$FILE_SERVER_PORT/health" | grep -q "healthy"; then
        print_success "File server health check passed"
    else
        print_warning "File server health check failed"
    fi
    
    # Test exec server health if it exists
    if [[ -f "$AIO_SERVER_DIR/exec_server.py" || -f "$AIO_SERVER_DIR/main.py" ]]; then
        if curl -s "http://localhost:$EXEC_SERVER_PORT/health" | grep -q "healthy"; then
            print_success "Exec server health check passed"
        else
            print_warning "Exec server health check failed"
        fi
    fi
    
    # Test chat router server health if it exists
    if [[ -f "$AIO_SERVER_DIR/chat_router_server.py" ]]; then
        if curl -s "http://localhost:$CHAT_ROUTER_PORT/health" > /dev/null 2>&1; then
            print_success "Chat router server health check passed"
        else
            print_warning "Chat router server health check failed"
        fi
    fi
}

# Display status
display_status() {
    echo
    print_success "AIO-Pod services started successfully!"
    echo
    echo "=== Service Status ==="
    echo "File Server: http://localhost:$FILE_SERVER_PORT"
    echo "Exec Server: http://localhost:$EXEC_SERVER_PORT"
    echo "Chat Router: http://localhost:$CHAT_ROUTER_PORT"
    echo "Nginx Proxy: https://mcp.aio2030.fun"
    echo "Nginx Proxy (Chat): https://webchat.aio2030.fun"
    echo
    echo "=== Log Files ==="
    echo "File Server Log: $AIO_SERVER_DIR/file_server.log"
    echo "Exec Server Log: $AIO_SERVER_DIR/exec_server.log"
    echo "Chat Router Log: $AIO_SERVER_DIR/chat_router.log"
    echo "Nginx Access Log: /var/log/nginx/access.log"
    echo "Nginx Error Log: /var/log/nginx/error.log"
    echo
    echo "=== Management Commands ==="
    echo "Stop services: ./stop_aio_pod.sh"
    
    # Show appropriate nginx commands based on platform
    if command -v systemctl &> /dev/null; then
        echo "Restart nginx: systemctl restart nginx"
    elif command -v nginx &> /dev/null; then
        echo "Reload nginx: sudo nginx -s reload"
        echo "Stop nginx: sudo nginx -s stop"
    fi
    
    echo "View file server logs: tail -f $AIO_SERVER_DIR/file_server.log"
    echo "View exec server logs: tail -f $AIO_SERVER_DIR/exec_server.log"
    echo "View chat router logs: tail -f $AIO_SERVER_DIR/chat_router.log"
    echo
    echo "=== API Endpoints ==="
    echo "Health Check: https://mcp.aio2030.fun/health"
    echo "File Upload: https://mcp.aio2030.fun/api/v1/upload/{type}"
    echo "File Download: https://mcp.aio2030.fun/api/v1/?type={type}&filename={filename}"
    echo "MCP Execute: https://mcp.aio2030.fun/api/v1/mcp/{filename}"
    echo "Chat Completions: https://webchat.aio2030.fun/v1/chat/completions"
    echo "List Models: https://webchat.aio2030.fun/v1/models"
}

# Check OpenClaw Gateway configuration
check_gateway_config() {
    print_info "Checking OpenClaw Gateway configuration..."
    
    local config_missing=false
    
    # Check if Gateway host is configured
    if [[ "$OPENCLAW_GATEWAY_HOST" == "127.0.0.1" ]]; then
        print_info "  Gateway Host: $OPENCLAW_GATEWAY_HOST (local)"
    else
        print_info "  Gateway Host: $OPENCLAW_GATEWAY_HOST"
    fi
    
    # Check if Gateway port is configured
    if [[ "$OPENCLAW_GATEWAY_PORT" == "18789" ]]; then
        print_info "  Gateway Port: $OPENCLAW_GATEWAY_PORT (default)"
    else
        print_info "  Gateway Port: $OPENCLAW_GATEWAY_PORT"
    fi
    
    # Check if Gateway token is configured (without showing the actual token)
    if [[ -z "$OPENCLAW_GATEWAY_TOKEN" || "$OPENCLAW_GATEWAY_TOKEN" == "sk-lm-gyXsWZIS:opqYGydrY8dwynxrZNT6" ]]; then
        print_warning "  Gateway Token: 使用默认值 (建议配置实际的 Token)"
        config_missing=true
    else
        print_info "  Gateway Token: ${OPENCLAW_GATEWAY_TOKEN:0:15}... (已配置)"
    fi
    
    # Check default agent
    print_info "  Default Agent: $OPENCLAW_DEFAULT_AGENT"
    
    # Check Chat Router config
    print_info "  Chat Router Port: $CHAT_ROUTER_PORT"
    
    # Display configuration tips if needed
    if [[ "$config_missing" == true ]]; then
        echo
        print_warning "===== OpenClaw Gateway 配置提示 ====="
        print_info "Chat Router 需要连接到 OpenClaw Gateway 才能正常工作"
        print_info ""
        print_info "请在 export_env_local.sh 中配置以下环境变量："
        print_info ""
        echo "  # OpenClaw Gateway 配置"
        echo "  export OPENCLAW_GATEWAY_HOST=\"127.0.0.1\"          # Gateway 地址"
        echo "  export OPENCLAW_GATEWAY_PORT=\"18789\"              # Gateway 端口"
        echo "  export OPENCLAW_GATEWAY_TOKEN=\"your-token-here\"   # Gateway 认证 Token"
        echo "  export OPENCLAW_DEFAULT_AGENT=\"main\"              # 默认 Agent ID"
        echo "  export CHAT_ROUTER_PORT=\"8002\"                    # Chat Router 端口"
        print_info ""
        print_info "配置文件位置: $WORKSPACE_ROOT/export_env_local.sh"
        print_info ""
        print_info "如果还没有此文件，可以创建："
        echo "  cat > export_env_local.sh << 'EOF'"
        echo "  #!/bin/bash"
        echo "  # OpenClaw Gateway 配置"
        echo "  export OPENCLAW_GATEWAY_HOST=\"127.0.0.1\""
        echo "  export OPENCLAW_GATEWAY_PORT=\"18789\""
        echo "  export OPENCLAW_GATEWAY_TOKEN=\"your-actual-token\""
        echo "  export OPENCLAW_DEFAULT_AGENT=\"main\""
        echo "  export CHAT_ROUTER_PORT=\"8002\""
        echo "  EOF"
        echo "  chmod +x export_env_local.sh"
        print_info ""
        print_warning "配置后请重新运行: ./start_aio_pod.sh"
        echo "=========================================="
        echo
        
        # Ask if user wants to continue
        read -p "是否继续启动服务? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "启动已取消，请配置后重试"
            exit 0
        fi
    else
        print_success "OpenClaw Gateway 配置已完成"
    fi
}

# Load environment variables
load_environment() {
    print_info "Loading environment variables..."
    
    # Check if local environment file exists
    if [[ -f "$WORKSPACE_ROOT/export_env_local.sh" ]]; then
        print_info "Loading local environment configuration..."
        source "$WORKSPACE_ROOT/export_env_local.sh"
        print_success "Local environment configuration loaded"
    else
        print_warning "No local environment file found at $WORKSPACE_ROOT/export_env_local.sh"
        print_info "Using default environment variables"
    fi
    
    # Display key environment variables (without sensitive data)
    print_info "Environment configuration:"
    print_info "  IOT_ROLE_ARN: ${IOT_ROLE_ARN:0:20}..."
    print_info "  TC_SECRET_ID: ${TC_SECRET_ID:0:10}..."
    print_info "  DEFAULT_REGION: $DEFAULT_REGION"
    print_info "  LOG_LEVEL: $LOG_LEVEL"
}

# Main execution
main() {
    print_info "Starting AIO-Pod services..."
    print_info "Workspace: $WORKSPACE_ROOT"
    print_info "File Server Port: $FILE_SERVER_PORT"
    print_info "Exec Server Port: $EXEC_SERVER_PORT"
    print_info "Chat Router Port: $CHAT_ROUTER_PORT"
    echo
    
    load_environment
    check_gateway_config
    check_ports
    kill_existing_processes
    setup_conda
    install_dependencies
    create_directories
    start_file_server
    start_exec_server
    start_chat_router
    wait_for_servers
    test_endpoints
    display_status
}

# Run main function
main "$@" 