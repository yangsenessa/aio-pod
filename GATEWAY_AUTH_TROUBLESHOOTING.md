# OpenClaw Gateway 认证问题排查

## 当前状态

✅ **基础功能正常**：
- Chat Router 服务启动正常
- 健康检查通过
- 模型列表正常

⚠️ **WebSocket 认证失败**：
- 错误：`NOT_PAIRED, message=device identity required`
- 原因：Gateway 需要设备配对/身份验证

## 问题分析

OpenClaw Gateway 使用了两步认证流程：

1. **Connect Challenge**：
   - Gateway 返回 `connect.challenge` 事件
   - 包含 `nonce` 用于签名

2. **Device Identity Required**：
   - Gateway 需要设备配对
   - 需要 `deviceId` 或完成配对流程

## 解决方案

### 方案 1：获取设备 ID（推荐）

从你的 OpenClaw Gateway 配置中获取设备 ID：

```bash
# 查看 Gateway 配置
cat ~/.openclaw/openclaw.json

# 或查看已配对设备列表
# 通常在 Gateway 管理界面的"设备管理"中
```

然后在 `export_env_local.sh` 中添加：

```bash
export OPENCLAW_DEVICE_ID="your-device-id"
```

### 方案 2：使用不需要配对的 Token

某些 Gateway 配置允许使用特殊的 Token 绕过设备配对：

```bash
# 向 Gateway 管理员请求不需要配对的 Token
export OPENCLAW_GATEWAY_TOKEN="sk-admin-xxxxx"
```

### 方案 3：完成设备配对流程

通过 Gateway 的配对 API 完成配对：

```bash
# 示例：使用 Gateway 的 pair API
curl -X POST http://localhost:18789/api/pair \
  -H "Content-Type: application/json" \
  -d '{
    "deviceName": "Chat Router",
    "deviceType": "service",
    "token": "your-token"
  }'
```

### 方案 4：修改 Gateway 配置

如果你有 Gateway 的管理权限，可以修改配置关闭设备配对要求：

```json
{
  "gateway": {
    "auth": {
      "requireDevicePairing": false
    }
  }
}
```

## 临时测试方案

在开发/测试阶段，如果你只需要测试 API 接口（不需要实际与 Gateway 通信），可以：

### 1. 测试基础功能

```bash
# 测试健康检查
curl http://localhost:8002/health

# 测试模型列表
curl http://localhost:8002/v1/models
```

这些功能不需要 WebSocket 连接，可以正常工作。

### 2. 使用模拟模式

创建一个模拟的 Gateway 响应（用于开发测试）：

```python
# 在 chat_router_service.py 中添加一个模拟模式
if os.getenv("CHAT_ROUTER_MOCK_MODE") == "true":
    return {"role": "assistant", "content": "这是模拟响应"}
```

## 当前代码已实现的功能

✅ 处理 `connect.challenge` 事件
✅ 计算签名（SHA256）
✅ 错误日志详细信息
✅ 优雅的错误处理

❌ 尚未实现设备配对流程

## 下一步

请选择以上方案之一，推荐顺序：

1. **首选**：从 Gateway 获取设备 ID 或不需要配对的 Token
2. **次选**：联系 Gateway 管理员关闭配对要求
3. **开发**：使用模拟模式进行接口开发

## 相关日志

查看详细错误信息：

```bash
tail -f aio_server/chat_router.log
```

关键日志：
- `Received connect.challenge event` - 收到挑战
- `Sending challenge response with signature` - 发送签名响应
- `WebSocket connect failed: code=NOT_PAIRED` - 配对失败

## 联系支持

如需帮助，请提供：
1. Gateway 版本和配置
2. 完整的错误日志
3. 你的使用场景（开发/生产）
