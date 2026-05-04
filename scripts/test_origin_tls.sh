#!/usr/bin/env bash
# 测试源站 IP:443 的 TLS（SNI、证书、TLS1.2/1.3、HTTP /health）
# 默认覆盖 MCP + Webchat 两个功能域名（见 scripts/domain_constants.sh，可用环境变量覆盖）
#
# 默认域名（可被 MCP_DOMAIN / WEBCHAT_DOMAIN / NAMES 覆盖）:
#   MCP_DOMAIN=mcp.univoices.club
#   WEBCHAT_DOMAIN=webchat.univoices.club
#
# 用法:
#   bash scripts/test_origin_tls.sh
#   ORIGIN=8.141.81.75 bash scripts/test_origin_tls.sh
#   NAMES="mcp.univoices.club webchat.univoices.club" ORIGIN=1.2.3.4 bash scripts/test_origin_tls.sh
#
# 注意:
#   - 脚本启动时会清除本进程内 HTTP(S) 代理环境变量，避免 curl/openssl 经代理导致误判。
#   - openssl s_client 在校验不信任证书时常返回非 0；成功以「已协商出真实套件」为准（排除 Cipher is (NONE)）。
#   - Cloudflare 回源会带 ALPN（常见 h2 与 http/1.1 组合）；若存在多份相同 server_name 的 server 块且先加载了 http2 off，仅宣告 h2 的 ClientHello 可能与源站无 ALPN 重叠→握手失败/525。
#   - curl 使用 --noproxy '*'；健康检查默认 --http1.1。
#   - macOS: 默认 Bash 往往无 /dev/tcp，[1] 会用 nc 探测；无 timeout 时会尝试 perl alarm（可选 brew install coreutils 装 gtimeout）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/domain_constants.sh
source "${ROOT}/scripts/domain_constants.sh"

# 启动时主动关闭代理（仅当前 shell 子进程，不影响已打开的父终端）
disable_http_proxies() {
  local any=0
  [[ -n "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}${ALL_PROXY:-}${ftp_proxy:-}${FTP_PROXY:-}" ]] && any=1
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY ftp_proxy FTP_PROXY no_proxy NO_PROXY 2>/dev/null || true
  if [[ "$any" -eq 1 ]]; then
    printf '\033[1;33m[proxy] 已清除 HTTP(S)/ALL/ftp 代理环境变量（本子进程内）。\033[0m\n'
  fi
}
disable_http_proxies

ORIGIN="${ORIGIN:-8.141.81.75}"
PORT="${PORT:-443}"
NAMES="${NAMES:-${MCP_DOMAIN} ${WEBCHAT_DOMAIN}}"
TIMEOUT="${TIMEOUT:-8}"

with_timeout() {
  local sec="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$sec" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$sec" "$@"
  elif command -v perl >/dev/null 2>&1; then
    # macOS 无 GNU timeout 时的常见替代：perl alarm
    perl -e 'alarm shift @ARGV; exec @ARGV' "$sec" "$@"
  else
    "$@"
  fi
}

# TCP 可达性：优先 nc（BSD 用 -G、GNU/OpenBSD 常用 -w，自带超时，适合 macOS）；否则再试 bash /dev/tcp（多见于 Linux）
tcp_reachable() {
  local host="$1" port="$2"
  if command -v nc >/dev/null 2>&1; then
    if nc -z -G 3 "${host}" "${port}" 2>/dev/null; then return 0; fi
    if nc -z -w 3 "${host}" "${port}" 2>/dev/null; then return 0; fi
  fi
  if exec 3<>"/dev/tcp/${host}/${port}" 2>/dev/null; then
    exec 3<&- 3>&-
    return 0
  fi
  return 1
}

red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
grn()   { printf '\033[0;32m%s\033[0m\n' "$*"; }
ylw()   { printf '\033[1;33m%s\033[0m\n' "$*"; }
info()  { printf '\033[0;34m%s\033[0m\n' "$*"; }

need() {
  command -v "$1" >/dev/null 2>&1 || { red "缺少命令: $1"; exit 1; }
}

need openssl
need curl

# openssl 输出偶含 NUL；command substitution 会触发 bash「ignored null byte」警告
run_s_client() {
  echo | with_timeout "${TIMEOUT}" openssl s_client "$@" 2>&1 | tr -d '\0' || true
}

echo "=============================================="
echo " 源站 TLS 探测"
echo " 目标: ${ORIGIN}:${PORT}"
echo " MCP 域名: ${MCP_DOMAIN}"
echo " Webchat 域名: ${WEBCHAT_DOMAIN}"
echo " SNI 列表: ${NAMES}"
echo "=============================================="
echo

# --- TCP 是否可达 ---
info "[1] TCP ${ORIGIN}:${PORT}"
if tcp_reachable "${ORIGIN}" "${PORT}"; then
  grn "    TCP 可连接"
else
  ylw "    不可达或无 nc（将仍尝试 openssl；macOS 可装 Xcode Command Line Tools 以获得 nc）"
fi
echo

analyze_openssl_out() {
  local label="$1"
  local out="$2"
  if echo "$out" | grep -qE 'Cipher is (TLS_|ECDHE-|DHE-)'; then
    grn "    ${label}: 握手成功"
    echo "$out" | grep -E '^(New,|Cipher|Protocol|Verify return code)' | sed 's/^/    /' || true
    echo "$out" | openssl x509 -noout -subject -dates -ext subjectAltName 2>/dev/null | sed 's/^/    cert> /' || true
  else
    red "    ${label}: 未协商出有效 Cipher（失败/超时/仅见 NONE）"
    echo "$out" | tail -14 | sed 's/^/    | /'
  fi
}

# 客户端仅提供 h2：源站须在 ALPN 中回应 h2（通常需 Nginx http2 on / listen ... http2）
check_alpn_h2_only_client() {
  local out="$1"
  if echo "$out" | grep -q 'ALPN protocol: h2'; then
    grn "    ALPN（客户端仅 h2）: 已协商 h2"
  elif echo "$out" | grep -q 'No ALPN negotiated'; then
    red "    ALPN（客户端仅 h2）: 未协商 — 若 CF 回源 ClientHello 仅含 h2，易导致 525"
  elif echo "$out" | grep -qE 'Cipher is (TLS_|ECDHE-|DHE-)'; then
    ylw "    ALPN（客户端仅 h2）: TLS 成功但未出现 h2（openssl -alpn 或源站 ALPN 列表异常）"
    echo "$out" | grep -E 'ALPN|Application-Layer Protocol' | sed 's/^/    /' || true
  else
    ylw "    ALPN（客户端仅 h2）: 无法判断（握手可能未完整）"
  fi
}

# 客户端提供 h2,http/1.1 时仍可与「仅开 HTTP/1.1 ALPN」的源站重叠；与「仅 h2」探测对照可发现 http2 off / 重复 server 块
check_alpn_cf_style_client() {
  local out="$1"
  if echo "$out" | grep -q 'ALPN protocol: h2'; then
    grn "    ALPN（客户端 h2,http/1.1）: 已协商 h2"
  elif echo "$out" | grep -q 'ALPN protocol: http/1.1'; then
    grn "    ALPN（客户端 h2,http/1.1）: 已协商 http/1.1（TLS 正常；若「仅 h2」探测失败，部分仅宣告 h2 的回源仍可能 525）"
  elif echo "$out" | grep -q 'No ALPN negotiated'; then
    red "    ALPN（客户端 h2,http/1.1）: 未协商"
  elif echo "$out" | grep -qE 'Cipher is (TLS_|ECDHE-|DHE-)'; then
    ylw "    ALPN（客户端 h2,http/1.1）: TLS 成功但未解析到 ALPN 行"
    echo "$out" | grep -E 'ALPN|Application-Layer Protocol' | sed 's/^/    /' || true
  else
    ylw "    ALPN（客户端 h2,http/1.1）: 无法判断"
  fi
}

warn_h2only_mismatch_duplicate_vhost() {
  local out_h2="$1"
  local out_cf="$2"
  if echo "$out_h2" | grep -qE 'Cipher is \(NONE\)|No ALPN negotiated'; then
    if echo "$out_cf" | grep -qE 'ALPN protocol: (h2|http/1.1)'; then
      ylw "    提示: 「仅 ALPN=h2」失败而「h2,http/1.1」成功 — 常见于源站只宣告 http/1.1（如某份配置仍为 http2 off），或与另一份 server_name 相同的块冲突（nginx -T 里出现两套 listen 443 + 同一 server_name 时，先加载的那份生效）。请: sudo grep -rE 'http2[[:space:]]+off' /etc/nginx/ ; sudo nginx -T 2>/dev/null | grep -E 'server_name mcp|http2|listen 443'"
    fi
  fi
}

# --- 每个 SNI：TLS1.3 / TLS1.2 / 默认 ---
for name in ${NAMES}; do
  info "[2] SNI=${name}  (TLS 1.3)"
  out=$(run_s_client -connect "${ORIGIN}:${PORT}" -servername "${name}" -tls1_3)
  analyze_openssl_out "TLS1.3" "$out"
  echo

  info "[2b] SNI=${name}  (TLS 1.2, ECDHE-RSA-AES256-GCM-SHA384)"
  out=$(run_s_client -connect "${ORIGIN}:${PORT}" -servername "${name}" -tls1_2 \
    -cipher 'ECDHE-RSA-AES256-GCM-SHA384')
  analyze_openssl_out "TLS1.2" "$out"
  echo

  info "[2c] SNI=${name}  (openssl 默认协议，不强制 -tls1_2/3)"
  out=$(run_s_client -connect "${ORIGIN}:${PORT}" -servername "${name}")
  analyze_openssl_out "默认" "$out"
  echo

  info "[2d] SNI=${name}  (ALPN 客户端仅 h2；CF 部分路径可能如此)"
  out_h2only=$(run_s_client -connect "${ORIGIN}:${PORT}" -servername "${name}" -alpn h2)
  analyze_openssl_out "ALPN+h2" "$out_h2only"
  check_alpn_h2_only_client "$out_h2only"
  echo

  info "[2e] SNI=${name}  (ALPN=h2,http/1.1，更接近常见浏览器 / CF ClientHello)"
  out_cfalpn=$(run_s_client -connect "${ORIGIN}:${PORT}" -servername "${name}" -alpn 'h2,http/1.1')
  analyze_openssl_out "ALPN+h2,http1.1" "$out_cfalpn"
  check_alpn_cf_style_client "$out_cfalpn"
  warn_h2only_mismatch_duplicate_vhost "$out_h2only" "$out_cfalpn"
  echo
done

# --- 无 SNI ---
info "[3] 无 SNI (-noservername)"
out=$(run_s_client -connect "${ORIGIN}:${PORT}" -noservername)
analyze_openssl_out "无SNI" "$out"
echo

# --- HTTP /health：直连 + HTTP/1.1 ---
safe_body() {
  local f="$1"
  local n="${2:-160}"
  if [[ -f "$f" ]]; then
    head -c "$n" "$f" | tr '\n' ' '
  else
    echo "(无输出文件，多为 TLS 后连接被重置)"
  fi
}

for name in ${NAMES}; do
  safe_name="${name//./_}"
  HEALTH_TMP="${TMPDIR:-/tmp}/_origin_health.$$.${safe_name}"
  rm -f "${HEALTH_TMP}"

  info "[4] HTTPS GET /health  (${name} → ${ORIGIN}, --http1.1, --noproxy)"
  set +e
  errf="${HEALTH_TMP}.err"
  code=$(curl --noproxy '*' -skS --http1.1 --max-time "$((TIMEOUT + 8))" -o "${HEALTH_TMP}" -w '%{http_code}' \
    --resolve "${name}:${PORT}:${ORIGIN}" "https://${name}/health" 2>"${errf}")
  cr=$?
  set -e
  if [[ "$code" == "200" ]]; then
    grn "    HTTP ${code}  body: $(safe_body "${HEALTH_TMP}" 120)"
  else
    red "    HTTP ${code:-000}  curl退出=${cr}  body: $(safe_body "${HEALTH_TMP}" 200)"
    if [[ -s "${errf}" ]]; then
      ylw "    curl 诊断: $(tr '\n' ' ' < "${errf}" | head -c 220)"
    fi
    if [[ "$code" == "525" ]]; then
      ylw "    提示: 525 为 Cloudflare 错误页；若已 --resolve 仍出现，检查透明代理/系统 VPN。"
    fi
    if [[ "$cr" != "0" ]]; then
      ylw "    若为本机到源站链路 RST：可在云服务器上执行同一脚本对比。"
    fi
  fi
  rm -f "${HEALTH_TMP}" "${errf}" 2>/dev/null || true
  echo
done

# --- 经公网 DNS 访问 Cloudflare 边缘（与 [4] 直连源 IP 对照）---
info "[5] 经 Cloudflare 边缘（https://域名/health，--noproxy，依赖本机 DNS）"
for name in "${MCP_DOMAIN}" "${WEBCHAT_DOMAIN}"; do
  cf_tmp="${TMPDIR:-/tmp}/_cf_edge.$$.${name//./_}"
  rm -f "${cf_tmp}"
  set +e
  code=$(curl --noproxy '*' -skS --http1.1 --max-time "$((TIMEOUT + 8))" -o "${cf_tmp}" -w '%{http_code}' "https://${name}/health")
  cr=$?
  set -e
  body="$(head -c 160 "${cf_tmp}" 2>/dev/null | tr '\n' ' ' || true)"
  rm -f "${cf_tmp}" 2>/dev/null || true
  if [[ "$code" == "200" ]]; then
    grn "    ${name} HTTP ${code}  ${body}"
  else
    red "    ${name} HTTP ${code:-?}  curl退出=${cr}  ${body}"
    [[ "$code" == "525" ]] && ylw "    （525：CF 与源站 TLS 握手失败，与 [4] 对比可区分边缘/源站问题）"
  fi
done
echo

ylw "--- 结果解读（若：无 SNI 成功、带 SNI 失败、curl 35）---"
ylw "在源站执行: echo | openssl s_client -connect 127.0.0.1:443 -servername ${MCP_DOMAIN} -tls1_3"
ylw "若源站正常而本机直连源 IP 异常 → 多为本机到源站链路；若 [4] 正常而 [5] 525 → 多为 Cloudflare 回源。"
ylw "排障: 确认已关闭系统代理/环境变量；换网络或在云主机上跑本脚本。"
ylw "若 nginx -T 对同一 server_name 出现多份 listen 443，且含 http2 off：删掉旧 sites-enabled 片段或合并为单份 http2 on，再 nginx -t && reload。"

info "完成。"
