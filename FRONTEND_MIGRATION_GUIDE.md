# 前端迁移指南 - AIO-Pod HTTPS 配置

## 🚀 快速开始

### 1. 环境变量更新

找到您的前端项目中的环境变量文件，将以下配置更新：

#### 修改前
```bash
# .env 或 .env.production
VITE_AIO_MCP_API_URL='https://8.141.81.75:8000/api/v1/rpc/'
```

#### 修改后
```bash
# .env 或 .env.production
VITE_AIO_MCP_API_URL='https://mcp.aio2030.fun/api/v1/rpc/'
VITE_AIO_FILE_API_URL='https://mcp.aio2030.fun/api/v1/'
VITE_AIO_UPLOAD_URL='https://mcp.aio2030.fun/upload/'
VITE_AIO_HEALTH_URL='https://mcp.aio2030.fun/health'
VITE_AIO_DOWNLOAD_URL='https://mcp.aio2030.fun/api/v1/'
```

### 2. API 调用代码更新

#### 文件上传 (原始路径)
```javascript
// 修改前
const uploadUrl = 'https://8.141.81.75:8001/upload/mcp';

// 修改后
const uploadUrl = 'https://mcp.aio2030.fun/upload/mcp';
```

#### RPC 调用
```javascript
// 修改前
const rpcUrl = 'https://8.141.81.75:8000/api/v1/rpc/mcp/';

// 修改后
const rpcUrl = 'https://mcp.aio2030.fun/api/v1/rpc/mcp/';
```

#### MCP 执行
```javascript
// 修改前
const mcpUrl = 'https://8.141.81.75:8000/api/v1/rpc/mcp/';

// 修改后
const mcpUrl = 'https://mcp.aio2030.fun/api/v1/rpc/mcp/';
```

### 3. 需要检查的文件

#### 环境变量文件
- [ ] `.env`
- [ ] `.env.production`
- [ ] `.env.development`
- [ ] `.env.local`

#### API 配置文件
- [ ] `src/api/config.js`
- [ ] `src/config/constants.js`
- [ ] `src/utils/api.js`
- [ ] `src/services/api.js`

#### 服务调用文件
- [ ] `src/services/uploadService.js`
- [ ] `src/services/mcpService.js`
- [ ] `src/services/rpcService.js`
- [ ] `src/api/endpoints.js`

#### 配置文件
- [ ] `vite.config.js`
- [ ] `webpack.config.js`
- [ ] `package.json` (如果有相关配置)

## 🧪 测试验证

### 1. 健康检查测试
```bash
curl -k https://mcp.aio2030.fun/health
```
预期响应: `{"status":"healthy"}`

### 2. 文件上传测试 (原始路径)
```bash
curl -k -X POST -F "file=@test.txt" https://mcp.aio2030.fun/upload/mcp
```

### 3. RPC 调用测试
```bash
curl -k -X POST https://mcp.aio2030.fun/api/v1/rpc/mcp/test.bin \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"test","params":{},"id":1}'
```

### 4. 前端测试步骤
1. 启动前端开发服务器
2. 打开浏览器开发者工具
3. 测试文件上传功能
4. 测试 MCP 执行功能
5. 检查网络请求是否使用新域名
6. 验证 HTTPS 连接正常

## 🔍 常见问题排查

### 1. CORS 错误
如果遇到 CORS 错误，检查：
- 请求是否使用 HTTPS
- 域名是否正确
- 请求头是否包含正确的 Content-Type

### 2. SSL 证书错误
如果遇到 SSL 证书错误：
- 在开发环境中可以忽略证书验证
- 生产环境中证书应该自动信任

### 3. 网络连接问题
如果无法连接到新域名：
- 检查域名解析: `nslookup mcp.aio2030.fun`
- 检查防火墙设置
- 验证服务器状态

## 📋 迁移检查清单

### 环境变量更新
- [ ] 更新 `VITE_AIO_MCP_API_URL`
- [ ] 更新 `VITE_AIO_FILE_API_URL` (如果有)
- [ ] 更新 `VITE_AIO_UPLOAD_URL` (如果有)
- [ ] 更新 `VITE_AIO_HEALTH_URL` (如果有)

### 代码更新
- [ ] 更新所有硬编码的 API 地址
- [ ] 更新配置文件中的服务器地址
- [ ] 更新测试文件中的地址
- [ ] 更新文档中的地址

### 测试验证
- [ ] 本地开发环境测试
- [ ] 生产环境测试
- [ ] 文件上传功能测试
- [ ] MCP 执行功能测试
- [ ] 错误处理测试

### 部署验证
- [ ] 构建生产版本
- [ ] 部署到生产环境
- [ ] 验证所有功能正常
- [ ] 监控错误日志

## 🎯 新 API 端点总结

| 功能 | 新地址 | 方法 | 说明 |
|------|--------|------|------|
| 健康检查 | `https://mcp.aio2030.fun/health` | GET | 服务状态检查 |
| 文件上传 | `https://mcp.aio2030.fun/upload/{type}` | POST | 上传文件到指定类型 (原始路径) |
| 文件下载 | `https://mcp.aio2030.fun/api/v1/?type={type}&filename={filename}` | GET | 下载指定文件 |
| MCP 执行 | `https://mcp.aio2030.fun/api/v1/rpc/{file_type}/{filename}` | POST | 执行 MCP 文件 (RPC) |
| RPC 服务 | `https://mcp.aio2030.fun/api/v1/rpc/{file_type}/{filename}` | POST | RPC 调用 |

## 🚨 重要提醒

1. **HTTPS 强制**: 所有 HTTP 请求会自动重定向到 HTTPS
2. **证书自动续期**: SSL 证书会自动续期，无需手动干预
3. **安全头部**: 已配置安全头部防止常见攻击
4. **速率限制**: API 端点有速率限制保护
5. **大文件支持**: 支持最大 100MB 文件上传

## 📞 技术支持

如果遇到问题，请检查：
1. 网络连接: `curl -k https://mcp.aio2030.fun/health`
2. SSL 证书: `openssl s_client -connect mcp.aio2030.fun:443`
3. 域名解析: `nslookup mcp.aio2030.fun`
4. 服务器状态: 联系系统管理员

---

**✅ 完成迁移后，您的应用将通过安全的 HTTPS 连接访问 AIO-Pod 服务！** 