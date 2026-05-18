#!/usr/bin/env bash
# 对照「同一 IP:443、不同 SNI」的 TLS 握手，排查路径上是否按 SNI 做选择性拦截（DPI/防火墙等）。
# 若 www.example.com 能完成握手，而业务域名在 ClientHello 后即 RST/EOF，则高度怀疑路径策略而非源站「不认 SNI」。
#
# 用法:
#   bash scripts/diag_sni_path.sh
#   bash scripts/diag_sni_path.sh 8.141.81.75
# 经 HTTP 代理 CONNECT（openssl s_client -proxy）:
#   HTTPS_PROXY=http://127.0.0.1:7890 bash scripts/diag_sni_path.sh 8.141.81.75
# LibreSSL 要求 -proxy 为「host:port」，脚本会自动去掉 http(s):// 前缀；勿把「# 或」整行粘进终端。
#
# 依赖: openssl（macOS 自带）、perl（合并 Session-ID/Master-Key 续行）、可选 timeout/gtimeout。
# 展示 openssl 尾部时从「最后一个 SSL-Session:」起截取约 42 行（DIAG_OPENSSL_TAIL_SPAN 可改），避免 tail 落在 ticket 十六进制里看不到已合并的 Session-ID。

set -uo pipefail

IP="${1:-8.141.81.75}"
TIMEOUT="${DIAG_TLS_TIMEOUT:-10}"
PROXY="${HTTPS_PROXY:-${https_proxy:-${ALL_PROXY:-${all_proxy:-}}}}"

# openssl/LibreSSL 的 -proxy 仅支持 HTTP CONNECT，且格式为 host:port（带 http:// 会报 malformed）。
openssl_proxy_hostport() {
  local raw="$1"
  case "$raw" in
    socks5://*|socks://*|socks4://*)
      printf '%s\n' "diag_sni_path: SOCKS 代理不能用于 openssl -proxy；请仅用 HTTP，例如: HTTPS_PROXY=http://127.0.0.1:7890" >&2
      return 1
      ;;
  esac
  raw="${raw#http://}"
  raw="${raw#https://}"
  raw="${raw%/}"
  printf '%s' "$raw"
}

OSSL_PROXY=""
if [[ -n "$PROXY" ]]; then
  OSSL_PROXY=$(openssl_proxy_hostport "$PROXY") || exit 2
fi

have_timeout() { command -v timeout >/dev/null 2>&1; }

# 去掉 session ticket 大块十六进制，避免窄终端折行看起来像「重复输出」
strip_ticket_hex() {
  grep -vE '^[[:space:]]+[0-9a-f]{4}[[:space:]]+-[[:space:]]+[0-9a-f]{2}' || true
}

# LibreSSL 常把长 Session-ID / Master-Key 拆成两行且第二行重复第一行十六进制前缀（两行都带标签）。
# 用 Perl 多行替换比 awk 状态机更稳；允许两行之间有空行。
merge_ssl_long_lines() {
  if command -v perl >/dev/null 2>&1; then
    perl -e '
      undef $/;
      $_ = <>;
      while (
        s/([\t ]+Session-ID\s*:\s*([0-9a-fA-F]+))\s*\n[\t ]+Session-ID\s*:\s*\2([0-9a-fA-F]*)/    Session-ID: $2$3/g
      ) { }
      while (
        s/([\t ]+Master-Key\s*:\s*([0-9a-fA-F]+))\s*\n[\t ]+Master-Key\s*:\s*\2([0-9a-fA-F]*)/    Master-Key: $2$3/g
      ) { }
      print;
    '
  else
    awk '
      /^[[:space:]]+Session-ID:[[:space:]]/ && $0 !~ /Session-ID-ctx/ {
        if (mk != "") { print "    Master-Key: " mk; mk = "" }
        sub(/^[[:space:]]+Session-ID:[[:space:]]*/, "")
        if (sid != "") { print "    Session-ID: " sid $0; sid = ""; next }
        sid = $0
        next
      }
      /^[[:space:]]+Master-Key:[[:space:]]/ {
        if (sid != "") { print "    Session-ID: " sid; sid = "" }
        sub(/^[[:space:]]+Master-Key:[[:space:]]*/, "")
        if (mk != "") { print "    Master-Key: " mk $0; mk = ""; next }
        mk = $0
        next
      }
      /^[[:space:]]*$/ {
        if (sid != "" || mk != "") next
        print
        next
      }
      {
        if (sid != "") { print "    Session-ID: " sid; sid = "" }
        if (mk != "") { print "    Master-Key: " mk; mk = "" }
        print
      }
      END {
        if (sid != "") print "    Session-ID: " sid
        if (mk != "") print "    Master-Key: " mk
      }
    '
  fi
}

# 从「最后一个 SSL-Session:」起截取约 40 行，避免 tail 落在 ticket 十六进制里看不到已合并的 Session-ID
show_openssl_session_tail() {
  awk -v span="${DIAG_OPENSSL_TAIL_SPAN:-42}" '
    { a[++n] = $0 }
    /^SSL-Session:/ { ss = n }
    END {
      if (ss) {
        e = ss + span - 1
        if (e > n) e = n
        for (i = ss; i <= e; i++) print a[i]
      } else {
        s = n - 24
        if (s < 1) s = 1
        for (i = s; i <= n; i++) print a[i]
      }
    }
  '
}

run_s_client() {
  local sni="$1"
  if [[ -n "$OSSL_PROXY" ]]; then
    if have_timeout; then
      timeout "${TIMEOUT}" openssl s_client -proxy "$OSSL_PROXY" -connect "${IP}:443" -servername "$sni" -tls1_2 </dev/null 2>&1
    else
      openssl s_client -proxy "$OSSL_PROXY" -connect "${IP}:443" -servername "$sni" -tls1_2 </dev/null 2>&1
    fi
  else
    if have_timeout; then
      timeout "${TIMEOUT}" openssl s_client -connect "${IP}:443" -servername "$sni" -tls1_2 </dev/null 2>&1
    else
      openssl s_client -connect "${IP}:443" -servername "$sni" -tls1_2 </dev/null 2>&1
    fi
  fi
}

summarize() {
  local out="$1"
  local hr
  if echo "$out" | grep -qE 'Cipher is \(NONE\)'; then
    hr=$(echo "$out" | grep -oE 'read [0-9]+ bytes' | head -1 | grep -oE '[0-9]+' || true)
    hw=$(echo "$out" | grep -oE 'written [0-9]+ bytes' | head -1 | grep -oE '[0-9]+' || true)
    printf '  结果: TLS 未完成；read=%s written=%s；Cipher (NONE)。\n' "${hr:-?}" "${hw:-?}"
    printf '  提示: example 段若成功 → 与「按 SNI 拦」对照。\n'
  elif echo "$out" | grep -qE 'SSL handshake has read 0 bytes'; then
    printf '  结果: TLS 未完成（read=0）。\n'
    printf '  提示: example 段若成功 → 与「按 SNI 拦」对照。\n'
  elif echo "$out" | grep -qE 'Verify return code: 0' && echo "$out" | grep -qE 'BEGIN CERTIFICATE|Server certificate'; then
    printf '  结果: 握手完成且证书链校验为 0（路径对该 SNI 未明显拦断）\n'
  elif echo "$out" | grep -qE 'BEGIN CERTIFICATE'; then
    printf '  结果: 收到证书但 verify 非 0，见上方 Verify return code\n'
  elif echo "$out" | grep -qiE 'CONNECTION RESET|broken pipe|EOF occurred|shutdown while in init|errno=54'; then
    printf '  结果: 连接早期被 RST/断开（与按 SNI 拦一致时需对照中性 SNI 是否稳定成功）\n'
  else
    printf '  结果: 未能归类，请人工扫上方 openssl 输出\n'
  fi
}

echo "目标: ${IP}:443"
if [[ -n "$OSSL_PROXY" ]]; then
  echo "代理: ${OSSL_PROXY}（openssl -proxy）"
else
  echo "模式: 直连"
fi
[[ -n "$PROXY" ]] && echo "环境: ${PROXY}"
echo ""

for sni in www.example.com mcp.univoices.club webchat.univoices.club; do
  printf '=== SNI=%s ===\n' "$sni"
  out=$(run_s_client "$sni" || true)
  echo "$out" | tr -d '\r' | strip_ticket_hex | merge_ssl_long_lines | show_openssl_session_tail
  summarize "$out"
  echo ""
done

echo "解读:"
echo "  · example 成、业务败："
echo "    疑路径按 SNI 关键字拦（非 Nginx 未配 server_name）。"
echo "  · 三段皆败：换网络再测。"
echo "  · curl --resolve:"
echo "      curl -vk --resolve mcp.univoices.club:443:${IP} \\"
echo "        https://mcp.univoices.club/health"
