#!/usr/bin/env bash
# 统一域名与 Cloudflare Origin Certificate 路径（源站 Nginx 使用，配合 CF SSL Full Strict）
# 在仓库内其它脚本中通过: source "$(dirname ...)/scripts/domain_constants.sh" 引用
#
# 默认值（未设置环境变量时）:
#   MCP_DOMAIN=mcp.univoices.club
#   WEBCHAT_DOMAIN=webchat.univoices.club

export MCP_DOMAIN="${MCP_DOMAIN:-mcp.univoices.club}"
export WEBCHAT_DOMAIN="${WEBCHAT_DOMAIN:-webchat.univoices.club}"

export MCP_BASE_URL="${MCP_BASE_URL:-https://${MCP_DOMAIN}}"
export WEBCHAT_BASE_URL="${WEBCHAT_BASE_URL:-https://${WEBCHAT_DOMAIN}}"

# Cloudflare 控制台生成的 Origin Certificate（PEM）及私钥；证书 SAN 需包含上述主机名
export CF_ORIGIN_CERT="${CF_ORIGIN_CERT:-/etc/ssl/cloudflare/univoices.origin.pem}"
export CF_ORIGIN_KEY="${CF_ORIGIN_KEY:-/etc/ssl/cloudflare/univoices.origin.key}"
