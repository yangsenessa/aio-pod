import uvicorn
import os
from dotenv import load_dotenv
from app.api.server import create_app

# Load environment variables
load_dotenv()

app = create_app()

if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    log_level = os.getenv("LOG_LEVEL", "info").lower()
    
    uvicorn.run(
        "main:app",
        host=host,
        port=port,
        reload=False,
        log_level=log_level
    ) 