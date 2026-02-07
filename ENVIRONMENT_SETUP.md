# AIO-Pod 环境配置说明

## 问题解决

### 1. Conda 环境问题
- **问题**: `conda not found. Please install Anaconda or Miniconda`
- **解决**: 已安装 Miniconda 并更新启动脚本自动检测和配置 conda 路径

### 2. IOT_ROLE_ARN 环境变量问题
- **问题**: `Environment variable IOT_ROLE_ARN is not set`
- **解决**: 已添加完整的环境变量配置支持

## 环境变量配置

### 快速开始

1. **复制环境变量模板**:
   ```bash
   cp export_env_local.sh export_env_local.sh.backup
   ```

2. **编辑环境变量文件**:
   ```bash
   nano export_env_local.sh
   ```

3. **填入您的真实配置**:
   - 将 `YOUR_UIN` 替换为您的腾讯云账号UIN
   - 将 `YOUR_ROLE_NAME` 替换为您的IoT角色名称
   - 将 `YOUR_SECRET_ID` 和 `YOUR_SECRET_KEY` 替换为您的腾讯云API密钥

### 必需配置项

#### IoT角色ARN
```bash
export IOT_ROLE_ARN="qcs::cam::uin/YOUR_UIN:roleName/YOUR_ROLE_NAME"
```
- **获取方式**: 腾讯云控制台 -> 访问管理 -> 角色 -> 选择角色 -> 复制角色ARN

#### 腾讯云访问凭证
```bash
export TC_SECRET_ID="YOUR_SECRET_ID"
export TC_SECRET_KEY="YOUR_SECRET_KEY"
```
- **获取方式**: 腾讯云控制台 -> 访问管理 -> API密钥管理
- **建议**: 使用子账号密钥，比主账号密钥更安全

### 可选配置项

#### COS对象存储配置
```bash
export COS_OWNER_UIN="YOUR_UIN"
export COS_BUCKET_NAME="your-bucket-name"
export COS_REGION="ap-guangzhou"
```

#### 服务配置
```bash
export DEFAULT_REGION="ap-guangzhou"
export COS_BUCKET="pixelmug-assets"
export LOG_LEVEL="INFO"
```

## 启动服务

### 方法1: 使用启动脚本（推荐）
```bash
./start_aio_pod.sh
```

### 方法2: 手动加载环境变量后启动
```bash
# 加载环境变量
source export_env_local.sh

# 启动服务
./start_aio_pod.sh
```

## 验证配置

启动脚本会自动显示环境变量配置状态：
```
[INFO] Environment configuration:
[INFO]   IOT_ROLE_ARN: qcs::cam::uin/123456789...
[INFO]   TC_SECRET_ID: AKID123456...
[INFO]   DEFAULT_REGION: ap-guangzhou
[INFO]   LOG_LEVEL: INFO
```

## 故障排除

### 1. 环境变量未生效
- 确保 `export_env_local.sh` 文件存在且可执行
- 检查文件中的配置值是否正确
- 确保没有语法错误

### 2. Conda 环境问题
- 启动脚本会自动检测和配置 conda
- 如果仍有问题，手动执行：
  ```bash
  export PATH="/root/miniconda3/bin:$PATH"
  eval "$(/root/miniconda3/bin/conda shell.bash hook)"
  ```

### 3. 服务启动失败
- 检查端口是否被占用：`lsof -i :8000,8001`
- 查看日志文件：`tail -f aio_server/file_server.log`
- 检查环境变量是否正确设置

## 文件说明

- `start_aio_pod.sh`: 主启动脚本，包含环境变量配置和服务启动逻辑
- `export_env_local.sh`: 环境变量配置模板，需要用户填入真实配置
- `ENVIRONMENT_SETUP.md`: 本说明文档

## 安全建议

1. **不要将包含真实密钥的文件提交到版本控制系统**
2. **定期轮换API密钥**
3. **使用子账号密钥而非主账号密钥**
4. **限制API密钥的权限范围**
