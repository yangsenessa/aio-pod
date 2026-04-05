#!/usr/bin/env bash
# 验证 mcp.aio2030.fun / webchat.aio2030.fun 各 endpoint 是否可达
# 用法: bash scripts/verify_endpoints.sh

set -e

MCP_BASE="https://mcp.aio2030.fun"
CHAT_BASE="https://webchat.aio2030.fun"

red () { echo -e "\033[0;31m$*\033[0m"; }
green () { echo -e "\033[0;32m$*\033[0m"; }
yellow () { echo -e "\033[1;33m$*\033[0m"; }

check() {
    local name="$1"
    local method="$2"
    local url="$3"
    local data="$4"
    local expect="${5:-200}"
    local code
    code=$(curl -s -o /tmp/verify_resp.txt -w "%{http_code}" -X "$method" "$url" ${data:+ -d "$data"} ${data:+ -H "Content-Type: application/json"})
    if [[ "$code" == "$expect" ]]; then
        green "[OK] $name (HTTP $code)"
    else
        red "[FAIL] $name (HTTP $code, expected $expect)"
        head -c 200 /tmp/verify_resp.txt
        echo
    fi
}

echo "=== MCP (mcp.aio2030.fun) ==="
check "Health"           GET  "$MCP_BASE/health" ""
# Upload 需 multipart，单独测
upcode=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$MCP_BASE/upload/mcp" -F "file=@/etc/hostname")
[[ "$upcode" == "200" ]] && green "[OK] Upload (POST) (HTTP $upcode)" || red "[FAIL] Upload (POST) (HTTP $upcode)"
check "Download (GET)"   GET  "$MCP_BASE/?type=mcp&filename=test" ""  "200"
# RPC：文件不存在时返回 404 + JSON-RPC error，表示接口正常
check "RPC MCP (POST)"   POST "$MCP_BASE/api/v1/rpc/mcp/nonexistent" '{"jsonrpc":"2.0","method":"ping","id":1}' "404"

echo ""
echo "=== Chat (webchat.aio2030.fun) ==="
check "List Models"      GET  "$CHAT_BASE/v1/models" ""
# Chat Completions: 200=正常, 422/500=接口可达但网关/上游异常
code=$(curl -s -o /tmp/chat_resp.txt -w "%{http_code}" -X POST "$CHAT_BASE/v1/chat/completions" -H "Content-Type: application/json" -d '{"model":"gpt-4","messages":[{"role":"user","content":"hi"}]}')
if [[ "$code" == "200" ]]; then
    green "[OK] Chat Completions (HTTP 200)"
elif [[ "$code" == "422" || "$code" == "500" ]]; then
    yellow "[WARN] Chat Completions 可达但上游异常 (HTTP $code)"
    head -c 120 /tmp/chat_resp.txt; echo
else
    red "[FAIL] Chat Completions (HTTP $code)"
fi

echo ""
echo "=== Done ==="
