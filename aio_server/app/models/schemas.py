from datetime import datetime
from enum import Enum
from typing import Optional, Dict, Any, List
from pydantic import BaseModel, Field

class FileType(str, Enum):
    """File type enumeration"""
    AGENT = "agent"
    MCP = "mcp"

class UploadResponse(BaseModel):
    """File upload response model"""
    success: bool
    filepath: Optional[str] = None
    filename: Optional[str] = None
    download_url: Optional[str] = None
    message: str

class DownloadResponse(BaseModel):
    """File download response model"""
    success: bool
    filename: Optional[str] = None
    message: str

class FileInfo(BaseModel):
    """File information model"""
    id: str
    filename: str
    filepath: str
    file_type: FileType
    size: int
    created_at: datetime
    checksum: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None

class FileInfoResponse(BaseModel):
    """File information response model"""
    success: bool
    message: str
    file: Optional[FileInfo] = None

class FileListResponse(BaseModel):
    """File list response model"""
    success: bool
    message: str
    files: List[FileInfo] = []
    total: int = 0
    page: int = 1
    page_size: int = 20

class ExecutionRequest(BaseModel):
    """Execution request model"""
    filepath: str
    arguments: Optional[List[str]] = Field(default_factory=list)
    stdin_data: Optional[str] = None
    timeout: Optional[int] = 30  # Default timeout 30 seconds
    environment: Optional[Dict[str, str]] = None

class ExecutionResponse(BaseModel):
    """Execution response model"""
    success: bool
    stdout: Optional[str] = None
    stderr: Optional[str] = None
    exit_code: Optional[int] = None
    execution_time: Optional[float] = None
    message: str 