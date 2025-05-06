from fastapi import APIRouter, Depends, File, Form, UploadFile, HTTPException, Query, Path, Request
from typing import List, Optional, Dict, Any
import os
import subprocess
import logging
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response

from app.models.schemas import (
    FileType, 
    UploadResponse, 
    DownloadResponse, 
    FileInfoResponse, 
    FileListResponse,
    ExecutionRequest, 
    ExecutionResponse
)
from app.services.file_service import FileService
from app.services.exec_service import ExecutionService
from app.utils.config import get_settings, Settings

# Configure logging
logger = logging.getLogger(__name__)
settings = get_settings()

router = APIRouter()  # Remove prefix, will be added by server.py

# Add OPTIONS handler for all routes
@router.options("/{path:path}")
async def options_handler(request: Request, path: str):
    origin = request.headers.get("origin", "*")
    return Response(
        headers={
            "Access-Control-Allow-Origin": origin,
            "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept, Origin, X-Requested-With",
            "Access-Control-Allow-Credentials": "true",
            "Access-Control-Max-Age": "3600"
        }
    )

# Dependency: Get application configuration
def get_config():
    return get_settings()

def get_cors_headers(request: Request) -> dict:
    """Helper function to get consistent CORS headers"""
    origin = request.headers.get("origin", "*")
    return {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept, Origin, X-Requested-With",
        "Access-Control-Allow-Credentials": "true"
    }

# JSON-RPC execution route
@router.post("/rpc/{file_type}/{filename}")
async def execute_rpc(
    request: Request,
    file_type: FileType = Path(..., description="File type"),
    filename: str = Path(..., description="Filename"),
    rpc_request: Dict[str, Any] = None,
    timeout: int = Query(30, ge=1, le=300, description="Execution timeout (seconds)"),
    config: Settings = Depends(get_config)
):
    """
    Execute uploaded executable file using JSON-RPC protocol
    
    - **file_type**: File type (agent or mcp)
    - **filename**: Filename
    - **rpc_request**: JSON-RPC request object
    - **timeout**: Execution timeout (seconds)
    """
    try:
        logger.info(f"Received RPC request - type: {file_type}, filename: {filename}")
        # Get file path and check for .bin suffix if it's an MCP file
        if file_type == FileType.MCP:
            logger.info(f"MCP file detected - type: {file_type}, filename: {filename}")
            base_path = FileService.get_file_path(file_type, filename)
            bin_path = f"{base_path}.bin"
            
            if os.path.exists(bin_path):
                file_path = bin_path
            elif os.path.exists(base_path):
                file_path = base_path
            else:
                logger.error(f"File does not exist: neither {base_path} nor {bin_path}")
                return JSONResponse(
                    status_code=404,
                    content={
                        "jsonrpc": "2.0",
                        "error": {
                            "code": -32602,
                            "message": f"File does not exist: {filename}"
                        },
                        "id": rpc_request.get("id") if rpc_request else None
                    },
                    headers=get_cors_headers(request)
                )
                
            # Set execute permissions for MCP files
            try:
                logger.info(f"Setting execute permissions for: {file_path}")
                os.chmod(file_path, 0o755)  # rwxr-xr-x
            except Exception as e:
                logger.error(f"Failed to set execute permissions: {str(e)}")
                return JSONResponse(
                    status_code=500,
                    content={
                        "jsonrpc": "2.0",
                        "error": {
                            "code": -32000,
                            "message": "Failed to set execute permissions"
                        },
                        "id": rpc_request.get("id") if rpc_request else None
                    },
                    headers=get_cors_headers(request)
                )
        else:
            file_path = FileService.get_file_path(file_type, filename)
            if not FileService.file_exists(file_path):
                return JSONResponse(
                    status_code=404,
                    content={
                        "jsonrpc": "2.0",
                        "error": {
                            "code": -32602,
                            "message": f"File does not exist: {filename}"
                        },
                        "id": rpc_request.get("id") if rpc_request else None
                    },
                    headers=get_cors_headers(request)
                )

        # If no RPC request provided, return error
        if not rpc_request:
            return JSONResponse(
                status_code=400,
                content={
                    "jsonrpc": "2.0",
                    "error": {
                        "code": -32600,
                        "message": "Invalid request: Missing JSON-RPC request object"
                    },
                    "id": None
                },
                headers=get_cors_headers(request)
            )

        # Extract RPC parameters
        method = rpc_request.get("method")
        params = rpc_request.get("params")
        id = rpc_request.get("id")

        if not method:
            return JSONResponse(
                status_code=400,
                content={
                    "jsonrpc": "2.0",
                    "error": {
                        "code": -32600,
                        "message": "Invalid request: Missing method field"
                    },
                    "id": id
                },
                headers=get_cors_headers(request)
            )

        # Execute RPC request
        logger.info(f"Executing RPC request - filepath: {file_path}, method: {method}, id: {id}, timeout: {timeout}")
        result = await ExecutionService.execute_json_rpc(
            filepath=file_path,
            method=method,
            params=params,
            id=id,
            timeout=timeout
        )

        return JSONResponse(content=result, headers=get_cors_headers(request))

    except Exception as e:
        logger.error(f"RPC execution error: {str(e)}")
        return JSONResponse(
            status_code=500,
            content={
                "jsonrpc": "2.0",
                "error": {
                    "code": -32000,
                    "message": str(e)
                },
                "id": rpc_request.get("id") if rpc_request else None
            },
            headers=get_cors_headers(request)
        )

@router.get("/health")
async def api_health_check(request: Request):
    return JSONResponse(
        content={"status": "healthy"},
        headers=get_cors_headers(request)
    ) 