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
WORKSPACE_ROOT="/root/AIO-2030/aio-pod"
AIO_SERVER_DIR="$WORKSPACE_ROOT/aio_server"
FILE_SERVER_PORT=8001
EXEC_SERVER_PORT=8000
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
    
    print_success "Ports $FILE_SERVER_PORT and $EXEC_SERVER_PORT are available"
    return 0
}

# Kill existing processes on ports
kill_existing_processes() {
    print_info "Cleaning up existing processes..."
    
    # Kill processes on our ports
    lsof -ti:$FILE_SERVER_PORT,$EXEC_SERVER_PORT | xargs -r kill -9 2>/dev/null || true
    
    print_success "Existing processes cleaned up"
}

# Setup conda environment
setup_conda() {
    print_info "Setting up conda environment..."
    
    # Add conda to PATH if not available
    if ! command -v conda &> /dev/null; then
        print_info "Adding conda to PATH..."
        export PATH="/root/miniconda3/bin:$PATH"
        
        # Initialize conda for this session
        eval "$(/root/miniconda3/bin/conda shell.bash hook)"
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
        nohup python main.py > exec_server.log 2>&1 &
        
        EXEC_SERVER_PID=$!
        echo $EXEC_SERVER_PID > exec_server.pid
        
        print_success "Main server started on port $EXEC_SERVER_PORT (PID: $EXEC_SERVER_PID)"
    else
        print_warning "Neither exec_server.py nor main.py found, skipping exec server"
    fi
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
    if [[ -f "$AIO_SERVER_DIR/exec_server.py" ]]; then
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
    if [[ -f "$AIO_SERVER_DIR/exec_server.py" ]]; then
        if curl -s "http://localhost:$EXEC_SERVER_PORT/health" | grep -q "healthy"; then
            print_success "Exec server health check passed"
        else
            print_warning "Exec server health check failed"
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
    echo "Nginx Proxy: https://mcp.aio2030.fun"
    echo
    echo "=== Log Files ==="
    echo "File Server Log: $AIO_SERVER_DIR/file_server.log"
    echo "Exec Server Log: $AIO_SERVER_DIR/exec_server.log"
    echo "Nginx Access Log: /var/log/nginx/access.log"
    echo "Nginx Error Log: /var/log/nginx/error.log"
    echo
    echo "=== Management Commands ==="
    echo "Stop services: ./stop_aio_pod.sh"
    echo "Restart nginx: systemctl restart nginx"
    echo "View file server logs: tail -f $AIO_SERVER_DIR/file_server.log"
    echo "View exec server logs: tail -f $AIO_SERVER_DIR/exec_server.log"
    echo
    echo "=== API Endpoints ==="
    echo "Health Check: https://mcp.aio2030.fun/health"
    echo "File Upload: https://mcp.aio2030.fun/api/v1/upload/{type}"
    echo "File Download: https://mcp.aio2030.fun/api/v1/?type={type}&filename={filename}"
    echo "MCP Execute: https://mcp.aio2030.fun/api/v1/mcp/{filename}"
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
    echo
    
    load_environment
    check_ports
    kill_existing_processes
    setup_conda
    install_dependencies
    create_directories
    start_file_server
    start_exec_server
    wait_for_servers
    test_endpoints
    display_status
}

# Run main function
main "$@" 