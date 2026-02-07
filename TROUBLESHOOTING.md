# 修复说明

## 问题：测试脚本遇到代理配置问题

在运行 `test_chat_router.py` 时遇到了 SOCKS 代理配置问题。

## 解决方案

已更新 `test_chat_router.py`，在所有 `httpx.AsyncClient` 调用中添加了 `trust_env=False` 参数，这样可以忽略系统的代理设置，直接访问本地服务。

## 修改内容

```python
# 之前
async with httpx.AsyncClient(timeout=10.0) as client:

# 修改后
async with httpx.AsyncClient(timeout=10.0, trust_env=False) as client:
```

## 当前状态

测试脚本已修复，但 Chat Router 服务尚未启动。这是正常的，需要按照以下步骤启动服务。

## 启动服务步骤

1. **配置环境变量**（如果还没有配置）：
   ```bash
   # 编辑 export_env_local.sh 文件，确保包含以下配置：
   export OPENCLAW_GATEWAY_HOST="127.0.0.1"
   export OPENCLAW_GATEWAY_PORT="18789"
   export OPENCLAW_GATEWAY_TOKEN="sk-lm-gyXsWZIS:opqYGydrY8dwynxrZNT6"
   export OPENCLAW_DEFAULT_AGENT="main"
   ```

2. **确保 OpenClaw Gateway 正在运行**：
   ```bash
   # Chat Router 依赖 Gateway，请先确保 Gateway 在运行
   lsof -i :18789
   ```

3. **启动所有 AIO-Pod 服务**：
   ```bash
   ./start_aio_pod.sh
   ```

4. **验证服务状态**：
   ```bash
   # 检查 Chat Router 是否运行
   lsof -i :8002
   
   # 检查健康状态
   curl http://localhost:8002/health
   ```

5. **运行测试**：
   ```bash
   python3 test_chat_router.py
   ```

## 测试说明

测试脚本会检查：
- ✓ 健康检查端点
- ✓ 模型列表端点
- ✓ 聊天完成接口（非流式）

如果需要测试流式响应：
```bash
python3 test_chat_router.py --stream
```

## 注意事项

1. **代理设置**：如果你的系统配置了代理（如 SOCKS5），测试脚本已经配置为忽略代理设置访问本地服务
2. **依赖服务**：Chat Router 必须在 OpenClaw Gateway 启动后才能正常工作
3. **端口冲突**：确保 8002 端口没有被其他服务占用

## 故障排查

如果测试失败，请检查：

1. **服务是否运行**：
   ```bash
   ps aux | grep chat_router
   lsof -i :8002
   ```

2. **查看日志**：
   ```bash
   tail -f aio_server/chat_router.log
   ```

3. **检查 Gateway 连接**：
   ```bash
   curl http://localhost:18789/health
   ```

4. **手动测试端点**：
   ```bash
   # 健康检查
   curl http://localhost:8002/health
   
   # 模型列表
   curl http://localhost:8002/v1/models
   
   # 聊天测试
   curl -X POST http://localhost:8002/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model":"openclaw:main","messages":[{"role":"user","content":"你好"}]}'
   ```
