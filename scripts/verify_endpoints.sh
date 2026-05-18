#!/usr/bin/env bash
# 验证 MCP / Webchat 各 endpoint 是否可达（域名见 scripts/domain_constants.sh）
# 「浏览器正常、脚本失败」时：脚本 URL/方法与集成文档一致；根因通常是本机递归 DNS、是否走代理、
# 以及 curl(LibreSSL)/TCP-TLS 与浏览器(HTTP3/BoringSSL) 路径不同，而非本脚本写错端点。
# 若直连源站 IP 时仅业务 SNI 失败、中性 SNI（如 example.com）可握手，疑为路径 DPI/按 SNI 策略：
#   bash scripts/diag_sni_path.sh 8.141.81.75
# 启动时清除 HTTP(S) 代理环境变量；所有 curl 默认使用 --noproxy '*'。
# 必须走本机 Clash 等 HTTP 代理（默认 127.0.0.1:7890）：
#   VERIFY_USE_LOCAL_PROXY=1 ./scripts/verify_endpoints.sh
# 或指定 URL：VERIFY_PROXY_URL=http://127.0.0.1:7890 ./scripts/verify_endpoints.sh
# 保留当前 shell 已有代理、不清除：VERIFY_KEEP_HTTP_PROXY=1 ./scripts/verify_endpoints.sh
# macOS: 无 /etc/hostname 时会写入临时探针文件做上传测试；需 bash + curl。
#
# 默认域名（可被环境变量覆盖）:
#   MCP_DOMAIN=mcp.univoices.club
#   WEBCHAT_DOMAIN=webchat.univoices.club
#
# 用法:
#   bash scripts/verify_endpoints.sh
#   VERIFY_USE_LOCAL_PROXY=1 bash scripts/verify_endpoints.sh
#   MCP_DOMAIN=mcp.other.org WEBCHAT_DOMAIN=webchat.other.org bash scripts/verify_endpoints.sh
#
# 若「浏览器能打开 /health，但本脚本 curl 报 35 / reset」：二者往往走的不是同一条路。
#   - Chrome 可能走 HTTP/3(QUIC/UDP)，curl 默认是 TCP+TLS；一边通、一边被中间设备 RST 很常见。
#   - TLS ClientHello 指纹（密码套件/扩展）不同，前置 WAF/防爬可能只放行「像浏览器」的握手。
#   - 浏览器 DoH 与系统 dig 可能解析到不同 anycast 节点。
#   可对照：Chrome 网络面板里该请求的「协议」与「远程地址」；终端试 curl --http1.1 / --tlsv1.2 或 brew 的 curl（OpenSSL）与 --http3（若支持）。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/domain_constants.sh
source "${ROOT}/scripts/domain_constants.sh"

if [[ "${VERIFY_USE_LOCAL_PROXY:-}" == "1" ]]; then
  VERIFY_PROXY_URL="${VERIFY_PROXY_URL:-http://127.0.0.1:7890}"
fi

disable_http_proxies() {
  if [[ -n "${VERIFY_PROXY_URL:-}" ]]; then
    export http_proxy="${VERIFY_PROXY_URL}" https_proxy="${VERIFY_PROXY_URL}" \
      HTTP_PROXY="${VERIFY_PROXY_URL}" HTTPS_PROXY="${VERIFY_PROXY_URL}" \
      ALL_PROXY="${VERIFY_PROXY_URL}" all_proxy="${VERIFY_PROXY_URL}"
    printf '\033[1;33m[proxy] VERIFY_PROXY_URL=%s（curl 经 HTTP 代理；已同步 ALL_PROXY）。\033[0m\n' "$VERIFY_PROXY_URL"
    return 0
  fi
  if [[ "${VERIFY_KEEP_HTTP_PROXY:-}" == "1" ]]; then
    printf '\033[1;33m[proxy] VERIFY_KEEP_HTTP_PROXY=1：保留代理变量，curl 将使用系统代理。\033[0m\n'
    return 0
  fi
  local any=0
  [[ -n "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}${ALL_PROXY:-}${all_proxy:-}${ftp_proxy:-}${FTP_PROXY:-}" ]] && any=1
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy ftp_proxy FTP_PROXY no_proxy NO_PROXY 2>/dev/null || true
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

# 统一 curl：默认不走代理；VERIFY_PROXY_URL / VERIFY_KEEP_HTTP_PROXY=1 时不加 --noproxy。
# 调用处请用 -sS：失败时 curl 会把原因打到 stderr（HTTP 000 时便于对照）。
_curl() {
  # 禁止对空数组做 "${arr[@]}" 展开：set -u 下会报 unbound variable。
  if [[ "${VERIFY_KEEP_HTTP_PROXY:-}" == "1" || -n "${VERIFY_PROXY_URL:-}" ]]; then
    curl \
      --connect-timeout "${CURL_CONNECT_TIMEOUT:-20}" \
      --max-time "${CURL_MAX_TIME:-180}" \
      "$@"
  else
    curl --noproxy '*' \
      --connect-timeout "${CURL_CONNECT_TIMEOUT:-20}" \
      --max-time "${CURL_MAX_TIME:-180}" \
      "$@"
  fi
}

check() {
    local name="$1"
    local method="$2"
    local url="$3"
    local data="$4"
    local expect="${5:-200}"
    local code
    code=$(_curl -sS -o "${VERIFY_RESP}" -w "%{http_code}" -X "$method" "$url" ${data:+ -d "$data"} ${data:+ -H "Content-Type: application/json"}) || code="000"
    code="${code//$'\r'/}"
    code="${code//$'\n'/}"
    if [[ "$code" == "$expect" ]]; then
        green "[OK] $name (HTTP $code)"
    else
        red "[FAIL] $name (HTTP $code, expected $expect)"
        [[ "$code" == "000" ]] && yellow "  提示: 000=未收到 HTTP；含义见上方 curl 行。"
        [[ "$code" == "525" ]] && yellow "  提示: CF 525=回源 HTTPS 失败；查源站 443/证书与 CF「SSL/TLS」模式。"
        head -c 200 "${VERIFY_RESP}" 2>/dev/null || true
        echo
    fi
}

echo "MCP: ${MCP_DOMAIN}  →  ${MCP_BASE}"
echo "Webchat: ${WEBCHAT_DOMAIN}  →  ${CHAT_BASE}"
if [[ -z "${VERIFY_PROXY_URL:-}" && "${VERIFY_KEEP_HTTP_PROXY:-}" != "1" ]]; then
  yellow "提示: curl 为直连；若须 7890: VERIFY_USE_LOCAL_PROXY=1 bash \"${BASH_SOURCE[0]}\""
fi

# 浏览器能打开而脚本失败时，多数不是「URL 写错」，而是：解析到的 IP/协议/TLS 与浏览器不一致。
print_dns_hint() {
  command -v dig >/dev/null 2>&1 || return 0
  local m w ns am aw ttl_line apex
  m=$(dig +short "${MCP_DOMAIN}." A 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  w=$(dig +short "${WEBCHAT_DOMAIN}." A 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  printf '  递归 DNS A → %s: %s\n' "${MCP_DOMAIN}" "${m:-（无应答）}"
  printf '  递归 DNS A → %s: %s\n' "${WEBCHAT_DOMAIN}" "${w:-（无应答）}"
  # 取第一条 A 应答整行（避免 grep 在「IN」「A」间断行时拼成 INA）
  ttl_line=$(dig "${WEBCHAT_DOMAIN}." A +noall +answer 2>/dev/null | awk '!/^;/ && NF >= 5 && $4 == "A" { print; exit }')
  [[ -n "$ttl_line" ]] && printf '  递归 TTL/应答(%s): %s\n' "${WEBCHAT_DOMAIN}" "$ttl_line"

  apex="${MCP_DOMAIN#*.}"
  [[ "$apex" == "$MCP_DOMAIN" ]] && apex="$MCP_DOMAIN"
  ns=$(dig +short NS "${apex}." 2>/dev/null | head -1)
  if [[ -n "$ns" ]]; then
    ns="${ns%.}"
    am=$(dig @"${ns}" +short "${MCP_DOMAIN}." A 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    aw=$(dig @"${ns}" +short "${WEBCHAT_DOMAIN}." A 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    printf '  权威 NS %s → %s: %s\n' "$ns" "${MCP_DOMAIN}" "${am:-?}"
    printf '  权威 NS %s → %s: %s\n' "$ns" "${WEBCHAT_DOMAIN}" "${aw:-?}"
  fi

  if printf '%s%s' "$m" "$w" | grep -qE '(104\.21\.|172\.67\.)'; then
    yellow "  说明: 递归含 Cloudflare 任播段时，525 只会在经 CF 边缘时出现。"
    if [[ -n "$am$aw" ]] && ! printf '%s%s' "$am" "$aw" | grep -qE '(104\.21\.|172\.67\.)'; then
      yellow "  排查: 权威已是源站 IP，递归仍为 CF → 本机/上游递归在「吃旧缓存」。"
      yellow "    · 等该记录 TTL 过期（见上「IN A」前的秒数）；CF 自动 TTL 常见 300～3600。"
      yellow "    · 刷新本机: sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
      yellow "    · 路由器/光猫作 DNS 会缓存，可重启路由或系统设置里 DNS 改为 1.1.1.1 再 dig 对照。"
      yellow "    · 对比: dig +short 与 dig @<上面权威NS> +short 是否一致。"
    fi
  fi
  if [[ -n "${m:-}${w:-}" ]] && ! printf '%s%s' "$m" "$w" | grep -qE '(104\.21\.|172\.67\.)'; then
    yellow "  说明: 递归/权威均为源站 IP 时，若仍 curl(35)/000，与 DNS 无关；试代理 VERIFY_USE_LOCAL_PROXY=1 或 curl --http1.1 / brew curl。"
  fi
}
print_dns_hint
echo ""

echo "=== MCP (${MCP_DOMAIN}) ==="
check "Health"           GET  "$MCP_BASE/health" ""
UPLOAD_SRC="/etc/hostname"
if [[ ! -r "$UPLOAD_SRC" ]]; then
  UPLOAD_SRC="${VERIFY_RESP}.probe"
  printf 'aio-verify-probe\n' > "${UPLOAD_SRC}"
fi
printf '  → 正在请求 Upload: POST %s/upload/mcp …\n' "$MCP_BASE"
upcode=$(_curl -sS -o /dev/null -w "%{http_code}" -X POST "$MCP_BASE/upload/mcp" -F "file=@${UPLOAD_SRC}") || upcode="000"
upcode="${upcode//$'\r'/}"
upcode="${upcode//$'\n'/}"
[[ "${UPLOAD_SRC}" == "${VERIFY_RESP}.probe" ]] && rm -f "${VERIFY_RESP}.probe" 2>/dev/null || true
if [[ "$upcode" == "200" ]]; then green "[OK] Upload (POST) (HTTP $upcode)"; else red "[FAIL] Upload (POST) (HTTP $upcode)"; [[ "$upcode" == "000" ]] && yellow "  提示: 见上方 curl 行。"; fi
check "Download (GET)"   GET  "$MCP_BASE/?type=mcp&filename=test" ""  "200"
check "RPC MCP (POST)"   POST "$MCP_BASE/api/v1/rpc/mcp/nonexistent" '{"jsonrpc":"2.0","method":"ping","id":1}' "404"

echo ""
echo "=== Chat (${WEBCHAT_DOMAIN}) ==="
check "List Models"      GET  "$CHAT_BASE/v1/models" ""
code=$(_curl -sS -o "${CHAT_RESP}" -w "%{http_code}" -X POST "$CHAT_BASE/v1/chat/completions" -H "Content-Type: application/json" -d '{"model":"gpt-4","messages":[{"role":"user","content":"hi"}]}') || code="000"
code="${code//$'\r'/}"
code="${code//$'\n'/}"
if [[ "$code" == "200" ]]; then
    green "[OK] Chat Completions (HTTP 200)"
elif [[ "$code" == "422" || "$code" == "500" ]]; then
    yellow "[WARN] Chat Completions 可达但上游异常 (HTTP $code)"
    head -c 120 "${CHAT_RESP}"; echo
else
    red "[FAIL] Chat Completions (HTTP $code)"
    [[ "$code" == "000" ]] && yellow "  提示: 见上方 curl 行。"
fi

echo ""
echo "=== Done ==="
