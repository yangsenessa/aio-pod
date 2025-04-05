# AIO-MCP Execution Service

A Python FastAPI application for uploading, storing, and executing AIO Agent and MCP executable files.

## Features

- File Upload: Support for uploading AIO Agent and MCP executable files
- File Management: List, view details, and delete uploaded files
- File Execution: Execute executable files in standard I/O mode
- JSON-RPC: Support for calling executable files using JSON-RPC protocol
- API Documentation: Built-in Swagger and ReDoc API documentation

## Installation and Running

### Prerequisites

- Python 3.8+
- Conda (Anaconda or Miniconda)

### Installing Dependencies

Using the existing univoice conda environment:

```bash
# Activate the environment
conda activate univoice

# Install dependencies
pip install -r requirements.txt
```

Or create a new environment if needed:

```bash
# Create a new conda environment
conda create -n aio_server python=3.9

# Activate the environment
conda activate aio_server

# Install dependencies
pip install -r requirements.txt
```

### Configuration

Create or modify the `.env` file in the project root directory:

```
API_VERSION=v1
LOG_LEVEL=info
PORT=8000
HOST=0.0.0.0
AGENT_EXEC_DIR=uploads/agent
MCP_EXEC_DIR=uploads/mcp
DATABASE_URL=sqlite:///./aio_server.db
ALLOWED_ORIGINS=["*"]
```

### Running the Service

Using the start script:

```bash
./start.sh
```

Or manually:

```bash
conda activate univoice
python main.py
```

Or using uvicorn directly:

```bash
conda activate univoice
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

## API Endpoints

### File Upload

- `POST /api/v1/upload`: Upload executable file

### File Management

- `GET /api/v1/files`: List uploaded files
- `GET /api/v1/files/{file_type}/{filename}`: Get file details
- `DELETE /api/v1/files/{file_type}/{filename}`: Delete file

### File Execution

- `POST /api/v1/execute`: Execute uploaded executable file
- `POST /api/v1/rpc/{file_type}/{filename}`: Execute executable file using JSON-RPC protocol

## API Documentation

- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

## Docker Deployment

Build and run using Docker:

```bash
docker build -t aio-server .
docker run -p 8000:8000 -v ./uploads:/app/uploads aio-server
```

Or using Docker Compose:

```bash
docker-compose up -d
``` 