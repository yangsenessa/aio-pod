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

# Check Python version
PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}')
print_blue "Detected Python version: $PYTHON_VERSION"

# Environment name - use existing univoice environment
CONDA_ENV="univoice"

# Check if conda is available
if ! command -v conda &> /dev/null; then
    print_red "conda not found. Please install Anaconda or Miniconda"
    exit 1
fi

# Activate conda environment
print_blue "Activating conda environment..."
eval "$(conda shell.bash hook)"
conda activate $CONDA_ENV

# Install dependencies
print_blue "Installing dependencies..."
pip install -r requirements.txt

# Create upload directories
print_blue "Ensuring upload directories exist..."
mkdir -p uploads/agent uploads/mcp

# Kill any existing processes on ports 8000 and 8001
print_blue "Cleaning up existing processes..."
lsof -ti:8000,8001 | xargs -r kill -9

# Start file server (port 8001)
print_blue "Starting file server on port 8001..."
python server.py &

# Start execution server (port 8000)
print_blue "Starting execution server on port 8000..."
PYTHONPATH=/root/AIO-2030/aio-pod/aio_server uvicorn main:app --host 0.0.0.0 --port 8000

# Wait for any process to exit
wait

# Catch Ctrl+C signal
trap 'echo -e "\nService stopped"; exit 0' INT

# conda environment exit (if script can reach here)
conda deactivate 