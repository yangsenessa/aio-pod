import os
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.api.routes import router as api_router
from app.utils.config import get_settings

def create_app() -> FastAPI:
    """Create FastAPI application instance"""
    settings = get_settings()
    
    # Configure logging
    logging.basicConfig(
        level=getattr(logging, settings.log_level.upper()),
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    # Create FastAPI app
    app = FastAPI(
        title="AIO-MCP Execution Service",
        description="Service for uploading, storing and executing AIO Agent and MCP executable files",
        version=settings.api_version,
        docs_url="/docs",
        redoc_url="/redoc",
    )
    
    # Configure CORS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    # Create upload directories (if they don't exist)
    os.makedirs(settings.agent_exec_dir, exist_ok=True)
    os.makedirs(settings.mcp_exec_dir, exist_ok=True)
    
    # Register API routes
    app.include_router(api_router, prefix=f"/api/{settings.api_version}")
    
    # Mount static files directory (for direct access to uploaded files)
    app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")
    
    return app 