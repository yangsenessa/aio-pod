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

# --- 每个 SNI：TLS1.3 / TLS1.2 / 默认 ---
for name in ${NAMES}; do
  info "[2] SNI=${name}  (TLS 1.3)"
  out=$(echo | with_timeout "${TIMEOUT}" openssl s_client -connect "${ORIGIN}:${PORT}" -servername "${name}" -tls1_3 2>&1) || true
  analyze_openssl_out "TLS1.3" "$out"
  echo

  info "[2b] SNI=${name}  (TLS 1.2, ECDHE-RSA-AES256-GCM-SHA384)"
  out=$(echo | with_timeout "${TIMEOUT}" openssl s_client -connect "${ORIGIN}:${PORT}" -servername "${name}" -tls1_2 \
    -cipher 'ECDHE-RSA-AES256-GCM-SHA384' 2>&1) || true
  analyze_openssl_out "TLS1.2" "$out"
  echo

  info "[2c] SNI=${name}  (openssl 默认协议，不强制 -tls1_2/3)"
  out=$(echo | with_timeout "${TIMEOUT}" openssl s_client -connect "${ORIGIN}:${PORT}" -servername "${name}" 2>&1) || true
  analyze_openssl_out "默认" "$out"
  echo
done

# --- 无 SNI ---
info "[3] 无 SNI (-noservername)"
out=$(echo | with_timeout "${TIMEOUT}" openssl s_client -connect "${ORIGIN}:${PORT}" -noservername 2>&1) || true
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

info "完成。"
