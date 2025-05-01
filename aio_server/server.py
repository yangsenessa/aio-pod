import os
import sys
import logging
from logging.handlers import TimedRotatingFileHandler
from datetime import datetime
from fastapi import FastAPI, UploadFile, File, HTTPException, Query, Request, Form, Body
from fastapi.responses import JSONResponse, FileResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.routing import APIRoute
import shutil
from pathlib import Path
from typing import Optional, List, Dict, Any
from app.models.schemas import FileType
from fastapi.encoders import jsonable_encoder
from fastapi.datastructures import UploadFile as FastAPIUploadFile
from starlette.datastructures import UploadFile as StarletteUploadFile

# Configure logging
def setup_logger():
    # Create log directory
    log_dir = Path("log")
    log_dir.mkdir(exist_ok=True)
    
    # Set log file name format
    log_file = log_dir / "file_server.log"
    
    # Create log handler
    handler = TimedRotatingFileHandler(
        log_file,
        when="midnight",  # Roll over at midnight
        interval=1,
        backupCount=30,  # Keep 30 days of logs
        encoding="utf-8"
    )
    
    # Set log format
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    handler.setFormatter(formatter)
    
    # Configure root logger
    logger = logging.getLogger()
    logger.setLevel(logging.DEBUG)  # Set to DEBUG level
    logger.addHandler(handler)
    
    # Also log to console
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
    
    return logger

# Initialize logger
logger = setup_logger()

class NoAliasingAPIRoute(APIRoute):
    def get_route_handler(self):
        original_route_handler = super().get_route_handler()
        async def custom_route_handler(request: Request):
            return await original_route_handler(request)
        return custom_route_handler

app = FastAPI(
    title="AIO-MCP File Server",
    description="File upload and download service for AIO-MCP",
    version="1.0.0",
    debug=True,
)

# Configure CORS - Must be before any routes
origins = [
    "http://localhost:4173",
    "http://localhost:3000",
    "http://localhost:8080",
    "*"  # Allow all origins as fallback
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
    max_age=3600,
)

@app.middleware("http")
async def cors_middleware(request: Request, call_next):
    if request.method == "OPTIONS":
        response = Response(
            status_code=200,
            headers={
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "*",
                "Access-Control-Allow-Headers": "*",
                "Access-Control-Allow-Credentials": "true",
                "Access-Control-Max-Age": "3600",
            },
        )
        return response
    
    response = await call_next(request)
    
    # Add CORS headers to all responses
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "*"
    response.headers["Access-Control-Allow-Credentials"] = "true"
    
    return response

@app.get("/")
async def download_file(type: str = Query(..., description="File type (agent, mcp, img, or video)"), filename: str = Query(..., description="File name")):
    try:
        # Validate file type
        if type not in ["agent", "mcp", "img", "video"]:
            raise HTTPException(status_code=400, detail="Invalid file type. Must be 'agent', 'mcp', 'img', or 'video'")
        
        # Construct file path
        file_path = os.path.join("uploads", type, filename)
        
        # Check if file exists
        if not os.path.exists(file_path):
            raise HTTPException(status_code=404, detail="File not found")
        
        # Return file
        return FileResponse(file_path, filename=filename)
    except Exception as e:
        logger.error(f"File download failed: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/upload/{type}", summary="Upload file")
async def upload_file(type: str, request: Request):
    """
    Generic upload endpoint that handles all file types
    """
    try:
        # Log request details
        logger.info(f"Received upload request for type: {type}")
        logger.info(f"Content-Type: {request.headers.get('content-type')}")
        logger.info(f"Content-Length: {request.headers.get('content-length')}")
        
        # Validate file type
        if type not in ["agent", "mcp", "img", "video"]:
            return JSONResponse(
                status_code=400,
                content={"detail": "Invalid file type"},
                headers={"Access-Control-Allow-Origin": "*"}
            )
            
        try:
            # Parse form with explicit size limit
            form = await request.form()
            file = form.get("file")
            if not file:
                raise ValueError("No file found in form data")
                
            logger.info(f"File received: {file.filename}")
            
            # Create upload directory
            upload_dir = Path(f"uploads/{type}")
            upload_dir.mkdir(parents=True, exist_ok=True)
            
            # Save file with progress logging
            file_path = upload_dir / file.filename
            size_written = 0
            
            with open(file_path, "wb") as f:
                while chunk := await file.read(1024 * 1024):  # 1MB chunks
                    size_written += len(chunk)
                    f.write(chunk)
                    logger.debug(f"Written {size_written} bytes")
            
            logger.info(f"Upload complete: {file_path}")
            
            return JSONResponse(
                status_code=200,
                content={
                    "success": True,
                    "message": "File upload successful",
                    "filename": file.filename,
                    "filepath": str(file_path),
                    "size": size_written
                },
                headers={"Access-Control-Allow-Origin": "*"}
            )
            
        except Exception as e:
            logger.error(f"Upload error: {str(e)}")
            return JSONResponse(
                status_code=400,
                content={"detail": str(e)},
                headers={"Access-Control-Allow-Origin": "*"}
            )
            
    except Exception as e:
        logger.error(f"Server error: {str(e)}")
        return JSONResponse(
            status_code=500,
            content={"detail": str(e)},
            headers={"Access-Control-Allow-Origin": "*"}
        )

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

if __name__ == "__main__":
    # Create upload directories
    for dir_name in ["agent", "mcp", "img", "video"]:
        Path(f"uploads/{dir_name}").mkdir(parents=True, exist_ok=True)
    
    logger.info("Starting File Server")
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8001,
        log_level="debug",
        reload=False,
        workers=1,
        access_log=True,
        # Increase limits for large files
        limit_concurrency=1,  # Handle one upload at a time
        backlog=2048,
        timeout=1800,  # 30 minutes timeout
        timeout_keep_alive=120,
        # Increase upload size limits
        server_header=False,
        proxy_headers=True,
    ) 