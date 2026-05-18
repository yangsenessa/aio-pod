#!/usr/bin/env bash
# 在源站抓取「入站 :443」报文，用于对照 Cloudflare 回源 TLS 握手（排查 525 等）
#
# 用法（必须在源站本机、root）:
#   sudo IFACE=eth0 DURATION=60 bash scripts/capture_cf_origin_tls.sh
# 另开一终端或从外网执行，触发 CF 回源:
#   curl -sS --noproxy '*' "https://${MCP_DOMAIN}/health"
#
# 抓包结束后本脚本会尝试用 tshark 列出 ClientHello 的源 IP 与 SNI（若已安装 tshark）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/domain_constants.sh
source "${ROOT}/scripts/domain_constants.sh"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  printf '请用 root 运行: sudo bash %s\n' "$0" >&2
  exit 1
fi

need() { command -v "$1" >/dev/null 2>&1 || { printf '缺少命令: %s\n' "$1" >&2; exit 1; }; }
need tcpdump

IFACE="${IFACE:-any}"
DURATION="${DURATION:-45}"
OUT="${PCAP:-/tmp/cf-origin-443-$(date +%Y%m%d-%H%M%S).pcap}"

# 双向抓 443（含源站发出的 ServerHello；仅用 dst 443 会漏掉回包导致误判）
FILTER='tcp port 443'

printf '\n======== 源站抓包（Cloudflare 回源 TLS）========\n'
printf '网卡: %s  时长: %ss  文件: %s\n' "$IFACE" "$DURATION" "$OUT"
printf 'BPF: %s\n\n' "$FILTER"
printf '请在 %s 秒内从外网触发经 Cloudflare 的请求，例如:\n' "$DURATION"
printf '  curl -sS --noproxy '\''*'\'' "https://%s/health"\n' "${MCP_DOMAIN}"
printf '  curl -sS --noproxy '\''*'\'' "https://%s/health"\n\n' "${WEBCHAT_DOMAIN}"
printf '开始 tcpdump …\n\n'

tcpdump -i "$IFACE" -s 0 -nn -w "$OUT" "$FILTER" &
TPID=$!

cleanup() {
  kill -INT "${TPID}" 2>/dev/null || true
  wait "${TPID}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep "${DURATION}"
cleanup
trap - EXIT INT TERM

if [[ ! -s "$OUT" ]]; then
  printf '未写入数据或文件为空: %s\n' "$OUT" >&2
  exit 1
fi

printf '\n已写入: %s  大小: %s\n' "$OUT" "$(du -h "$OUT" | awk '{print $1}')"

if command -v tshark >/dev/null 2>&1; then
  printf '\n--- 入站 TCP:443 对话（对端 IP，按帧数排序）---\n'
  tshark -r "$OUT" -q -z conv,tcp 2>/dev/null | head -40 || true

  printf '\n--- TLS ClientHello：源 IP 与 SNI（若有）---\n'
  tshark -r "$OUT" -Y 'tls.handshake.type == 1' -T fields \
    -e frame.number -e ip.src -e ipv6.src \
    -e tls.handshake.extensions_server_name 2>/dev/null | head -50 || true

  printf '\n--- 若需看某条流的握手详情（把 1.2.3.4 换成上表中的源 IP）---\n'
  printf 'tshark -r %s -Y "ip.src==1.2.3.4 && tcp.port==443" -V | less\n' "$OUT"
else
  printf '\n未安装 tshark，可: apt-get install -y tshark  或 将 pcap 拷到本机用 Wireshark 打开。\n'
  printf 'Wireshark 显示过滤器示例: tcp.dstport==443 && tls.handshake.type==1\n'
fi

printf '\n完成。\n'
