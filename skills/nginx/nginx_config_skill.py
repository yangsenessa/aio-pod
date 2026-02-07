"""
Nginx Configuration Skill
生成 Nginx 配置文件的技能
"""

import os
import sys
import argparse
from typing import Dict, Any, Optional
from pathlib import Path
from jinja2 import Environment, FileSystemLoader, Template

from skills.base_skill import BaseSkill


class NginxConfigSkill(BaseSkill):
    """Nginx 配置生成技能"""
    
    def __init__(self):
        super().__init__(
            name="nginx_config",
            description="Generate Nginx configuration files",
            version="1.0.0"
        )
        
        # 获取模板目录
        self.template_dir = Path(__file__).parent / "templates"
        self.env = Environment(loader=FileSystemLoader(str(self.template_dir)))
    
    def execute(self, **kwargs) -> str:
        """
        生成 Nginx 配置
        
        Args:
            domain: 域名
            service_type: 服务类型 (chat_router, file_server, exec_server)
            backend_port: 后端端口
            enable_ssl: 是否启用 SSL
            cert_path: SSL 证书路径（启用 SSL 时必需）
            key_path: SSL 密钥路径（启用 SSL 时必需）
            max_body_size: 最大请求体大小（默认 100M）
            proxy_timeout: 代理超时时间（默认 300秒）
            
        Returns:
            生成的 Nginx 配置内容
        """
        # 验证必需参数
        required = ["domain", "service_type", "backend_port"]
        if not self.validate_params(kwargs, required):
            raise ValueError("Missing required parameters")
        
        domain = kwargs["domain"]
        service_type = kwargs["service_type"]
        backend_port = kwargs["backend_port"]
        enable_ssl = kwargs.get("enable_ssl", False)
        cert_path = kwargs.get("cert_path", f"/etc/letsencrypt/live/{domain}/fullchain.pem")
        key_path = kwargs.get("key_path", f"/etc/letsencrypt/live/{domain}/privkey.pem")
        max_body_size = kwargs.get("max_body_size", "100M")
        proxy_timeout = kwargs.get("proxy_timeout", 300)
        
        # SSL 参数验证
        if enable_ssl:
            if not cert_path or not key_path:
                raise ValueError("cert_path and key_path are required when enable_ssl is True")
        
        # 选择模板
        if service_type == "chat_router":
            template_name = "chat_router.conf.j2"
        elif enable_ssl:
            template_name = "https.conf.j2"
        else:
            template_name = "http.conf.j2"
        
        # 加载模板
        try:
            template = self.env.get_template(template_name)
        except Exception as e:
            raise ValueError(f"Failed to load template {template_name}: {str(e)}")
        
        # 渲染模板
        config = template.render(
            domain=domain,
            service_type=service_type,
            backend_port=backend_port,
            enable_ssl=enable_ssl,
            cert_path=cert_path,
            key_path=key_path,
            max_body_size=max_body_size,
            proxy_timeout=proxy_timeout
        )
        
        return config
    
    def generate_config(
        self,
        domain: str,
        service_type: str,
        backend_port: int,
        enable_ssl: bool = False,
        cert_path: Optional[str] = None,
        key_path: Optional[str] = None,
        max_body_size: str = "100M",
        proxy_timeout: int = 300
    ) -> str:
        """
        便捷方法：生成 Nginx 配置
        
        Args:
            domain: 域名
            service_type: 服务类型
            backend_port: 后端端口
            enable_ssl: 是否启用 SSL
            cert_path: SSL 证书路径
            key_path: SSL 密钥路径
            max_body_size: 最大请求体大小
            proxy_timeout: 代理超时时间
            
        Returns:
            生成的配置内容
        """
        return self.execute(
            domain=domain,
            service_type=service_type,
            backend_port=backend_port,
            enable_ssl=enable_ssl,
            cert_path=cert_path,
            key_path=key_path,
            max_body_size=max_body_size,
            proxy_timeout=proxy_timeout
        )


def main():
    """命令行入口"""
    parser = argparse.ArgumentParser(
        description="Generate Nginx configuration files"
    )
    
    parser.add_argument(
        "--domain",
        required=True,
        help="Domain name (e.g., webchat.aio2030.fun)"
    )
    
    parser.add_argument(
        "--service-type",
        required=True,
        choices=["chat_router", "file_server", "exec_server"],
        help="Service type"
    )
    
    parser.add_argument(
        "--backend-port",
        type=int,
        required=True,
        help="Backend service port"
    )
    
    parser.add_argument(
        "--enable-ssl",
        action="store_true",
        help="Enable SSL/HTTPS"
    )
    
    parser.add_argument(
        "--cert-path",
        help="SSL certificate path (default: /etc/letsencrypt/live/{domain}/fullchain.pem)"
    )
    
    parser.add_argument(
        "--key-path",
        help="SSL key path (default: /etc/letsencrypt/live/{domain}/privkey.pem)"
    )
    
    parser.add_argument(
        "--max-body-size",
        default="100M",
        help="Maximum request body size (default: 100M)"
    )
    
    parser.add_argument(
        "--proxy-timeout",
        type=int,
        default=300,
        help="Proxy timeout in seconds (default: 300)"
    )
    
    parser.add_argument(
        "--output",
        "-o",
        help="Output file path (default: stdout)"
    )
    
    args = parser.parse_args()
    
    # 创建技能实例
    skill = NginxConfigSkill()
    
    # 生成配置
    try:
        config = skill.generate_config(
            domain=args.domain,
            service_type=args.service_type,
            backend_port=args.backend_port,
            enable_ssl=args.enable_ssl,
            cert_path=args.cert_path,
            key_path=args.key_path,
            max_body_size=args.max_body_size,
            proxy_timeout=args.proxy_timeout
        )
        
        # 输出配置
        if args.output:
            with open(args.output, "w") as f:
                f.write(config)
            print(f"✓ Configuration written to: {args.output}")
        else:
            print(config)
    
    except Exception as e:
        print(f"✗ Error: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
