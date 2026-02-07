# 平台兼容性说明

## 支持的平台

AIO-Pod 服务脚本现在支持以下平台：

### ✅ Linux (Ubuntu/Debian/CentOS)
- 完整支持所有功能
- 使用 `systemd` 管理 Nginx
- 使用 `systemctl` 命令

### ✅ macOS
- 支持所有核心服务（File Server, Exec Server, Chat Router）
- Nginx 管理使用原生命令（如果已安装）
- 自动检测并使用适当的命令

### ⚠️ Windows
- 建议使用 WSL2 (Windows Subsystem for Linux)
- 或使用 Git Bash / MinGW

## 平台差异

### Nginx 管理命令

**Linux (systemd)**:
```bash
sudo systemctl start nginx
sudo systemctl stop nginx
sudo systemctl restart nginx
sudo systemctl reload nginx
sudo systemctl status nginx
```

**macOS**:
```bash
sudo nginx                    # 启动
sudo nginx -s stop            # 停止
sudo nginx -s reload          # 重新加载配置
sudo nginx -t                 # 测试配置
ps aux | grep nginx           # 查看状态
```

### 服务检查

脚本会自动检测平台并使用适当的命令：

```bash
# Linux - 使用 systemctl
if systemctl is-active --quiet nginx; then
    echo "Nginx: RUNNING"
fi

# macOS - 使用 pgrep
if pgrep -x nginx > /dev/null; then
    echo "Nginx: RUNNING"
fi
```

## 自动平台检测

启动和停止脚本会自动检测：

1. **systemctl 可用性** - 用于 Linux systemd
2. **nginx 命令可用性** - 用于 macOS 或其他系统
3. **conda 路径** - 在多个常见位置搜索

## macOS 特定说明

### 安装 Nginx (可选)

使用 Homebrew 安装：
```bash
brew install nginx
```

### Nginx 配置路径

Homebrew 安装的 Nginx：
- 配置文件：`/usr/local/etc/nginx/nginx.conf`
- 站点配置：`/usr/local/etc/nginx/servers/`
- 日志文件：`/usr/local/var/log/nginx/`

系统默认路径：
- 配置文件：`/etc/nginx/nginx.conf`
- 站点配置：`/etc/nginx/sites-available/`, `/etc/nginx/sites-enabled/`
- 日志文件：`/var/log/nginx/`

### 端口权限

macOS 上绑定 < 1024 的端口需要 root 权限：
```bash
# 启动需要 sudo
sudo nginx

# 或者修改配置使用非特权端口
listen 8080;  # 而不是 80
listen 8443;  # 而不是 443
```

### 开发模式

在 macOS 上开发时，建议：

1. **不使用 Nginx**：直接访问服务端口
   ```bash
   # 访问本地服务
   curl http://localhost:8002/health
   ```

2. **使用测试脚本**：
   ```bash
   python3 test_chat_router.py
   ```

3. **在生产服务器上部署 Nginx**（Linux）

## 常见问题

### Q: macOS 上 `systemctl: command not found`

**A**: 这是正常的，macOS 不使用 systemd。脚本已更新为自动检测平台并使用适当的命令。

### Q: macOS 上如何管理 Nginx？

**A**: 使用以下命令：
```bash
# 启动
sudo nginx

# 停止
sudo nginx -s stop

# 重新加载
sudo nginx -s reload

# 测试配置
sudo nginx -t
```

### Q: 为什么启动脚本在 macOS 上跳过 Nginx？

**A**: Nginx 通常不需要在开发环境（macOS）上运行。服务可以直接通过端口访问。Nginx 主要用于生产环境的反向代理和 SSL 终止。

### Q: Conda 环境在 macOS 上找不到？

**A**: 脚本会在以下位置自动搜索：
- `$HOME/miniconda3`
- `$HOME/anaconda3`
- `$HOME/conda`
- `/opt/conda`
- `/opt/miniconda3`
- `/opt/anaconda3`

如果你的 Conda 安装在其他位置，请手动激活：
```bash
conda activate aiopod
```

## 测试平台兼容性

运行以下命令测试：

```bash
# 检查脚本平台检测
./stop_aio_pod.sh

# 应该看到类似输出：
# Nginx: NOT INSTALLED (macOS 开发环境)
# 或
# Nginx: RUNNING (Linux 生产环境)
```

## 建议的部署方式

### 开发环境 (macOS/Linux Desktop)
- 运行 Python 服务（8000, 8001, 8002）
- 不使用 Nginx
- 直接访问 localhost 端口

### 生产环境 (Linux Server)
- 运行所有服务
- 使用 Nginx 作为反向代理
- 配置 SSL/HTTPS
- 使用域名访问

## 更新记录

### 2026-02-07
- ✅ 修复 macOS 上的 `systemctl: command not found` 错误
- ✅ 添加平台自动检测
- ✅ 支持多种 Nginx 管理方式
- ✅ 改进停止脚本的兼容性
- ✅ 改进启动脚本的兼容性
