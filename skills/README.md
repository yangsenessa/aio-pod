# Skills Framework for AIO-Pod

该框架提供了一套可扩展的技能系统，用于管理和生成各种配置文件。

## 目录结构

```
skills/
├── __init__.py           # 技能框架初始化
├── base_skill.py         # 技能基类
├── skill_manager.py      # 技能管理器
├── nginx/                # Nginx 相关技能
│   ├── __init__.py
│   ├── nginx_config_skill.py
│   └── templates/        # Nginx 配置模板
│       ├── http.conf.j2
│       ├── https.conf.j2
│       └── chat_router.conf.j2
└── README.md            # 本文件

## 使用方法

### 1. 生成 Nginx 配置

```python
from skills.nginx.nginx_config_skill import NginxConfigSkill

skill = NginxConfigSkill()
config = skill.generate_config(
    domain="webchat.aio2030.fun",
    service_type="chat_router",
    backend_port=8002,
    enable_ssl=True,
    cert_path="/etc/letsencrypt/live/webchat.aio2030.fun/fullchain.pem",
    key_path="/etc/letsencrypt/live/webchat.aio2030.fun/privkey.pem"
)
print(config)
```

### 2. 通过命令行使用

```bash
# 生成 Chat Router 的 Nginx 配置
python -m skills.nginx.nginx_config_skill \
    --domain webchat.aio2030.fun \
    --service-type chat_router \
    --backend-port 8002 \
    --enable-ssl \
    --output /tmp/nginx_chat_router.conf
```

## 扩展新技能

1. 继承 `BaseSkill` 类
2. 实现 `execute()` 方法
3. 在 `skill_manager.py` 中注册新技能

示例：

```python
from skills.base_skill import BaseSkill

class MySkill(BaseSkill):
    def __init__(self):
        super().__init__(
            name="my_skill",
            description="My custom skill",
            version="1.0.0"
        )
    
    def execute(self, **kwargs):
        # 实现技能逻辑
        pass
```
