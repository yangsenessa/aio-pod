import os
import json
from functools import lru_cache
from typing import List
from pydantic import Field
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    """Application configuration class"""
    api_version: str = Field("v1", env="API_VERSION")
    log_level: str = Field("info", env="LOG_LEVEL")
    agent_exec_dir: str = Field("uploads/agent", env="AGENT_EXEC_DIR")
    mcp_exec_dir: str = Field("uploads/mcp", env="MCP_EXEC_DIR")
    database_url: str = Field("sqlite:///./aio_server.db", env="DATABASE_URL")
    allowed_origins: List[str] = Field(["*"], env="ALLOWED_ORIGINS")
    host: str = Field("0.0.0.0", env="HOST")
    port: int = Field(8000, env="PORT")
    
    class Config:
        env_file = ".env"
        extra = "ignore"  # Allow extra fields in environment
        
    def __init__(self, **data):
        super().__init__(**data)
        # Ensure paths are absolute
        self.agent_exec_dir = os.path.abspath(self.agent_exec_dir)
        self.mcp_exec_dir = os.path.abspath(self.mcp_exec_dir)
        
        # Parse ALLOWED_ORIGINS (if it's a JSON string)
        if isinstance(self.allowed_origins, str):
            try:
                self.allowed_origins = json.loads(self.allowed_origins)
            except json.JSONDecodeError:
                self.allowed_origins = [x.strip() for x in self.allowed_origins.split(",")]

@lru_cache()
def get_settings() -> Settings:
    """Get application configuration singleton"""
    return Settings() 