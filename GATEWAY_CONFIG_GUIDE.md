# OpenClaw Gateway 配置指南

## 快速开始

### 方法 1：使用配置向导（推荐）

```bash
./configure_gateway.sh
```

配置向导会交互式地询问你：
- Gateway 地址（默认：127.0.0.1）
- Gateway 端口（默认：18789）
- **Gateway Token**（必需！从 Gateway 获取）
- 默认 Agent ID（默认：main）
- Chat Router 端口（默认：8002）

### 方法 2：手动编辑配置文件

```bash
# 1. 复制模板
cp export_env_local.sh.template export_env_local.sh

# 2. 编辑配置
vim export_env_local.sh

# 3. 修改以下关键配置
export OPENCLAW_GATEWAY_TOKEN="your-actual-token"
```

### 方法 3：快速创建配置

```bash
cat > export_env_local.sh << 'EOF'
#!/bin/bash
# OpenClaw Gateway 配置
export OPENCLAW_GATEWAY_HOST="127.0.0.1"
export OPENCLAW_GATEWAY_PORT="18789"
export OPENCLAW_GATEWAY_TOKEN="your-actual-token"
export OPENCLAW_DEFAULT_AGENT="main"
export CHAT_ROUTER_PORT="8002"
EOF

chmod +x export_env_local.sh
```

## 配置说明

### 必需配置

| 变量 | 说明 | 默认值 | 示例 |
|------|------|--------|------|
| `OPENCLAW_GATEWAY_HOST` | Gateway 服务地址 | 127.0.0.1 | 127.0.0.1 或远程IP |
| `OPENCLAW_GATEWAY_PORT` | Gateway 服务端口 | 18789 | 18789 |
| `OPENCLAW_GATEWAY_TOKEN` | 认证 Token | *无* | sk-lm-xxx:yyy |
| `OPENCLAW_DEFAULT_AGENT` | 默认 Agent ID | main | main |
| `CHAT_ROUTER_PORT` | Chat Router 端口 | 8002 | 8002 |

### 获取 Gateway Token

Gateway Token 用于认证 Chat Router 到 Gateway 的连接。获取方式：

1. **从 OpenClaw Gateway 配置文件**：
   ```bash
   # 查看 Gateway 配置
   cat ~/.openclaw/openclaw.json
   # 或
   cat /path/to/gateway/config.json
   
   # 查找 auth.token 字段
   ```

2. **从 Gateway 管理界面**：
   - 登录 Gateway 管理后台
   - 导航到"认证设置"或"API 密钥"
   - 复制 Token

3. **从 Gateway 日志**：
   - 某些 Gateway 在启动时会在日志中显示 Token

## 配置检查

启动服务时，脚本会自动检查配置：

```bash
./start_aio_pod.sh
```

如果配置不完整，会显示：

```
⚠ Gateway Token: 使用默认值 (建议配置实际的 Token)

===== OpenClaw Gateway 配置提示 =====
Chat Router 需要连接到 OpenClaw Gateway 才能正常工作

请在 export_env_local.sh 中配置以下环境变量：
...

是否继续启动服务? (y/N):
```

## 验证配置

### 1. 检查环境变量

```bash
source export_env_local.sh
echo $OPENCLAW_GATEWAY_TOKEN
```

### 2. 测试 Gateway 连接

```bash
# 检查 Gateway 是否运行
curl http://localhost:18789/health

# 或使用诊断脚本
./diagnose_chat_router.sh
```

### 3. 启动并测试服务

```bash
# 启动服务
./start_aio_pod.sh

# 等待服务启动完成后测试
python3 test_chat_router.py
```

## 常见问题

### Q: 找不到 Gateway Token？

**A**: Gateway Token 通常在以下位置：
- `~/.openclaw/openclaw.json` - 配置文件中的 `gateway.auth.token`
- Gateway 启动日志
- Gateway 管理界面的 API 设置

如果找不到，请联系 Gateway 管理员或查看 Gateway 文档。

### Q: 启动时提示"Gateway disconnected"？

**A**: 可能的原因：
1. Gateway 没有运行
   ```bash
   # 检查 Gateway 进程
   lsof -i :18789
   ps aux | grep gateway
   ```

2. Token 配置错误
   ```bash
   # 检查配置
   source export_env_local.sh
   echo "Token: ${OPENCLAW_GATEWAY_TOKEN:0:15}..."
   ```

3. 网络问题（如果 Gateway 在远程服务器）
   ```bash
   # 测试连接
   telnet <gateway-host> 18789
   curl http://<gateway-host>:18789/health
   ```

### Q: 可以使用远程 Gateway 吗？

**A**: 可以！修改配置：

```bash
export OPENCLAW_GATEWAY_HOST="your-remote-server.com"
export OPENCLAW_GATEWAY_PORT="18789"
export OPENCLAW_GATEWAY_TOKEN="your-token"
```

确保：
- 远程服务器的防火墙允许连接
- Gateway 配置允许远程连接
- 网络延迟可接受（建议 < 100ms）

### Q: 如何更改配置？

**A**: 三种方式：

1. **重新运行配置向导**：
   ```bash
   ./configure_gateway.sh
   ```

2. **直接编辑配置文件**：
   ```bash
   vim export_env_local.sh
   ```

3. **临时覆盖（测试用）**：
   ```bash
   export OPENCLAW_GATEWAY_TOKEN="new-token"
   ./start_aio_pod.sh
   ```

## 安全建议

1. **保护 Token**：
   ```bash
   # 确保配置文件权限正确
   chmod 600 export_env_local.sh
   
   # 不要提交到 Git
   echo "export_env_local.sh" >> .gitignore
   ```

2. **定期轮换 Token**：
   - 建议每 3-6 个月更换一次 Token
   - Token 泄露后立即更换

3. **使用最小权限**：
   - 如果 Gateway 支持多种 Token，使用权限最小的
   - 考虑为不同环境（开发/生产）使用不同 Token

## 相关文件

- `export_env_local.sh.template` - 配置模板
- `configure_gateway.sh` - 配置向导
- `diagnose_chat_router.sh` - 诊断工具
- `start_aio_pod.sh` - 启动脚本
- `test_chat_router.py` - 测试脚本

## 更多帮助

如需更多帮助，请查看：
- `CHAT_ROUTER_DEPLOYMENT.md` - 完整部署指南
- `TROUBLESHOOTING.md` - 故障排查
- `COMPLETION_SUMMARY.md` - 项目总结
