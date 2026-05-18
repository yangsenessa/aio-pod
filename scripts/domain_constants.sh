#!/usr/bin/env bash
# 统一域名与源站 TLS 路径（在仓库内其它脚本中: source "$(dirname ...)/scripts/domain_constants.sh"）
#
# 当前约定：Cloudflare 为 DNS-only（灰云，不经 CF 代理），源站对外直接终止 TLS，
# 使用 Let's Encrypt（例如通配符 *.univoices.club；certbot 常见 live 目录名为 apex 域名）。
#
# 默认值（未设置环境变量时）:
#   MCP_DOMAIN=mcp.univoices.club
#   WEBCHAT_DOMAIN=webchat.univoices.club

export MCP_DOMAIN="${MCP_DOMAIN:-mcp.univoices.club}"
export WEBCHAT_DOMAIN="${WEBCHAT_DOMAIN:-webchat.univoices.club}"

export MCP_BASE_URL="${MCP_BASE_URL:-https://${MCP_DOMAIN}}"
export WEBCHAT_BASE_URL="${WEBCHAT_BASE_URL:-https://${WEBCHAT_DOMAIN}}"

# Let's Encrypt（certbot）：fullchain.pem / privkey.pem；若 live 目录名不同请覆盖 LE_TLS_*
export LE_TLS_CERT="${LE_TLS_CERT:-/etc/letsencrypt/live/univoices.club/fullchain.pem}"
export LE_TLS_KEY="${LE_TLS_KEY:-/etc/letsencrypt/live/univoices.club/privkey.pem}"

# 可选：橙云 + SSL Full (strict) 回源时，源站改用 Cloudflare Origin Certificate（须与 CF 面板一致）
export CF_ORIGIN_CERT="${CF_ORIGIN_CERT:-/etc/ssl/cloudflare/univoices.origin.pem}"
export CF_ORIGIN_KEY="${CF_ORIGIN_KEY:-/etc/ssl/cloudflare/univoices.origin.key}"
