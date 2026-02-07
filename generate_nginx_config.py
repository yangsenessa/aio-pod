#!/usr/bin/env python3
"""
Generate Nginx Configuration for webchat.aio2030.fun
为 Chat Router 服务生成 Nginx 配置
"""

import sys
import os
from pathlib import Path

# 添加项目根目录到 Python 路径
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

from skills.nginx.nginx_config_skill import NginxConfigSkill


def main():
    """生成 Chat Router 的 Nginx 配置"""
    
    print("=" * 70)
    print("Nginx Configuration Generator for Chat Router")
    print("=" * 70)
    print()
    
    # 配置参数
    domain = "webchat.aio2030.fun"
    service_type = "chat_router"
    backend_port = 8002
    enable_ssl = True
    cert_path = f"/etc/letsencrypt/live/{domain}/fullchain.pem"
    key_path = f"/etc/letsencrypt/live/{domain}/privkey.pem"
    
    print(f"Domain: {domain}")
    print(f"Service Type: {service_type}")
    print(f"Backend Port: {backend_port}")
    print(f"Enable SSL: {enable_ssl}")
    print(f"Certificate: {cert_path}")
    print(f"Private Key: {key_path}")
    print()
    
    # 创建技能实例
    skill = NginxConfigSkill()
    
    # 生成配置
    try:
        config = skill.generate_config(
            domain=domain,
            service_type=service_type,
            backend_port=backend_port,
            enable_ssl=enable_ssl,
            cert_path=cert_path,
            key_path=key_path
        )
        
        # 输出到文件
        output_file = project_root / "nginx_webchat.conf"
        with open(output_file, "w") as f:
            f.write(config)
        
        print("✓ Configuration generated successfully!")
        print()
        print(f"Output file: {output_file}")
        print()
        print("=" * 70)
        print("Next Steps:")
        print("=" * 70)
        print()
        print("1. 复制配置文件到 Nginx 配置目录：")
        print(f"   sudo cp {output_file} /etc/nginx/sites-available/webchat.aio2030.fun.conf")
        print()
        print("2. 创建符号链接：")
        print("   sudo ln -s /etc/nginx/sites-available/webchat.aio2030.fun.conf /etc/nginx/sites-enabled/")
        print()
        print("3. 测试 Nginx 配置：")
        print("   sudo nginx -t")
        print()
        print("4. 重新加载 Nginx：")
        print("   sudo systemctl reload nginx")
        print()
        print("5. 检查服务状态：")
        print("   curl https://webchat.aio2030.fun/health")
        print()
        print("=" * 70)
        print()
        
        # 显示配置内容预览
        print("Configuration Preview:")
        print("-" * 70)
        lines = config.split("\n")
        for i, line in enumerate(lines[:30], 1):
            print(f"{i:3d} | {line}")
        if len(lines) > 30:
            print(f"... ({len(lines) - 30} more lines)")
        print("-" * 70)
        
    except Exception as e:
        print(f"✗ Error: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
