from fastapi import APIRouter, Depends, File, Form, UploadFile, HTTPException, Query, Path
from typing import List, Optional, Dict, Any
import os
import subprocess
import logging
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

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
logger.setLevel(getattr(logging, settings.log_level.upper()))

router = APIRouter()

# Dependency: Get application configuration
def get_config():
    return get_settings()

# File upload route


# JSON-RPC execution route
@router.post("/rpc/{file_type}/{filename}")
async def execute_rpc(
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
    # Get file path
    logger.info(f"RPC request params - file_type: {file_type}, filename: {filename}, method: {rpc_request.get('method')}, params: {rpc_request.get('params')}, timeout: {timeout}")
    file_path = FileService.get_file_path(file_type, filename)
    
    # Check if file exists
    if not FileService.file_exists(file_path):
        return {
            "jsonrpc": "2.0",
            "error": {
                "code": -32602,
                "message": f"File does not exist: {filename}"
            },
            "id": rpc_request.get("id") if rpc_request else None
        }
    
    # If no RPC request provided, return error
    if not rpc_request:
        return {
            "jsonrpc": "2.0",
            "error": {
                "code": -32600,
                "message": "Invalid request: Missing JSON-RPC request object"
            },
            "id": None
        }
    
    # Extract RPC parameters
    method = rpc_request.get("method")
    params = rpc_request.get("params")
    id = rpc_request.get("id")
    
    if not method:
        return {
            "jsonrpc": "2.0",
            "error": {
                "code": -32600,
                "message": "Invalid request: Missing method field"
            },
            "id": id
        }
    
    # Execute RPC request
    logger.info(f"Executing RPC request - filepath: {file_path}, method: {method}, params: {params}, id: {id}, timeout: {timeout}")
    result = await ExecutionService.execute_json_rpc(
        filepath=file_path,
        method=method,
        params=params,
        id=id,
        timeout=timeout
    )
    
    return result

@router.post("/execute/agent")
async def execute_agent(filename: str, args: Optional[str] = None):
    try:
        logger.info(f"Starting agent file execution: {filename}")
        file_path = os.path.join("uploads/agent", filename)
        
        if not os.path.exists(file_path):
            logger.error(f"Agent file does not exist: {file_path}")
            raise HTTPException(status_code=404, detail="File does not exist")
        
        if not os.access(file_path, os.X_OK):
            logger.error(f"Agent file does not have execute permission: {file_path}")
            raise HTTPException(status_code=403, detail="File does not have execute permission")
        
        cmd = [file_path]
        if args:
            cmd.extend(args.split())
        
        logger.info(f"Executing command: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            logger.error(f"Agent execution failed: {result.stderr}")
            raise HTTPException(status_code=500, detail=result.stderr)
        
        logger.info(f"Agent execution successful: {result.stdout}")
        return {"output": result.stdout}
    except Exception as e:
        logger.error(f"Agent execution error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/execute/mcp")
async def execute_mcp(filename: str, args: Optional[str] = None):
    try:
        logger.info(f"Starting mcp file execution: {filename}")
        file_path = os.path.join("uploads/mcp", filename)
        
        if not os.path.exists(file_path):
            logger.error(f"MCP file does not exist: {file_path}")
            raise HTTPException(status_code=404, detail="File does not exist")
        
        if not os.access(file_path, os.X_OK):
            logger.error(f"MCP file does not have execute permission: {file_path}")
            raise HTTPException(status_code=403, detail="File does not have execute permission")
        
        cmd = [file_path]
        if args:
            cmd.extend(args.split())
        
        logger.info(f"Executing command: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            logger.error(f"MCP execution failed: {result.stderr}")
            raise HTTPException(status_code=500, detail=result.stderr)
        
        logger.info(f"MCP execution successful: {result.stdout}")
        return {"output": result.stdout}
    except Exception as e:
        logger.error(f"MCP execution error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e)) 