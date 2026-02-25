from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse, JSONResponse
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field
import logging

from app.services.chat_router_service import ChatRouterService

logger = logging.getLogger(__name__)

router = APIRouter()

# 创建聊天路由服务实例
chat_service = ChatRouterService()


class ChatMessage(BaseModel):
    """聊天消息模型"""
    role: str = Field(..., description="消息角色: system, user, assistant")
    content: str = Field(..., description="消息内容")
    name: Optional[str] = Field(None, description="消息发送者名称")


class ChatCompletionRequest(BaseModel):
    """聊天完成请求模型"""
    model: str = Field("openclaw:main", description="模型名称，格式: openclaw:{agent_id}")
    messages: List[ChatMessage] = Field(..., description="消息列表")
    temperature: Optional[float] = Field(None, ge=0.0, le=2.0, description="温度参数")
    top_p: Optional[float] = Field(None, ge=0.0, le=1.0, description="Top-p 采样参数")
    n: Optional[int] = Field(1, ge=1, description="生成的回复数量")
    stream: Optional[bool] = Field(False, description="是否流式返回")
    max_tokens: Optional[int] = Field(None, ge=1, description="最大token数")
    presence_penalty: Optional[float] = Field(None, ge=-2.0, le=2.0, description="存在惩罚")
    frequency_penalty: Optional[float] = Field(None, ge=-2.0, le=2.0, description="频率惩罚")
    user: Optional[str] = Field(
        None,
        description="OpenAI 用户标识。若传入，Gateway 会据此生成稳定 session key，同用户多次请求可共享同一 agent 会话（Session behavior）。"
    )
    user_nickname: Optional[str] = Field(None, description="用户昵称，可选透传到 Gateway")


class ModelInfo(BaseModel):
    """模型信息"""
    id: str
    object: str = "model"
    created: int
    owned_by: str


class ModelsResponse(BaseModel):
    """模型列表响应"""
    object: str = "list"
    data: List[ModelInfo]


def get_cors_headers(request: Request) -> dict:
    """获取 CORS 头"""
    origin = request.headers.get("origin", "*")
    return {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept, Origin, X-Requested-With",
        "Access-Control-Allow-Credentials": "true"
    }


@router.options("/{path:path}")
async def options_handler(request: Request, path: str):
    """处理 OPTIONS 请求"""
    from fastapi.responses import Response
    origin = request.headers.get("origin", "*")
    return Response(
        headers={
            "Access-Control-Allow-Origin": origin,
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept, Origin, X-Requested-With",
            "Access-Control-Allow-Credentials": "true",
            "Access-Control-Max-Age": "3600"
        }
    )


@router.get("/health")
async def health_check(request: Request):
    """健康检查"""
    # 检查 Gateway 是否可用
    is_healthy = await chat_service.check_gateway_health()
    
    if is_healthy:
        return JSONResponse(
            content={
                "status": "healthy",
                "gateway": "connected"
            },
            headers=get_cors_headers(request)
        )
    else:
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "gateway": "disconnected"
            },
            headers=get_cors_headers(request)
        )


@router.get("/v1/models")
async def list_models(request: Request):
    """列出可用模型"""
    import time
    
    models = [
        {
            "id": "openclaw:main",
            "object": "model",
            "created": int(time.time()),
            "owned_by": "openclaw"
        }
    ]
    
    return JSONResponse(
        content={
            "object": "list",
            "data": models
        },
        headers=get_cors_headers(request)
    )


@router.post("/v1/chat/completions")
async def chat_completions(
    request: Request,
    chat_request: ChatCompletionRequest
):
    """
    OpenAI 兼容的聊天完成接口
    
    支持流式和非流式响应
    """
    try:
        # 会话保持：只有稳定的 user 才能让 Gateway 派生同一 session key
        logger.info(
            "chat/completions request: model=%s stream=%s user=%s",
            chat_request.model,
            chat_request.stream,
            repr(chat_request.user) if chat_request.user is not None else "(absent)",
        )
        if chat_request.user is None or chat_request.user.strip() == "":
            logger.warning(
                "chat/completions: no stable user provided — each request will use a new session; "
                "frontend should send a persistent user (e.g. userId or localStorage clientId), not anonymous-${Date.now()}"
            )
        # 转换消息格式
        messages = [
            {
                "role": msg.role,
                "content": msg.content
            }
            for msg in chat_request.messages
        ]
        # 将 user_nickname 注入为 system 消息，使 Gateway/agent 能在上下文中看到并正确称呼用户
        # （OpenClaw 文档未定义 user_nickname 字段，仅透传 body 无法被 agent 理解）
        nickname = (chat_request.user_nickname or "").strip()
        if nickname:
            system_hint = {
                "role": "system",
                "content": f"当前对话用户的昵称是：{nickname}。请在回复中可自然使用该昵称称呼用户。"
            }
            messages = [system_hint] + messages

        # 流式响应
        if chat_request.stream:
            logger.info(f"Processing streaming chat request for model: {chat_request.model}")
            
            async def generate():
                try:
                    async for chunk in chat_service.chat_completion_stream(
                        messages=messages,
                        model=chat_request.model,
                        temperature=chat_request.temperature,
                        max_tokens=chat_request.max_tokens,
                        user=chat_request.user,
                        user_nickname=chat_request.user_nickname,
                    ):
                        yield chunk
                except Exception as e:
                    logger.error(f"Stream error: {str(e)}")
                    error_chunk = {
                        "error": {
                            "message": str(e),
                            "type": "server_error"
                        }
                    }
                    yield f"data: {error_chunk}\n\n"
            
            return StreamingResponse(
                generate(),
                media_type="text/event-stream",
                headers=get_cors_headers(request)
            )
        
        # 非流式响应
        else:
            logger.info(f"Processing chat request for model: {chat_request.model}")
            
            response = await chat_service.chat_completion(
                messages=messages,
                model=chat_request.model,
                temperature=chat_request.temperature,
                max_tokens=chat_request.max_tokens,
                user=chat_request.user,
                user_nickname=chat_request.user_nickname,
            )
            
            return JSONResponse(
                content=response,
                headers=get_cors_headers(request)
            )
    
    except ValueError as e:
        logger.error(f"Invalid request: {str(e)}")
        return JSONResponse(
            status_code=400,
            content={
                "error": {
                    "message": str(e),
                    "type": "invalid_request_error"
                }
            },
            headers=get_cors_headers(request)
        )
    
    except Exception as e:
        logger.error(f"Chat completion error: {str(e)}")
        return JSONResponse(
            status_code=500,
            content={
                "error": {
                    "message": str(e),
                    "type": "server_error"
                }
            },
            headers=get_cors_headers(request)
        )
