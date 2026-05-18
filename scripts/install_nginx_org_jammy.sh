#!/usr/bin/env bash
# 在 Ubuntu 22.04 (jammy) 上从 nginx.org 安装官方 nginx（解决部分 CF 回源与 Ubuntu 1.18+OpenSSL3 的 TLS 问题）
# 用法: sudo bash scripts/install_nginx_org_jammy.sh
set -euo pipefail
[[ "${EUID:-}" -eq 0 ]] || { echo "请使用 root 运行"; exit 1; }
[[ "$(lsb_release -cs 2>/dev/null)" == "jammy" ]] || { echo "仅针对 jammy 测试过"; exit 1; }

curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
chmod a+r /usr/share/keyrings/nginx-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu jammy nginx" >/etc/apt/sources.list.d/nginx-org.list

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" nginx
systemctl unmask nginx 2>/dev/null || true
systemctl enable --now nginx
nginx -v
