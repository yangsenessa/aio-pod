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
import sys
import argparse

# Define a single middleware for both request logging and CORS
async def combined_middleware(request: Request, call_next):
    """Middleware to handle both logging and CORS in a single pass"""
    start_time = time.time()
    
    # Log request details - only once
    logging.info(f"""
    -------- Incoming Request --------
    Method: {request.method}
    URL: {request.url}
    Client IP: {request.client.host}
    Headers: {dict(request.headers)}
    """)
    
    # Handle OPTIONS preflight requests
    if request.method == "OPTIONS":
        origin = request.headers.get("origin", "*")
        response = Response(status_code=200)
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, Accept, Origin, X-Requested-With"
        response.headers["Access-Control-Allow-Credentials"] = "true"
        response.headers["Access-Control-Max-Age"] = "3600"
        
        # Log response - reduced logging for OPTIONS
        process_time = time.time() - start_time
        logging.info(f"""
        -------- Response Details (OPTIONS) --------
        Status Code: 200
        Process Time: {process_time:.3f} seconds
        -------------------------------------
        """)
        
        return response
    
    try:
        # Process the request
        response = await call_next(request)
        
        # Add CORS headers
        origin = request.headers.get("origin", "*")
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, Accept, Origin, X-Requested-With"
        response.headers["Access-Control-Allow-Credentials"] = "true"
        
        # Log response
        process_time = time.time() - start_time
        logging.info(f"""
        -------- Response Details --------
        Status Code: {response.status_code}
        Process Time: {process_time:.3f} seconds
        -------------------------------------
        """)
        
        return response
    except Exception as e:
        logging.error(f"Request failed: {str(e)}")
        return Response(
            status_code=500,
            headers={
                "Access-Control-Allow-Origin": request.headers.get("origin", "*"),
                "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept, Origin, X-Requested-With",
                "Access-Control-Allow-Credentials": "true"
            }
        )

def create_app() -> FastAPI:
    """Create FastAPI application instance"""
    settings = get_settings()
    
    # Configure logging - first reset any existing handlers to avoid duplication
    root_logger = logging.getLogger()
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)
    
    logging.basicConfig(
        level=logging.INFO,  # Set root logger to INFO instead of DEBUG to reduce verbosity
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
        handlers=[
            logging.StreamHandler(),  # Console handler
            logging.FileHandler('app.log')  # File handler
        ]
    )
    
    # Set specific loggers to different levels as needed
    # Don't set ALL loggers to DEBUG as that's too verbose
    app_logger = logging.getLogger('app')
    app_logger.setLevel(logging.DEBUG)
    
    logging.debug("Debug logging is enabled in server")
    logging.info("Info logging is enabled in server")
    
    # Create FastAPI app
    app = FastAPI(
        title="AIO-MCP Execution Service",
        description="Service for uploading, storing and executing AIO Agent and MCP executable files",
        version="v1",
        docs_url="/docs",
        redoc_url="/redoc",
    )
    
    # Add single combined middleware for both logging and CORS
    app.middleware("http")(combined_middleware)
    
    # Configure CORS - use middleware instead of add_middleware to avoid duplicate processing
    # app.add_middleware(
    #     CORSMiddleware,
    #     allow_origins=["*"],
    #     allow_credentials=True,
    #     allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    #     allow_headers=["Content-Type", "Authorization", "Accept", "Origin", "X-Requested-With"],
    #     expose_headers=["Content-Type", "Authorization"],
    #     max_age=3600,
    # )
    
    # REMOVE THIS DUPLICATE MIDDLEWARE
    # @app.middleware("http")
    # async def cors_middleware(request: Request, call_next):
    #     if request.method == "OPTIONS":
    #         origin = request.headers.get("origin", "*")
    #         response = Response(status_code=200)
    #         response.headers["Access-Control-Allow-Origin"] = origin
    #         response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    #         response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, Accept, Origin, X-Requested-With"
    #         response.headers["Access-Control-Allow-Credentials"] = "true"
    #         response.headers["Access-Control-Max-Age"] = "3600"
    #         return response
    #         
    #     try:
    #         response = await call_next(request)
    #         origin = request.headers.get("origin", "*")
    #         response.headers["Access-Control-Allow-Origin"] = origin
    #         response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    #         response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization, Accept, Origin, X-Requested-With"
    #         response.headers["Access-Control-Allow-Credentials"] = "true"
    #         return response
    #     except Exception as e:
    #         logging.error(f"Request failed: {str(e)}")
    #         return Response(
    #             status_code=500,
    #             headers={
    #                 "Access-Control-Allow-Origin": request.headers.get("origin", "*"),
    #                 "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
    #                 "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept, Origin, X-Requested-With",
    #                 "Access-Control-Allow-Credentials": "true"
    #             }
    #         )
    
    # Add health check endpoint at root and /health
    @app.get("/")
    @app.get("/health")
    async def health_check():
        try:
            # Create upload directories if they don't exist
            os.makedirs("uploads/agent", exist_ok=True)
            os.makedirs("uploads/mcp", exist_ok=True)
            
            # Check if we can write to upload directories
            try:
                test_file = "uploads/agent/.test"
                with open(test_file, "w") as f:
                    f.write("test")
                os.remove(test_file)
                
                test_file = "uploads/mcp/.test"
                with open(test_file, "w") as f:
                    f.write("test")
                os.remove(test_file)
            except Exception as e:
                logging.error(f"Upload directories not writable: {str(e)}")
                return {"status": "error", "message": f"Upload directories not writable: {str(e)}"}
            
            return {
                "status": "healthy",
                "timestamp": time.time(),
                "uptime": time.time() - app.state.start_time if hasattr(app.state, 'start_time') else 0
            }
        except Exception as e:
            logging.error(f"Health check failed: {str(e)}")
            return {"status": "error", "message": str(e)}
    
    # Store start time for uptime calculation
    app.state.start_time = time.time()
    
    # Create upload directories (if they don't exist)
    os.makedirs(settings.agent_exec_dir, exist_ok=True)
    os.makedirs(settings.mcp_exec_dir, exist_ok=True)
    
    # Register API routes with version prefix
    app.include_router(api_router, prefix="/api/v1")
    
    # Log all registered routes for debugging
    for route in app.routes:
        logging.info(f"Registered route: {route.path} [{','.join(route.methods)}]")
    
    # Mount static files directory (for direct access to uploaded files)
    app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")
    
    return app

def run_server(host: str = "0.0.0.0", port: int = 8001, use_https: bool = False, cert_file: str = None, key_file: str = None):
    """Run the server with HTTPS support
    
    Args:
        host (str): Host address to bind to
        port (int): Port number to listen on
        use_https (bool): Whether to use HTTPS
        cert_file (str): Path to SSL certificate file
        key_file (str): Path to SSL private key file
    """
    try:
        # Create base configuration
        config = {
            "host": host,
            "port": port,
            "reload": True,  # Enable auto-reload for development
            "log_level": "info",
            "access_log": True,
            "workers": 1,
            "app": "app.api.server:create_app()"  # Use import string instead of direct app instance
        }
        
        if use_https:
            if not cert_file or not key_file:
                logging.error("Certificate and key files are required for HTTPS")
                sys.exit(1)
                
            if not os.path.exists(cert_file):
                logging.error(f"Certificate file not found: {cert_file}")
                sys.exit(1)
                
            if not os.path.exists(key_file):
                logging.error(f"Private key file not found: {key_file}")
                sys.exit(1)
            
            try:
                # Add SSL configuration
                config.update({
                    "ssl_certfile": cert_file,
                    "ssl_keyfile": key_file,
                    "ssl_version": ssl.PROTOCOL_TLS,
                })
                
            except Exception as e:
                logging.error(f"Failed to configure SSL: {str(e)}")
                sys.exit(1)
        
        logging.info(f"Starting server on {'HTTPS' if use_https else 'HTTP'}://{host}:{port}")
        uvicorn.run(**config)
        
    except Exception as e:
        logging.error(f"Failed to start server: {str(e)}")
        sys.exit(1)

# Create a global app instance for direct uvicorn use
app = create_app()

if __name__ == "__main__":
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    parser = argparse.ArgumentParser(description="AIO-MCP Server")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=8001, help="Port to listen on")
    parser.add_argument("--https", action="store_true", help="Enable HTTPS")
    parser.add_argument("--cert", help="Path to SSL certificate file")
    parser.add_argument("--key", help="Path to SSL private key file")
    
    args = parser.parse_args()
    
    run_server(
        host=args.host,
        port=args.port,
        use_https=args.https,
        cert_file=args.cert,
        key_file=args.key
    ) 