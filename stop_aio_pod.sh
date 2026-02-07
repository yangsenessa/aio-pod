#!/bin/bash

# AIO-Pod Service Stop Script
# This script stops the AIO-Pod services

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

# Stop processes by PID file
stop_by_pid() {
    local service_name=$1
    local pid_file="$AIO_SERVER_DIR/${service_name}.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            print_info "Stopping $service_name (PID: $pid)..."
            kill -TERM "$pid"
            
            # Wait for graceful shutdown
            local count=0
            while kill -0 "$pid" 2>/dev/null && [ $count -lt 10 ]; do
                sleep 1
                count=$((count + 1))
            done
            
            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                print_warning "Force killing $service_name (PID: $pid)..."
                kill -KILL "$pid"
            fi
            
            rm -f "$pid_file"
            print_success "$service_name stopped"
        else
            print_warning "$service_name PID file exists but process not running"
            rm -f "$pid_file"
        fi
    else
        print_warning "No PID file found for $service_name"
    fi
}

# Stop processes by port
stop_by_port() {
    local port=$1
    local service_name=$2
    
    if lsof -i :$port > /dev/null 2>&1; then
        print_info "Stopping processes on port $port..."
        
        # Get PIDs (compatible with both Linux and macOS)
        local pids=$(lsof -ti:$port 2>/dev/null || true)
        
        if [[ -n "$pids" ]]; then
            # Try graceful shutdown first
            echo "$pids" | xargs kill -TERM 2>/dev/null || true
            
            # Wait for graceful shutdown
            local count=0
            while lsof -i :$port > /dev/null 2>&1 && [ $count -lt 10 ]; do
                sleep 1
                count=$((count + 1))
            done
            
            # Force kill if still running
            if lsof -i :$port > /dev/null 2>&1; then
                print_warning "Force killing processes on port $port..."
                pids=$(lsof -ti:$port 2>/dev/null || true)
                if [[ -n "$pids" ]]; then
                    echo "$pids" | xargs kill -KILL 2>/dev/null || true
                fi
            fi
        fi
        
        print_success "Processes on port $port stopped"
    else
        print_info "No processes running on port $port"
    fi
}

# Clean up log files
cleanup_logs() {
    print_info "Cleaning up log files..."
    
    cd "$AIO_SERVER_DIR"
    
    # Archive old logs
    for log_file in file_server.log exec_server.log chat_router.log; do
        if [[ -f "$log_file" ]]; then
            local timestamp=$(date +%Y%m%d_%H%M%S)
            mv "$log_file" "${log_file}.${timestamp}"
            print_info "Archived $log_file to ${log_file}.${timestamp}"
        fi
    done
    
    print_success "Log cleanup completed"
}

# Display status
display_status() {
    echo
    print_success "AIO-Pod services stopped successfully!"
    echo
    echo "=== Service Status ==="
    if lsof -i :$FILE_SERVER_PORT > /dev/null 2>&1; then
        echo "File Server: RUNNING on port $FILE_SERVER_PORT"
    else
        echo "File Server: STOPPED"
    fi
    
    if lsof -i :$EXEC_SERVER_PORT > /dev/null 2>&1; then
        echo "Exec Server: RUNNING on port $EXEC_SERVER_PORT"
    else
        echo "Exec Server: STOPPED"
    fi
    
    if lsof -i :$CHAT_ROUTER_PORT > /dev/null 2>&1; then
        echo "Chat Router: RUNNING on port $CHAT_ROUTER_PORT"
    else
        echo "Chat Router: STOPPED"
    fi
    
    # Check nginx status (compatible with both Linux and macOS)
    if command -v systemctl &> /dev/null; then
        # Linux with systemd
        if systemctl is-active --quiet nginx 2>/dev/null; then
            echo "Nginx: RUNNING"
        else
            echo "Nginx: STOPPED"
        fi
    elif command -v nginx &> /dev/null; then
        # Check if nginx process is running
        if pgrep -x nginx > /dev/null 2>&1; then
            echo "Nginx: RUNNING"
        else
            echo "Nginx: STOPPED"
        fi
    else
        echo "Nginx: NOT INSTALLED"
    fi
    echo
    echo "=== To Restart Services ==="
    echo "Start services: ./start_aio_pod.sh"
    
    # Show appropriate nginx commands based on platform
    if command -v systemctl &> /dev/null; then
        echo "Start nginx: systemctl start nginx"
        echo "Restart nginx: systemctl restart nginx"
    elif command -v nginx &> /dev/null; then
        echo "Start nginx: sudo nginx"
        echo "Restart nginx: sudo nginx -s reload"
        echo "Stop nginx: sudo nginx -s stop"
    fi
}

# Main execution
main() {
    print_info "Stopping AIO-Pod services..."
    echo
    
    # Stop by PID files first (graceful shutdown)
    stop_by_pid "file_server"
    stop_by_pid "exec_server"
    stop_by_pid "chat_router"
    
    # Stop by ports (fallback)
    stop_by_port $FILE_SERVER_PORT "file server"
    stop_by_port $EXEC_SERVER_PORT "exec server"
    stop_by_port $CHAT_ROUTER_PORT "chat router"
    
    # Clean up logs
    cleanup_logs
    
    # Display final status
    display_status
}

# Run main function
main "$@" 