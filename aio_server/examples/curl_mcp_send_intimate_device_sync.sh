#!/usr/bin/env bash
#
# 通过 HTTP 调用已上传 MCP 的 JSON-RPC（服务端逻辑见 app/services/exec_service.py::execute_json_rpc）
#
# 用法:
#   ./curl_mcp_send_intimate_device_sync.sh
#   MCP_FILENAME 默认 mcp_pixelmug.bin；覆盖示例: export MCP_FILENAME=其它.mcp
#
# 可选环境变量:
#   AIO_SERVICE_URL  默认 http://localhost:8000（与 examples/client.py 一致）
#   RPC_TIMEOUT      查询参数 timeout，默认 120（秒）
#   MCP_FILENAME     默认 mcp_pixelmug.bin
#
# MCP_FILENAME 应与「上传后的文件名」一致，可用: python client.py list mcp
# 服务端解析规则见 app/api/routes.py（MCP 会尝试 .bin 等路径）。

set -euo pipefail

BASE_URL="${AIO_SERVICE_URL:-http://localhost:8000}"
RPC_TIMEOUT="${RPC_TIMEOUT:-120}"
MCP_FILENAME="${MCP_FILENAME:-mcp_pixelmug.bin}"

# 与 exec_service 中 json.dumps(..., separators=(',', ':')) 等价的紧凑 JSON
REQUEST2='{"jsonrpc":"2.0","method":"send_intimate_device_sync","params":{"product_id":"H3PI4FBTV5","device_name":"mug_001","ack":""},"id":2}'

URL="${BASE_URL}/api/v1/rpc/mcp/${MCP_FILENAME}?timeout=${RPC_TIMEOUT}"

echo "POST ${URL}" >&2
echo "Body: ${REQUEST2}" >&2

if command -v jq >/dev/null 2>&1; then
  curl -sS -X POST "${URL}" \
    -H "Content-Type: application/json" \
    -d "${REQUEST2}" | jq .
else
  curl -sS -X POST "${URL}" \
    -H "Content-Type: application/json" \
    -d "${REQUEST2}"
  echo
fi
