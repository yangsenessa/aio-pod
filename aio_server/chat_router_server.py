#!/usr/bin/env python3
"""
OpenAI-Compatible Chat Router Server
提供 OpenAI 兼容的 API 接口，路由到 OpenClaw Gateway
"""

import os
import uvicorn
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

from app.api.chat_router import router as chat_router

# 加载环境变量
load_dotenv()

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)

# 创建 FastAPI 应用
app = FastAPI(
    title="OpenAI-Compatible Chat Router",
    description="OpenAI 兼容的聊天路由服务，连接到 OpenClaw Gateway",
    version="1.0.0"
)

# 配置 CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 生产环境建议限制具体域名
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"]
)

# 注册路由
app.include_router(chat_router, tags=["Chat"])

@app.on_event("startup")
async def startup_event():
    """应用启动事件"""
    logger.info("=" * 60)
    logger.info("OpenAI-Compatible Chat Router Server Starting...")
    logger.info("=" * 60)
    
    # 显示配置信息
    gateway_host = os.getenv("OPENCLAW_GATEWAY_HOST", "127.0.0.1")
    gateway_port = os.getenv("OPENCLAW_GATEWAY_PORT", "18789")
    default_agent = os.getenv("OPENCLAW_DEFAULT_AGENT", "main")
    
    logger.info(f"Gateway: {gateway_host}:{gateway_port}")
    logger.info(f"Default Agent: {default_agent}")
    logger.info("=" * 60)

@app.on_event("shutdown")
async def shutdown_event():
    """应用关闭事件"""
    logger.info("OpenAI-Compatible Chat Router Server Shutting Down...")

if __name__ == "__main__":
    # 从环境变量获取配置
    host = os.getenv("CHAT_ROUTER_HOST", "0.0.0.0")
    port = int(os.getenv("CHAT_ROUTER_PORT", "8002"))
    log_level = os.getenv("LOG_LEVEL", "info").lower()
    
    logger.info(f"Starting server on {host}:{port}")
    
    uvicorn.run(
        "chat_router_server:app",
        host=host,
        port=port,
        reload=False,
        log_level=log_level
    )
