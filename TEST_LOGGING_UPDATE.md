# 测试日志更新说明

## 修改内容

### 1. 日志输出到 `./log` 目录

`test_chat_router.py` 现在会将详细的测试日志保存到 `./log` 目录下。

**日志特性：**
- 日志文件名格式：`test_chat_router_YYYYMMDD_HHMMSS.log`
- 包含时间戳，便于追踪不同的测试执行
- 同时输出到控制台和文件
- 包含详细的 DEBUG 级别日志（HTTP 请求/响应、WebSocket 通信等）

**日志文件示例：**
```
./log/test_chat_router_20260207_154134.log
```

### 2. 增强的日志内容

测试脚本现在记录：

- **HTTP 请求详情**
  - 请求 URL、方法、headers
  - 请求 body（JSON 格式）
  
- **HTTP 响应详情**
  - 响应状态码
  - 响应 headers
  - 响应 body（完整 JSON）
  
- **测试流程**
  - 每个测试阶段的开始和结束
  - 成功/失败状态
  - 异常堆栈信息（如果有）

- **流式响应**
  - 每个数据块的接收时间
  - 数据块内容（前100字符）
  - 完成状态

### 3. 使用方法

**运行测试（非流式）：**
```bash
python3 test_chat_router.py
```

**运行测试（流式）：**
```bash
python3 test_chat_router.py --stream
```

**指定服务 URL：**
```bash
python3 test_chat_router.py --url http://remote-host:8002
```

**查看日志：**
```bash
# 查看最新的日志文件
ls -lt log/test_chat_router_*.log | head -1

# 查看日志内容
tail -f log/test_chat_router_20260207_154134.log
```

### 4. 日志级别

当前配置为 `DEBUG` 级别，包含最详细的信息。

如需调整日志级别，可以修改 `test_chat_router.py` 中的：

```python
logging.basicConfig(
    level=logging.DEBUG,  # 可改为 INFO, WARNING, ERROR
    ...
)
```

### 5. 目录结构

```
aio-pod/
├── log/                                    # 测试日志目录
│   ├── test_chat_router_20260207_154134.log
│   ├── test_chat_router_20260207_160230.log
│   └── ...
├── test_chat_router.py                     # 测试脚本
└── quick_start_chat_router.sh             # 快速启动脚本（已更新提示）
```

### 6. 日志清理

日志文件会自动累积，建议定期清理旧日志：

```bash
# 删除 7 天前的日志
find ./log -name "test_chat_router_*.log" -mtime +7 -delete

# 或者手动删除
rm -f ./log/test_chat_router_*.log
```

## 相关文件

- `test_chat_router.py` - 测试脚本（已更新）
- `quick_start_chat_router.sh` - 快速启动指南（已更新提示）

## 示例日志输出

```
2026-02-07 15:41:34,818 - __main__ - INFO - Chat Router Service Test Started
2026-02-07 15:41:34,818 - __main__ - INFO - Service URL: http://localhost:8002
2026-02-07 15:41:34,818 - __main__ - INFO - ==================================================
2026-02-07 15:41:34,818 - __main__ - INFO - 开始测试健康检查
2026-02-07 15:41:34,840 - __main__ - DEBUG - 发送请求: GET http://localhost:8002/health
2026-02-07 15:41:34,896 - httpx - INFO - HTTP Request: GET http://localhost:8002/health "HTTP/1.1 200 OK"
2026-02-07 15:41:34,897 - __main__ - INFO - 响应状态码: 200
2026-02-07 15:41:34,897 - __main__ - DEBUG - 响应内容: {"status":"healthy","gateway":"connected"}
2026-02-07 15:41:34,897 - __main__ - INFO - 健康检查结果: 成功
```

## 优势

1. **调试方便** - 详细的日志信息便于问题排查
2. **历史追溯** - 保留每次测试的完整记录
3. **并行输出** - 同时在控制台和文件中输出，兼顾实时查看和事后分析
4. **时间戳命名** - 避免日志文件被覆盖
5. **结构化日志** - 清晰的分隔符和格式，便于阅读

---

**更新时间：** 2026-02-07
