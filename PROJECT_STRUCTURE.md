# 项目文件结构说明

## Chat Router 相关文件

### 核心服务文件

```
aio_server/
├── chat_router_server.py              # Chat Router 主服务程序
├── app/
│   ├── api/
│   │   └── chat_router.py             # OpenAI 兼容 API 路由
│   └── services/
│       └── chat_router_service.py     # Chat Router 业务逻辑
└── requirements.txt                   # Python 依赖（已更新）
```

### Skills 框架

```
skills/
├── __init__.py                        # 框架入口
├── base_skill.py                      # 技能基类
├── skill_manager.py                   # 技能管理器
├── requirements.txt                   # Skills 框架依赖
├── nginx/                             # Nginx 相关技能
│   ├── __init__.py
│   ├── nginx_config_skill.py          # Nginx 配置生成技能
│   └── templates/                     # Nginx 配置模板
│       ├── http.conf.j2               # HTTP 配置模板
│       ├── https.conf.j2              # HTTPS 配置模板
│       └── chat_router.conf.j2        # Chat Router 专用模板
└── README.md                          # Skills 框架文档
```

### 启动和管理脚本

```
start_aio_pod.sh                       # 启动脚本（已更新，支持 Chat Router）
stop_aio_pod.sh                        # 停止脚本（已更新，支持 Chat Router）
```

### 配置和测试工具

```
generate_nginx_config.py               # Nginx 配置生成工具
test_chat_router.py                    # Chat Router 测试脚本
quick_start_chat_router.sh             # 快速启动脚本
nginx_webchat.conf                     # 生成的 Nginx 配置（运行后生成）
```

### 文档

```
CHAT_ROUTER_DEPLOYMENT.md              # Chat Router 部署指南
skills/README.md                       # Skills 框架使用说明
```

## 文件说明

### 1. chat_router_server.py

独立的 FastAPI 应用，提供 OpenAI 兼容的 API 接口。

**关键特性**：
- 完整的 CORS 支持
- 健康检查端点
- 启动/关闭事件处理
- 环境变量配置

### 2. chat_router.py

API 路由定义，包含所有端点的实现。

**端点**：
- `GET /health` - 健康检查
- `GET /v1/models` - 列出可用模型
- `POST /v1/chat/completions` - 聊天完成（支持流式）
- `OPTIONS /{path:path}` - CORS 预检请求

### 3. chat_router_service.py

业务逻辑层，负责与 OpenClaw Gateway 通信。

**功能**：
- WebSocket 连接管理
- 认证处理
- 消息收发
- 流式响应处理
- 错误处理

### 4. nginx_config_skill.py

Nginx 配置生成技能，基于 Jinja2 模板。

**功能**：
- 支持 HTTP/HTTPS 配置
- 支持多种服务类型
- 自定义超时和缓冲设置
- 命令行工具

### 5. 配置模板

**chat_router.conf.j2**：
- 专为 Chat Router 优化
- 支持流式响应（SSE）
- 禁用缓冲以实现实时传输
- 长超时支持（300秒）
- 完整的 CORS 配置

### 6. 启动脚本更新

**start_aio_pod.sh**：
- 新增 `CHAT_ROUTER_PORT=8002` 配置
- 新增 `start_chat_router()` 函数
- 新增 Chat Router 健康检查
- 新增 OpenClaw Gateway 环境变量

**stop_aio_pod.sh**：
- 新增 Chat Router 停止逻辑
- 新增日志归档支持

## 端口分配

- **8000**: Exec Server (MCP 执行服务)
- **8001**: File Server (文件上传下载服务)
- **8002**: Chat Router (OpenAI 兼容 API)
- **18789**: OpenClaw Gateway (WebSocket)

## Nginx 配置

### 域名映射

- `mcp.aio2030.fun` → File Server (8001) + Exec Server (8000)
- `webchat.aio2030.fun` → Chat Router (8002)

### 配置文件位置

生成的配置文件应放置在：
- `/etc/nginx/sites-available/webchat.aio2030.fun.conf`
- 符号链接：`/etc/nginx/sites-enabled/webchat.aio2030.fun.conf`

## 日志文件

### 应用日志

- `aio_server/file_server.log` - File Server 日志
- `aio_server/exec_server.log` - Exec Server 日志
- `aio_server/chat_router.log` - Chat Router 日志

### Nginx 日志

- `/var/log/nginx/webchat.aio2030.fun_access.log` - 访问日志
- `/var/log/nginx/webchat.aio2030.fun_error.log` - 错误日志

## 环境变量

需要在 `export_env_local.sh` 中配置：

```bash
# OpenClaw Gateway 配置
OPENCLAW_GATEWAY_HOST="127.0.0.1"
OPENCLAW_GATEWAY_PORT="18789"
OPENCLAW_GATEWAY_TOKEN="your-token"
OPENCLAW_DEFAULT_AGENT="main"

# Chat Router 配置
CHAT_ROUTER_HOST="0.0.0.0"
CHAT_ROUTER_PORT="8002"
```

## 依赖关系

```
Chat Router (8002)
    ↓ WebSocket
OpenClaw Gateway (18789)
    ↓
AI Agent
```

Chat Router 依赖于 OpenClaw Gateway 的运行。确保 Gateway 在启动 Chat Router 之前已经运行。

## 工作流程

1. 用户请求 → Nginx (webchat.aio2030.fun:443)
2. Nginx → Chat Router (localhost:8002)
3. Chat Router → OpenClaw Gateway (localhost:18789) via WebSocket
4. Gateway → AI Agent
5. AI Agent → Gateway → Chat Router → Nginx → 用户

## 扩展性

### 添加新技能

1. 在 `skills/` 下创建新目录
2. 继承 `BaseSkill` 类
3. 实现 `execute()` 方法
4. 在 `skill_manager.py` 中注册

### 添加新的 API 端点

1. 在 `chat_router.py` 中添加路由
2. 在 `chat_router_service.py` 中添加业务逻辑
3. 更新文档

## 安全注意事项

1. **Token 管理**：不要在代码中硬编码 token
2. **HTTPS**：生产环境必须使用 HTTPS
3. **访问控制**：考虑添加 API 认证
4. **速率限制**：使用 Nginx 限制请求频率
5. **日志审计**：定期检查访问日志

## 监控建议

1. **健康检查**：使用 `/health` 端点监控服务状态
2. **日志监控**：使用 ELK 或类似工具聚合日志
3. **性能监控**：监控响应时间和错误率
4. **资源监控**：监控 CPU、内存、网络使用情况
