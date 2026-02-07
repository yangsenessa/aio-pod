# WebSocket 连接修复总结

## 更新时间
2026-02-07 16:08

## 问题诊断

### 原始错误
```
chat.send failed: {'type': 'res', 'id': 'connect-1770451559501', 'ok': False, 
'error': {'code': 'INVALID_REQUEST', 
'message': 'connect is only valid as the first request'}}
```

### 根本原因

根据 OpenClaw Gateway 的 Cursor 分析和原始测试脚本，发现了关键问题：

1. **错误的 Challenge 处理逻辑**
   - 旧代码：收到 `connect.challenge` 后，尝试发送第二个 `connect` 请求或发送 `type: "res"` 响应
   - 问题：Gateway 规定 **connect 只能作为第一个请求发送**，且不接受 `type: "res"` 格式的响应

2. **复杂化的认证流程**
   - 旧代码假设需要处理 challenge-response 机制
   - 实际情况：原始测试脚本显示，当 token 正确时，Gateway **直接返回成功响应**，不需要额外的 challenge 处理

## 修复方案

### 核心改进：简化连接逻辑

参考用户提供的原始 Node.js 测试脚本（`test-gateway-chat.mjs`），实现了更简单、更可靠的连接逻辑：

#### 修复前（错误的实现）
```python
# 发送 connect 请求
await ws.send(json.dumps(connect_request))

# 等待单个响应
response = await ws.recv()

# 如果是 challenge，尝试再次发送 connect 或发送响应帧
if response.get("event") == "connect.challenge":
    # ❌ 错误：再次发送 connect 请求（违反协议）
    await ws.send(json.dumps({
        "type": "req",
        "method": "connect",  # 违反 "connect 只能是第一个请求" 规则
        ...
    }))
```

#### 修复后（正确的实现）
```python
# 发送 connect 请求
connect_id = f"connect-{int(time.time() * 1000)}"
await ws.send(json.dumps(connect_request))

# ✅ 关键改进：循环接收消息，直到找到匹配 connect_id 的响应
max_attempts = 10
for attempt in range(max_attempts):
    response = await ws.recv()
    
    # 检查是否是 connect 请求的响应（id 匹配）
    if response.get("id") == connect_id and response.get("type") == "res":
        if response.get("ok"):
            return ws  # ✅ 连接成功
        else:
            # 连接失败，记录错误
            return None
    
    # 如果是其他消息（如 event），记录并继续等待
    if response.get("type") == "event":
        logger.info(f"Received event: {event_name} (waiting for connect response...)")
        continue  # ✅ 继续等待真正的 connect 响应
```

### 关键修复点

1. **正确的响应匹配**
   - 通过 `response.get("id") == connect_id` 匹配响应
   - 确保收到的是 **connect 请求的响应**（`type: "res"`），而不是事件

2. **处理中间事件**
   - Gateway 可能在返回 connect 响应前发送一些事件消息
   - 代码现在会**跳过这些事件**，继续等待实际的响应

3. **移除错误的 Challenge 处理**
   - 删除了尝试发送第二个 `connect` 请求的逻辑
   - 删除了尝试发送 `type: "res"` 响应帧的逻辑

## 测试结果

### ✅ 所有测试通过

#### 非流式测试
```bash
$ python3 test_chat_router.py
健康检查: ✓ 通过
模型列表: ✓ 通过
聊天完成: ✓ 通过
✓ 所有测试通过！
```

#### 流式测试
```bash
$ python3 test_chat_router.py --stream
健康检查: ✓ 通过
模型列表: ✓ 通过
聊天完成: ✓ 通过
✓ 所有测试通过！
```

## 代码对比

### 文件：`aio_server/app/services/chat_router_service.py`

#### 修改函数：`_connect_websocket()`

**修改前的行数：** 约 110 行  
**修改后的行数：** 约 75 行  
**代码简化：** 减少约 32% 的代码量

**核心逻辑变化：**

| 方面 | 修改前 | 修改后 |
|------|--------|--------|
| 连接方式 | 单次 recv，复杂的 challenge 处理 | 循环 recv，等待匹配的响应 |
| Challenge | 尝试响应 challenge（错误） | 忽略事件，等待实际响应 |
| 认证方式 | 多步骤认证流程 | 在初始 connect 中包含 token |
| 代码复杂度 | 高（处理多种情况） | 低（简单的循环等待） |

## 原始测试脚本参考

用户提供的 `test-gateway-chat.mjs` 脚本的关键部分：

```javascript
// 发送 connect 请求
ws.send(JSON.stringify({
  type: "req",
  id: connectId,
  method: "connect",
  params: {
    minProtocol: 3,
    maxProtocol: 3,
    client: { id: "webchat", version: "1.0.0", platform: "node", mode: "webchat" },
    role: "operator",
    scopes: ["operator.admin"],
    auth: token ? { token } : undefined,
  },
}));

// 等待匹配 connectId 的响应
const handler = (data) => {
  const msg = JSON.parse(data.toString());
  if (msg.id === connectId) {  // ✅ 关键：通过 ID 匹配
    ws.off("message", handler);
    resolve(msg);
  }
};
ws.on("message", handler);
```

**Python 实现遵循了相同的模式。**

## 经验教训

1. **不要过度设计**
   - 原始代码假设了复杂的 challenge-response 流程
   - 实际上 Gateway 的认证更简单：在 connect 中包含 token 即可

2. **参考官方示例**
   - 用户提供的测试脚本是最佳参考
   - 直接翻译其逻辑比猜测协议更可靠

3. **WebSocket 消息顺序**
   - Gateway 可能在响应前发送事件消息
   - 需要循环接收并匹配 ID，而不是假设第一个消息就是响应

4. **协议规则**
   - "connect 只能作为第一个请求" 是硬性规则
   - 任何尝试发送第二个 connect 都会失败

## 相关文件

- `aio_server/app/services/chat_router_service.py` - 修复的核心文件
- `test_chat_router.py` - 测试脚本
- `log/test_chat_router_*.log` - 测试日志

## 下一步

✅ WebSocket 连接问题已完全解决  
✅ 非流式和流式模式都正常工作  
✅ 可以开始生产部署

---

**修复者：** AI Assistant  
**参考：** 用户提供的 `test-gateway-chat.mjs` 原始测试脚本  
**验证：** 所有测试通过（非流式 + 流式）
