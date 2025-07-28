# AIO-Pod Nginx SSL 配置完成

## 概述

我已经为您的AIO-Pod服务创建了完整的nginx反向代理和SSL证书配置，支持域名 `mcp.aio2030.fun`。

## 创建的文件

### 配置文件
- `nginx.conf` - nginx主配置文件，包含反向代理和SSL设置
- `aio-pod.service` - systemd服务文件，用于自动启动AIO-Pod服务

### 脚本文件
- `setup_nginx_ssl.sh` - nginx安装和SSL证书配置脚本
- `start_aio_pod.sh` - AIO-Pod服务启动脚本
- `stop_aio_pod.sh` - AIO-Pod服务停止脚本
- `deploy.sh` - 完整部署脚本
- `test_https.sh` - HTTPS配置测试脚本

### 文档
- `NGINX_SSL_SETUP.md` - 详细的安装和配置说明
- `README_NGINX_SSL.md` - 本总结文档

## 快速开始

### 1. 一键部署（推荐）
```bash
sudo ./deploy.sh
```

### 2. 分步部署
```bash
# 安装nginx和SSL证书
sudo ./setup_nginx_ssl.sh

# 启动AIO-Pod服务
./start_aio_pod.sh

# 安装系统服务（可选）
sudo cp aio-pod.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable aio-pod.service
```

### 3. 测试配置
```bash
./test_https.sh
```

## 配置特性

### SSL/TLS 安全
- 使用Let's Encrypt免费SSL证书
- 强制HTTPS重定向
- TLS 1.2和1.3支持
- 安全头部配置

### 反向代理
- 文件服务器代理到端口8001
- 执行服务器代理到端口8000
- 支持大文件上传（100MB）
- 请求速率限制

### 安全配置
- UFW防火墙配置
- 安全HTTP头部
- 自动证书续期
- 日志记录和监控

## API端点

部署完成后，您的API将在以下地址可用：

- **健康检查**: `https://mcp.aio2030.fun/health`
- **文件上传**: `POST https://mcp.aio2030.fun/api/v1/upload/{type}`
- **文件下载**: `GET https://mcp.aio2030.fun/api/v1/?type={type}&filename={filename}`
- **MCP执行**: `POST https://mcp.aio2030.fun/api/v1/mcp/{filename}`

## 服务管理

### 检查服务状态
```bash
# nginx状态
sudo systemctl status nginx

# AIO-Pod服务状态
systemctl status aio-pod

# 端口使用情况
sudo lsof -i :8000
sudo lsof -i :8001
sudo lsof -i :443
```

### 启动/停止服务
```bash
# 启动服务
sudo systemctl start nginx
./start_aio_pod.sh

# 停止服务
./stop_aio_pod.sh
sudo systemctl stop nginx

# 重启服务
sudo systemctl restart nginx
systemctl restart aio-pod
```

### 查看日志
```bash
# nginx日志
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# AIO-Pod服务日志
tail -f aio_server/file_server.log
tail -f aio_server/exec_server.log

# 系统服务日志
journalctl -u aio-pod -f
```

## SSL证书管理

### 证书位置
证书存储在 `/etc/letsencrypt/live/mcp.aio2030.fun/`

### 手动续期
```bash
sudo certbot renew
sudo systemctl reload nginx
```

### 检查证书状态
```bash
sudo certbot certificates
```

## 故障排除

### 常见问题

1. **证书获取失败**
   - 确保域名DNS指向服务器IP
   - 检查端口80和443是否开放
   - 验证域名可以从互联网访问

2. **nginx配置错误**
   ```bash
   sudo nginx -t
   ```

3. **服务无法启动**
   - 检查conda环境: `conda activate aiopod`
   - 检查Python依赖: `pip install -r requirements.txt`
   - 检查端口可用性: `lsof -i :8001`

4. **SSL证书过期**
   ```bash
   sudo certbot renew
   sudo systemctl reload nginx
   ```

### 调试命令
```bash
# 检查nginx配置
sudo nginx -t

# 检查SSL证书
sudo certbot certificates

# 检查服务状态
systemctl status aio-pod
systemctl status nginx

# 检查日志
journalctl -u aio-pod -n 50
sudo tail -f /var/log/nginx/error.log

# 测试端点
curl -v https://mcp.aio2030.fun/health
```

## 安全考虑

1. **防火墙**: UFW配置为只允许必要端口
2. **SSL**: 强制使用TLS 1.2和1.3
3. **头部**: 添加安全头部防止常见攻击
4. **速率限制**: API端点配置了速率限制
5. **文件上传**: 大文件上传安全处理

## 备份和恢复

### 备份配置
```bash
# 备份nginx配置
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# 备份SSL证书
sudo cp -r /etc/letsencrypt /backup/letsencrypt
```

### 恢复配置
```bash
# 恢复nginx配置
sudo cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl reload nginx

# 恢复SSL证书
sudo cp -r /backup/letsencrypt /etc/
```

## 维护

### 定期任务
1. **证书续期**: 配置了自动每日续期
2. **日志轮转**: nginx日志自动轮转
3. **安全更新**: 保持nginx和certbot更新

### 监控
- 监控证书过期: `sudo certbot certificates`
- 监控nginx状态: `systemctl status nginx`
- 监控服务日志: `journalctl -u aio-pod -f`

## 下一步

1. 运行 `sudo ./deploy.sh` 开始部署
2. 运行 `./test_https.sh` 测试配置
3. 访问 `https://mcp.aio2030.fun` 验证服务
4. 根据需要调整配置参数

## 支持

如果遇到问题，请检查：
1. 域名DNS配置是否正确
2. 服务器防火墙设置
3. 服务日志中的错误信息
4. SSL证书状态

所有脚本都包含详细的错误处理和日志记录，可以帮助诊断问题。 