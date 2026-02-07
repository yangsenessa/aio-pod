# OpenAI-Compatible Chat Router 部署指南

本文档描述了如何部署和配置 OpenAI 兼容的 Chat Router 服务。

## 架构概述

```
客户端 (OpenAI SDK)
    ↓
Nginx (webchat.aio2030.fun:443)
    ↓
Chat Router Server (localhost:8002)
    ↓
OpenClaw Gateway (localhost:18789)
    ↓
Agent (AI 服务)
```

## 组件说明

### 1. Chat Router Server (端口 8002)

提供 OpenAI 兼容的 API 接口，包括：
- `/v1/chat/completions` - 聊天完成接口（支持流式和非流式）
- `/v1/models` - 模型列表
- `/health` - 健康检查

### 2. OpenClaw Gateway (端口 18789)

底层的 WebSocket 网关，负责与 AI Agent 通信。

### 3. Nginx (端口 443)

提供 HTTPS 访问，域名：`webchat.aio2030.fun`

## 部署步骤

### 第一步：环境配置

在 `export_env_local.sh` 中添加以下配置：

```bash
# OpenClaw Gateway 配置
export OPENCLAW_GATEWAY_HOST="127.0.0.1"
export OPENCLAW_GATEWAY_PORT="18789"
export OPENCLAW_GATEWAY_TOKEN="your-gateway-token"
export OPENCLAW_DEFAULT_AGENT="main"

# Chat Router 服务配置
export CHAT_ROUTER_HOST="0.0.0.0"
export CHAT_ROUTER_PORT="8002"
```

### 第二步：生成 Nginx 配置

运行配置生成脚本：

```bash
python3 generate_nginx_config.py
```

这将生成 `nginx_webchat.conf` 文件。

### 第三步：部署 Nginx 配置

```bash
# 1. 复制配置文件
sudo cp nginx_webchat.conf /etc/nginx/sites-available/webchat.aio2030.fun.conf

# 2. 创建符号链接
sudo ln -s /etc/nginx/sites-available/webchat.aio2030.fun.conf /etc/nginx/sites-enabled/

# 3. 测试配置
sudo nginx -t

# 4. 重新加载 Nginx
sudo systemctl reload nginx
```

### 第四步：申请 SSL 证书（如果还没有）

```bash
sudo certbot --nginx -d webchat.aio2030.fun
```

### 第五步：启动服务

```bash
# 启动所有服务（包括 Chat Router）
./start_aio_pod.sh

# 或者单独启动 Chat Router
cd aio_server
python3 chat_router_server.py
```

### 第六步：验证服务

```bash
# 测试本地服务
python3 test_chat_router.py

# 测试 HTTPS 访问
curl https://webchat.aio2030.fun/health

# 测试聊天 API
curl -X POST https://webchat.aio2030.fun/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openclaw:main",
    "messages": [
      {"role": "user", "content": "你好"}
    ]
  }'
```

## 使用示例

### Python (OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://webchat.aio2030.fun/v1",
    api_key="dummy"  # Chat Router 不需要 API key
)

response = client.chat.completions.create(
    model="openclaw:main",
    messages=[
        {"role": "user", "content": "你好，请介绍一下你自己"}
    ]
)

print(response.choices[0].message.content)
```

### 流式响应

```python
stream = client.chat.completions.create(
    model="openclaw:main",
    messages=[
        {"role": "user", "content": "讲个故事"}
    ],
    stream=True
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
```

### cURL

```bash
# 非流式
curl -X POST https://webchat.aio2030.fun/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openclaw:main",
    "messages": [{"role": "user", "content": "你好"}]
  }'

# 流式
curl -X POST https://webchat.aio2030.fun/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openclaw:main",
    "messages": [{"role": "user", "content": "你好"}],
    "stream": true
  }'
```

## 服务管理

### 启动服务

```bash
./start_aio_pod.sh
```

### 停止服务

```bash
./stop_aio_pod.sh
```

### 查看日志

```bash
# Chat Router 日志
tail -f aio_server/chat_router.log

# Nginx 日志
sudo tail -f /var/log/nginx/webchat.aio2030.fun_access.log
sudo tail -f /var/log/nginx/webchat.aio2030.fun_error.log
```

### 检查服务状态

```bash
# 检查进程
ps aux | grep chat_router

# 检查端口
lsof -i :8002

# 健康检查
curl http://localhost:8002/health
curl https://webchat.aio2030.fun/health
```

## 故障排查

### 问题 1：Chat Router 无法连接到 Gateway

**症状**：健康检查返回 `"gateway": "disconnected"`

**解决方案**：
1. 检查 Gateway 是否运行：`lsof -i :18789`
2. 检查环境变量配置
3. 检查 Gateway token 是否正确

### 问题 2：SSL 证书错误

**症状**：HTTPS 访问返回证书错误

**解决方案**：
1. 确认证书路径正确：`ls -la /etc/letsencrypt/live/webchat.aio2030.fun/`
2. 重新生成证书：`sudo certbot --nginx -d webchat.aio2030.fun`
3. 重新加载 Nginx：`sudo systemctl reload nginx`

### 问题 3：流式响应不工作

**症状**：流式请求返回完整响应而不是逐步返回

**解决方案**：
1. 检查 Nginx 配置中的 `proxy_buffering off`
2. 确认客户端正确处理 SSE (Server-Sent Events)

## Skills 框架使用

### 生成自定义 Nginx 配置

```python
from skills.nginx.nginx_config_skill import NginxConfigSkill

skill = NginxConfigSkill()

# 生成配置
config = skill.generate_config(
    domain="your-domain.com",
    service_type="chat_router",
    backend_port=8002,
    enable_ssl=True
)

print(config)
```

### 命令行使用

```bash
python -m skills.nginx.nginx_config_skill \
    --domain your-domain.com \
    --service-type chat_router \
    --backend-port 8002 \
    --enable-ssl \
    --output /tmp/nginx.conf
```

## 安全建议

1. **限制访问来源**：在 Nginx 配置中添加 IP 白名单
2. **启用 HTTPS**：始终使用 SSL/TLS 加密
3. **API 认证**：考虑添加 API key 验证
4. **速率限制**：使用 Nginx 的 `limit_req` 模块
5. **日志审计**：定期检查访问日志

## 性能优化

1. **连接池**：WebSocket 连接复用
2. **缓存**：对模型列表等静态内容启用缓存
3. **超时设置**：根据实际情况调整超时时间
4. **并发控制**：使用 Nginx 的 worker 进程配置

## 相关文件

- `aio_server/chat_router_server.py` - Chat Router 服务主程序
- `aio_server/app/api/chat_router.py` - API 路由定义
- `aio_server/app/services/chat_router_service.py` - 业务逻辑
- `skills/nginx/nginx_config_skill.py` - Nginx 配置生成器
- `generate_nginx_config.py` - 配置生成脚本
- `test_chat_router.py` - 测试脚本
- `start_aio_pod.sh` - 启动脚本
- `stop_aio_pod.sh` - 停止脚本

## 技术支持

如有问题，请查看日志文件或联系技术支持。
