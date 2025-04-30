import os
import logging
import ssl
import uvicorn
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.api.routes import router as api_router
from app.utils.config import get_settings
import time

async def log_request_middleware(request: Request, call_next):
    """Middleware to log request details"""
    start_time = time.time()
    
    # Log request details
    logging.info(f"""
    -------- Incoming Request --------
    Method: {request.method}
    URL: {request.url}
    Client IP: {request.client.host}
    Headers: {dict(request.headers)}
    """)
    
    # Process the request
    response = await call_next(request)
    
    # Calculate processing time
    process_time = time.time() - start_time
    
    # Log response details
    logging.info(f"""
    -------- Response Details --------
    Status Code: {response.status_code}
    Process Time: {process_time:.3f} seconds
    -------------------------------------
    """)
    
    return response

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
        version="v1",
        docs_url="/docs",
        redoc_url="/redoc",
    )
    
    # Add request logging middleware
    app.middleware("http")(log_request_middleware)
    
    # Configure CORS
    origins = ["*"]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["*"],
        expose_headers=["*"],
        max_age=3600,
    )
    
    # Add CORS middleware for preflight requests
    @app.middleware("http")
    async def cors_middleware(request: Request, call_next):
        if request.method == "OPTIONS":
            response = Response()
            response.headers["Access-Control-Allow-Origin"] = "*"
            response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
            response.headers["Access-Control-Allow-Headers"] = "*"
            response.headers["Access-Control-Allow-Credentials"] = "true"
            response.headers["Access-Control-Max-Age"] = "3600"
            return response
        response = await call_next(request)
        response.headers["Access-Control-Allow-Origin"] = "*"
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "*"
        response.headers["Access-Control-Allow-Credentials"] = "true"
        return response
    
    # Create upload directories (if they don't exist)
    os.makedirs(settings.agent_exec_dir, exist_ok=True)
    os.makedirs(settings.mcp_exec_dir, exist_ok=True)
    
    # Register API routes with new prefix
    app.include_router(api_router, prefix="/aip/v1")
    
    # Mount static files directory (for direct access to uploaded files)
    app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")
    
    return app

def run_server(host: str = "0.0.0.0", port: int = 8000, use_https: bool = False):
    """Run the server with HTTPS support"""
    app = create_app()
    
    if use_https:
        # SSL configuration
        ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ssl_context.load_cert_chain(
            certfile="./certs/server.crt",  # Path to your SSL certificate
            keyfile="./certs/server.key"    # Path to your SSL private key
        )
        
        # Run with HTTPS
        uvicorn.run(
            app,
            host=host,
            port=port,
            ssl_certfile="./certs/server.crt",
            ssl_keyfile="./certs/server.key"
        )
    else:
        # Run without HTTPS
        uvicorn.run(app, host=host, port=port)

if __name__ == "__main__":
    run_server() 