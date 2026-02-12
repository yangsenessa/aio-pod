import os
import json
import time
import asyncio
import logging
from typing import Dict, List, Optional, Any, AsyncIterator
import httpx
from datetime import datetime

logger = logging.getLogger(__name__)

class ChatRouterService:
    """OpenClaw Gateway 聊天路由服务"""
    
    def __init__(self):
        # 从环境变量读取配置
        self.gateway_host = os.getenv("OPENCLAW_GATEWAY_HOST", "127.0.0.1")
        self.gateway_port = int(os.getenv("OPENCLAW_GATEWAY_PORT", "18789"))
        self.gateway_token = os.getenv("OPENCLAW_GATEWAY_TOKEN", "")
        self.default_agent = os.getenv("OPENCLAW_DEFAULT_AGENT", "main")
        
        # 构建基础 URL
        self.base_url = f"http://{self.gateway_host}:{self.gateway_port}"
        
        # WebSocket 连接池（用于复用连接）
        self._ws_connections = {}
        
        logger.info(f"ChatRouterService initialized with gateway: {self.base_url}")
    
    async def check_gateway_health(self) -> bool:
        """检查 Gateway 健康状态"""
        try:
            # 使用 trust_env=False 禁用系统代理（访问本地服务）
            async with httpx.AsyncClient(trust_env=False) as client:
                response = await client.get(f"{self.base_url}/health", timeout=5.0)
                return response.status_code == 200
        except Exception as e:
            logger.error(f"Gateway health check failed: {str(e)}")
            return False
    
    async def _connect_websocket(self) -> Any:
        """建立 WebSocket 连接并进行认证（参考原始测试脚本）"""
        try:
            import websockets
            
            ws_url = f"ws://{self.gateway_host}:{self.gateway_port}"
            logger.info(f"Connecting to WebSocket: {ws_url}")
            ws = await websockets.connect(ws_url)
            
            # 发送 connect 请求（参考原始脚本的实现）
            connect_id = f"connect-{int(time.time() * 1000)}"
            connect_request = {
                "type": "req",
                "id": connect_id,
                "method": "connect",
                "params": {
                    "minProtocol": 3,
                    "maxProtocol": 3,
                    "client": {
                        "id": "webchat",
                        "version": "1.0.0",
                        "platform": "aio2030",
                        "mode": "webchat",
                    },
                    "role": "operator",
                    "scopes": ["operator.admin"],
                }
            }
            
            # 如果有 token，添加认证（参考原始脚本）
            if self.gateway_token:
                connect_request["params"]["auth"] = {"token": self.gateway_token}
            
            logger.debug(f"Sending connect request: {json.dumps(connect_request, indent=2)}")
            await ws.send(json.dumps(connect_request))
            
            # 等待 connect 响应（可能收到多个消息，需要找到匹配 connect_id 的响应）
            max_attempts = 10
            for attempt in range(max_attempts):
                try:
                    response_text = await asyncio.wait_for(ws.recv(), timeout=10.0)
                    response = json.loads(response_text)
                    logger.debug(f"Received message (attempt {attempt + 1}): {json.dumps(response, indent=2)}")
                    
                    # 检查是否是 connect 请求的响应（id 匹配）
                    if response.get("id") == connect_id and response.get("type") == "res":
                        if response.get("ok"):
                            logger.info("✓ WebSocket connect successful")
                            return ws
                        else:
                            error = response.get("error", {})
                            logger.error(f"✗ WebSocket connect failed: code={error.get('code')}, message={error.get('message')}")
                            await ws.close()
                            return None
                    
                    # 如果是其他消息（如 event），记录并继续等待
                    if response.get("type") == "event":
                        event_name = response.get("event")
                        logger.info(f"Received event: {event_name} (waiting for connect response...)")
                        # 继续循环，等待实际的 connect 响应
                        continue
                    
                except asyncio.TimeoutError:
                    logger.error("Timeout waiting for connect response")
                    await ws.close()
                    return None
            
            logger.error(f"Failed to receive connect response after {max_attempts} attempts")
            await ws.close()
            return None
            
        except Exception as e:
            logger.error(f"Failed to connect WebSocket: {str(e)}")
            import traceback
            logger.error(traceback.format_exc())
            return None
    
    async def chat_completion(
        self,
        messages: List[Dict[str, str]],
        model: str = "openclaw:main",
        stream: bool = False,
        temperature: Optional[float] = None,
        max_tokens: Optional[int] = None,
        **kwargs
    ) -> Dict[str, Any]:
        """
        OpenAI 兼容的聊天完成接口
        
        Args:
            messages: 消息列表
            model: 模型名称，格式为 "openclaw:{agent_id}"
            stream: 是否流式返回
            temperature: 温度参数（暂不使用）
            max_tokens: 最大token数（暂不使用）
            
        Returns:
            OpenAI 格式的响应
        """
        # 提取 agent_id
        agent_id = self.default_agent
        if model.startswith("openclaw:"):
            agent_id = model.split(":", 1)[1]
        
        # 获取最后一条用户消息
        user_message = None
        for msg in reversed(messages):
            if msg.get("role") == "user":
                user_message = msg.get("content")
                break
        
        if not user_message:
            raise ValueError("No user message found in messages")
        
        # 通过 WebSocket 发送消息
        ws = await self._connect_websocket()
        if not ws:
            raise Exception("Failed to connect to Gateway")
        
        try:
            # 构建 sessionKey
            session_key = f"agent:{agent_id}:main"
            
            # 发送 chat.send 请求
            request_id = f"chat-{int(time.time() * 1000)}"
            chat_request = {
                "type": "req",
                "id": request_id,
                "method": "chat.send",
                "params": {
                    "sessionKey": session_key,
                    "message": user_message,
                    "idempotencyKey": request_id,
                }
            }
            
            await ws.send(json.dumps(chat_request))
            
            # 等待 chat.send 响应
            response_text = await asyncio.wait_for(ws.recv(), timeout=10.0)
            response = json.loads(response_text)
            
            if not response.get("ok"):
                await ws.close()
                raise Exception(f"chat.send failed: {response}")
            
            run_id = response.get("payload", {}).get("runId")
            if not run_id:
                await ws.close()
                raise Exception("No runId in response")
            
            # 等待 AI 回复
            accumulated_text = ""
            is_complete = False
            
            # 设置超时
            timeout = 60.0
            start_time = time.time()
            
            while not is_complete and (time.time() - start_time) < timeout:
                try:
                    message_text = await asyncio.wait_for(ws.recv(), timeout=5.0)
                    message = json.loads(message_text)
                    
                    # 检查是否是 chat 事件
                    if message.get("type") == "event" and message.get("event") == "chat":
                        payload = message.get("payload", {})
                        
                        # 检查是否是当前 runId 的事件
                        if payload.get("runId") == run_id:
                            state = payload.get("state")
                            
                            if state == "delta":
                                # 增量更新
                                text = payload.get("message", {}).get("content", [{}])[0].get("text", "")
                                if text:
                                    accumulated_text = text
                            
                            elif state == "final":
                                # 最终回复
                                is_complete = True
                                text = payload.get("message", {}).get("content", [{}])[0].get("text", "")
                                if text:
                                    accumulated_text = text
                                break
                            
                            elif state == "error":
                                # 错误
                                error_msg = payload.get("errorMessage", "Unknown error")
                                await ws.close()
                                raise Exception(f"Chat error: {error_msg}")
                
                except asyncio.TimeoutError:
                    # 继续等待
                    continue
            
            await ws.close()
            
            if not is_complete:
                raise Exception("Chat response timeout")
            
            # 构建 OpenAI 格式的响应
            response_id = f"chatcmpl-{int(time.time() * 1000)}"
            
            return {
                "id": response_id,
                "object": "chat.completion",
                "created": int(time.time()),
                "model": model,
                "choices": [
                    {
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": accumulated_text,
                        },
                        "finish_reason": "stop",
                    }
                ],
                "usage": {
                    "prompt_tokens": 0,
                    "completion_tokens": 0,
                    "total_tokens": 0,
                }
            }
        
        except Exception as e:
            try:
                await ws.close()
            except:
                pass
            raise e
    
    async def chat_completion_stream(
        self,
        messages: List[Dict[str, str]],
        model: str = "openclaw:main",
        **kwargs
    ) -> AsyncIterator[str]:
        """
        OpenAI 兼容的流式聊天完成接口
        
        Args:
            messages: 消息列表
            model: 模型名称
            
        Yields:
            SSE 格式的流式响应
        """
        # 提取 agent_id
        agent_id = self.default_agent
        if model.startswith("openclaw:"):
            agent_id = model.split(":", 1)[1]
        
        # 获取最后一条用户消息
        user_message = None
        for msg in reversed(messages):
            if msg.get("role") == "user":
                user_message = msg.get("content")
                break
        
        if not user_message:
            raise ValueError("No user message found in messages")
        
        # 通过 WebSocket 发送消息
        ws = await self._connect_websocket()
        if not ws:
            raise Exception("Failed to connect to Gateway")
        
        try:
            # 构建 sessionKey
            session_key = f"agent:{agent_id}:main"
            
            # 发送 chat.send 请求
            request_id = f"chat-{int(time.time() * 1000)}"
            chat_request = {
                "type": "req",
                "id": request_id,
                "method": "chat.send",
                "params": {
                    "sessionKey": session_key,
                    "message": user_message,
                    "idempotencyKey": request_id,
                }
            }
            
            await ws.send(json.dumps(chat_request))
            
            # 等待 chat.send 响应
            response_text = await asyncio.wait_for(ws.recv(), timeout=10.0)
            response = json.loads(response_text)
            
            if not response.get("ok"):
                await ws.close()
                raise Exception(f"chat.send failed: {response}")
            
            run_id = response.get("payload", {}).get("runId")
            if not run_id:
                await ws.close()
                raise Exception("No runId in response")
            
            # 流式输出 AI 回复
            is_complete = False
            last_text = ""
            response_id = f"chatcmpl-{int(time.time() * 1000)}"
            
            # 设置超时
            timeout = 60.0
            start_time = time.time()
            
            while not is_complete and (time.time() - start_time) < timeout:
                try:
                    message_text = await asyncio.wait_for(ws.recv(), timeout=5.0)
                    message = json.loads(message_text)
                    
                    # 检查是否是 chat 事件
                    if message.get("type") == "event" and message.get("event") == "chat":
                        payload = message.get("payload", {})
                        
                        # 检查是否是当前 runId 的事件
                        if payload.get("runId") == run_id:
                            state = payload.get("state")
                            
                            if state == "delta":
                                # 增量更新
                                text = payload.get("message", {}).get("content", [{}])[0].get("text", "")
                                if text and text != last_text:
                                    # 计算新增的文本
                                    delta = text[len(last_text):]
                                    last_text = text
                                    
                                    # 构建流式响应
                                    chunk = {
                                        "id": response_id,
                                        "object": "chat.completion.chunk",
                                        "created": int(time.time()),
                                        "model": model,
                                        "choices": [
                                            {
                                                "index": 0,
                                                "delta": {
                                                    "content": delta,
                                                },
                                                "finish_reason": None,
                                            }
                                        ],
                                    }
                                    yield f"data: {json.dumps(chunk)}\n\n"
                            
                            elif state == "final":
                                # 最终回复
                                is_complete = True
                                
                                # 发送最终 chunk
                                chunk = {
                                    "id": response_id,
                                    "object": "chat.completion.chunk",
                                    "created": int(time.time()),
                                    "model": model,
                                    "choices": [
                                        {
                                            "index": 0,
                                            "delta": {},
                                            "finish_reason": "stop",
                                        }
                                    ],
                                }
                                yield f"data: {json.dumps(chunk)}\n\n"
                                yield "data: [DONE]\n\n"
                                break
                            
                            elif state == "error":
                                # 错误
                                error_msg = payload.get("errorMessage", "Unknown error")
                                await ws.close()
                                raise Exception(f"Chat error: {error_msg}")
                
                except asyncio.TimeoutError:
                    # 继续等待
                    continue
            
            await ws.close()
            
            if not is_complete:
                raise Exception("Chat response timeout")
        
        except Exception as e:
            try:
                await ws.close()
            except:
                pass
            raise e
