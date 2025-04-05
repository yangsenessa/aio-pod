import os
import sys
import logging
from logging.handlers import TimedRotatingFileHandler
from datetime import datetime
from fastapi import FastAPI, UploadFile, File, HTTPException, Query
from fastapi.responses import JSONResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
import shutil
from pathlib import Path
from app.models.schemas import FileType

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
    logger.setLevel(logging.INFO)
    logger.addHandler(handler)
    
    return logger

# Initialize logger
logger = setup_logger()

app = FastAPI()

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins, in production set specific domains
    allow_credentials=True,
    allow_methods=["*"],  # Allow all methods
    allow_headers=["*"],  # Allow all headers
)

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

@app.post("/upload/mcp")
async def upload_mcp(file: UploadFile = File(...)):
    try:
        logger.info(f"Starting mcp file upload: {file.filename}")
        file_path = os.path.join("uploads/mcp", file.filename)
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        logger.info(f"MCP file upload successful: {file_path}")
        return {"message": "File upload successful", "filename": file.filename, "path": file_path}
    except Exception as e:
        logger.error(f"MCP file upload failed: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/upload/agent")
async def upload_agent(file: UploadFile = File(...)):
    try:
        logger.info(f"Starting agent file upload: {file.filename}")
        file_path = os.path.join("uploads/agent", file.filename)
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        logger.info(f"Agent file upload successful: {file_path}")
        return {"message": "File upload successful", "filename": file.filename, "path": file_path}
    except Exception as e:
        logger.error(f"Agent file upload failed: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/upload/img")
async def upload_img(file: UploadFile = File(...)):
    try:
        logger.info(f"Starting image file upload: {file.filename}")
        file_path = os.path.join("uploads/img", file.filename)
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        logger.info(f"Image file upload successful: {file_path}")
        return {"message": "File upload successful", "filename": file.filename, "path": file_path}
    except Exception as e:
        logger.error(f"Image file upload failed: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/upload/video")
async def upload_video(file: UploadFile = File(...)):
    try:
        logger.info(f"Starting video file upload: {file.filename}")
        file_path = os.path.join("uploads/video", file.filename)
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        
        logger.info(f"Video file upload successful: {file_path}")
        return {"message": "File upload successful", "filename": file.filename, "path": file_path}
    except Exception as e:
        logger.error(f"Video file upload failed: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    logger.info("Starting File Server")
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001) 