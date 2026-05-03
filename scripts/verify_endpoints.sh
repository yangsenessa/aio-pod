#!/usr/bin/env bash
# 验证 MCP / Webchat 各 endpoint 是否可达（域名见 scripts/domain_constants.sh）
# 启动时清除 HTTP(S) 代理环境变量；所有 curl 使用 --noproxy '*'。
# macOS: 无 /etc/hostname 时会写入临时探针文件做上传测试；需 bash + curl。
#
# 默认域名（可被环境变量覆盖）:
#   MCP_DOMAIN=mcp.univoices.club
#   WEBCHAT_DOMAIN=webchat.univoices.club
#
# 用法:
#   bash scripts/verify_endpoints.sh
#   MCP_DOMAIN=mcp.other.org WEBCHAT_DOMAIN=webchat.other.org bash scripts/verify_endpoints.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/domain_constants.sh
source "${ROOT}/scripts/domain_constants.sh"

disable_http_proxies() {
  local any=0
  [[ -n "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}${ALL_PROXY:-}${ftp_proxy:-}${FTP_PROXY:-}" ]] && any=1
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY ftp_proxy FTP_PROXY no_proxy NO_PROXY 2>/dev/null || true
  if [[ "$any" -eq 1 ]]; then
    printf '\033[1;33m[proxy] 已清除 HTTP(S)/ALL/ftp 代理环境变量（本子进程内）。\033[0m\n'
  fi
}
disable_http_proxies

MCP_BASE="$MCP_BASE_URL"
CHAT_BASE="$WEBCHAT_BASE_URL"

RESP_DIR="${TMPDIR:-/tmp}"
VERIFY_RESP="${RESP_DIR}/verify_resp.$$"
CHAT_RESP="${RESP_DIR}/verify_chat.$$"
trap 'rm -f "${VERIFY_RESP}" "${CHAT_RESP}" "${VERIFY_RESP}.probe" 2>/dev/null' EXIT

red () { printf '\033[0;31m%s\033[0m\n' "$*"; }
green () { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow () { printf '\033[1;33m%s\033[0m\n' "$*"; }

# 统一 curl：不走代理
_curl() { curl --noproxy '*' "$@"; }

check() {
    local name="$1"
    local method="$2"
    local url="$3"
    local data="$4"
    local expect="${5:-200}"
    local code
    code=$(_curl -s -o "${VERIFY_RESP}" -w "%{http_code}" -X "$method" "$url" ${data:+ -d "$data"} ${data:+ -H "Content-Type: application/json"})
    if [[ "$code" == "$expect" ]]; then
        green "[OK] $name (HTTP $code)"
    else
        red "[FAIL] $name (HTTP $code, expected $expect)"
        head -c 200 "${VERIFY_RESP}" 2>/dev/null || true
        echo
    fi
}

echo "MCP: ${MCP_DOMAIN}  →  ${MCP_BASE}"
echo "Webchat: ${WEBCHAT_DOMAIN}  →  ${CHAT_BASE}"
echo ""

echo "=== MCP (${MCP_DOMAIN}) ==="
check "Health"           GET  "$MCP_BASE/health" ""
UPLOAD_SRC="/etc/hostname"
if [[ ! -r "$UPLOAD_SRC" ]]; then
  UPLOAD_SRC="${VERIFY_RESP}.probe"
  printf 'aio-verify-probe\n' > "${UPLOAD_SRC}"
fi
upcode=$(_curl -s -o /dev/null -w "%{http_code}" -X POST "$MCP_BASE/upload/mcp" -F "file=@${UPLOAD_SRC}")
[[ "${UPLOAD_SRC}" == "${VERIFY_RESP}.probe" ]] && rm -f "${VERIFY_RESP}.probe" 2>/dev/null || true
[[ "$upcode" == "200" ]] && green "[OK] Upload (POST) (HTTP $upcode)" || red "[FAIL] Upload (POST) (HTTP $upcode)"
check "Download (GET)"   GET  "$MCP_BASE/?type=mcp&filename=test" ""  "200"
check "RPC MCP (POST)"   POST "$MCP_BASE/api/v1/rpc/mcp/nonexistent" '{"jsonrpc":"2.0","method":"ping","id":1}' "404"

echo ""
echo "=== Chat (${WEBCHAT_DOMAIN}) ==="
check "List Models"      GET  "$CHAT_BASE/v1/models" ""
code=$(_curl -s -o "${CHAT_RESP}" -w "%{http_code}" -X POST "$CHAT_BASE/v1/chat/completions" -H "Content-Type: application/json" -d '{"model":"gpt-4","messages":[{"role":"user","content":"hi"}]}')
if [[ "$code" == "200" ]]; then
    green "[OK] Chat Completions (HTTP 200)"
elif [[ "$code" == "422" || "$code" == "500" ]]; then
    yellow "[WARN] Chat Completions 可达但上游异常 (HTTP $code)"
    head -c 120 "${CHAT_RESP}"; echo
else
    red "[FAIL] Chat Completions (HTTP $code)"
fi

echo ""
echo "=== Done ==="
