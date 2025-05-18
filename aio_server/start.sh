#!/bin/bash

# Ensure script stops on error
set -e

# Print colored text
print_green() {
    echo -e "\033[0;32m$1\033[0m"
}

print_blue() {
    echo -e "\033[0;34m$1\033[0m"
}

print_red() {
    echo -e "\033[0;31m$1\033[0m"
}

# Function to check if a port is available
check_port() {
    local port=$1
    if lsof -i :$port > /dev/null 2>&1; then
        return 1
    else
        return 0
    fi
}

# Function to wait for server to be ready
wait_for_server() {
    local port=$1
    local protocol=$2
    local max_attempts=30
    local attempt=1
    
    print_blue "Waiting for server on port $port to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if [ "$protocol" = "https" ]; then
            response=$(curl -sk "https://localhost:$port/health" 2>&1)
            if [ $? -eq 0 ] && [ "$(echo $response | jq -r '.status' 2>/dev/null)" = "healthy" ]; then
                print_green "Server on port $port is ready! (HTTPS)"
                return 0
            fi
        else
            response=$(curl -s "http://localhost:$port/health" 2>&1)
            if [ $? -eq 0 ] && [ "$(echo $response | jq -r '.status' 2>/dev/null)" = "healthy" ]; then
                print_green "Server on port $port is ready! (HTTP)"
                return 0
            fi
        fi
        sleep 1
        attempt=$((attempt + 1))
        print_blue "Waiting for server on port $port (attempt $attempt/$max_attempts)... Last response: $response"
    done
    
    print_red "Server on port $port failed to start after $max_attempts seconds. Last response: $response"
    return 1
}

# Function to cleanup processes
cleanup() {
    print_blue "Cleaning up processes..."
    if [ ! -z "$FILE_SERVER_PID" ]; then
        kill -9 $FILE_SERVER_PID 2>/dev/null || true
    fi
    if [ ! -z "$EXEC_SERVER_PID" ]; then
        kill -9 $EXEC_SERVER_PID 2>/dev/null || true
    fi
    pkill -P $$ 2>/dev/null || true
}

# Default configuration
CONDA_ENV="aiopod"
LOG_LEVEL=debug
HTTPS_ENABLED=false
HTTP_ENABLED=true
CERT_DIR="./certs"
SSL_CERT_FILE="$CERT_DIR/server.crt"
SSL_KEY_FILE="$CERT_DIR/server.key"
FILE_SERVER_PORT=8001
EXEC_SERVER_PORT=8000
WORKSPACE_ROOT="/root/AIO-2030/aio-pod"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --https)
            HTTPS_ENABLED=true
            shift
            ;;
        --http)
            HTTP_ENABLED=true
            shift
            ;;
        --cert)
            SSL_CERT_FILE="$2"
            shift 2
            ;;
        --key)
            SSL_KEY_FILE="$2"
            shift 2
            ;;
        *)
            print_red "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set up trap for cleanup
trap cleanup INT TERM

# Check Python version
PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}')
print_blue "Detected Python version: $PYTHON_VERSION"

# Check if conda is available
if ! command -v conda &> /dev/null; then
    print_red "conda not found. Please install Anaconda or Miniconda"
    exit 1
fi

# Check if ports are available
if ! check_port $FILE_SERVER_PORT; then
    print_red "Port $FILE_SERVER_PORT is already in use"
    exit 1
fi

if ! check_port $EXEC_SERVER_PORT; then
    print_red "Port $EXEC_SERVER_PORT is already in use"
    exit 1
fi

# Setup SSL certificates if HTTPS is enabled
if [ "$HTTPS_ENABLED" = true ]; then
    print_blue "Setting up HTTPS..."
    
    # Create certificates directory if it doesn't exist
    mkdir -p "$CERT_DIR"
    
    # Generate self-signed certificate if it doesn't exist
    if [ ! -f "$SSL_CERT_FILE" ] || [ ! -f "$SSL_KEY_FILE" ]; then
        print_blue "Generating self-signed SSL certificate..."
        openssl req -x509 -newkey rsa:4096 \
            -keyout "$SSL_KEY_FILE" \
            -out "$SSL_CERT_FILE" \
            -days 365 -nodes \
            -subj "/CN=localhost" \
            -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
    fi
    
    # Check if certificate files exist and are readable
    if [ ! -f "$SSL_CERT_FILE" ] || [ ! -f "$SSL_KEY_FILE" ]; then
        print_red "SSL certificate files not found!"
        exit 1
    fi
    
    if [ ! -r "$SSL_CERT_FILE" ] || [ ! -r "$SSL_KEY_FILE" ]; then
        print_red "SSL certificate files are not readable!"
        exit 1
    fi
fi

# Activate conda environment
print_blue "Activating conda environment..."
eval "$(conda shell.bash hook)"
conda activate $CONDA_ENV || { print_red "Failed to activate conda environment"; exit 1; }

# Install dependencies
print_blue "Installing dependencies..."
pip install -r requirements.txt || { print_red "Failed to install dependencies"; exit 1; }

# Create upload directories
print_blue "Creating upload directories..."
mkdir -p uploads/agent uploads/mcp

# Kill any existing processes on ports
print_blue "Cleaning up existing processes..."
lsof -ti:$FILE_SERVER_PORT,$EXEC_SERVER_PORT | xargs -r kill -9

# Export PYTHONPATH
export PYTHONPATH=$WORKSPACE_ROOT:$PYTHONPATH

# Start file server (port 8001)
print_blue "Starting file server on port $FILE_SERVER_PORT..."
cd $WORKSPACE_ROOT/aio_server
if [ "$HTTPS_ENABLED" = true ]; then
    nohup uvicorn server:app \
        --host 0.0.0.0 \
        --port $FILE_SERVER_PORT \
        --ssl-certfile "$SSL_CERT_FILE" \
        --ssl-keyfile "$SSL_KEY_FILE" \
        --reload \
        --log-level debug > file_server.log 2>&1 &
    FILE_SERVER_PID=$!
    print_green "File server started with HTTPS on port $FILE_SERVER_PORT (PID: $FILE_SERVER_PID)"
else
    nohup uvicorn server:app \
        --host 0.0.0.0 \
        --port $FILE_SERVER_PORT \
        --reload \
        --log-level debug > file_server.log 2>&1 &
    FILE_SERVER_PID=$!
    print_green "File server started with HTTP on port $FILE_SERVER_PORT (PID: $FILE_SERVER_PID)"
fi

# Start execution server (port 8000)
print_blue "Starting execution server on port $EXEC_SERVER_PORT..."
cd $WORKSPACE_ROOT/aio_server
if [ "$HTTPS_ENABLED" = true ]; then
    nohup env PYTHONPATH=$WORKSPACE_ROOT/aio_server uvicorn app.api.server:app \
        --host 0.0.0.0 \
        --port $EXEC_SERVER_PORT \
        --ssl-keyfile "$SSL_KEY_FILE" \
        --ssl-certfile "$SSL_CERT_FILE" \
        --reload \
        --log-level debug > exec_server.log 2>&1 &
    EXEC_SERVER_PID=$!
    print_green "Execution server started with HTTPS on port $EXEC_SERVER_PORT (PID: $EXEC_SERVER_PID)"
else
    nohup env PYTHONPATH=$WORKSPACE_ROOT/aio_server uvicorn app.api.server:app \
        --host 0.0.0.0 \
        --port $EXEC_SERVER_PORT \
        --reload \
        --log-level debug > exec_server.log 2>&1 &
    EXEC_SERVER_PID=$!
    print_green "Execution server started with HTTP on port $EXEC_SERVER_PORT (PID: $EXEC_SERVER_PID)"
fi

# Wait for servers to be ready
protocol="http"
if [ "$HTTPS_ENABLED" = true ]; then
    protocol="https"
fi

wait_for_server $FILE_SERVER_PORT $protocol || { 
    print_red "File server failed to start"
    cleanup
    exit 1
}

wait_for_server $EXEC_SERVER_PORT $protocol || {
    print_red "Execution server failed to start"
    cleanup
    exit 1
}

print_green "All servers are running!"
print_blue "File server is running on $protocol://localhost:$FILE_SERVER_PORT (PID: $FILE_SERVER_PID)"
print_blue "Execution server is running on $protocol://localhost:$EXEC_SERVER_PORT (PID: $EXEC_SERVER_PID)"

# Removed wait -n and final cleanup so the script exits after starting the services

# conda environment exit (if script can reach here)
conda deactivate 