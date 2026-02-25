#!/usr/bin/env sh
# 验证 Chat 服务是否正常工作（与 test_chat_router.py 的检查项一致）
# 用法: sh scripts/verify_chat_completions.sh [BASE_URL]
# 示例: sh scripts/verify_chat_completions.sh
#       sh scripts/verify_chat_completions.sh https://webchat.aio2030.fun
#       sh scripts/verify_chat_completions.sh http://localhost:8002

set -e

BASE_URL="${1:-https://webchat.aio2030.fun}"
BASE_URL="${BASE_URL%/}"

red () { echo "\033[0;31m$*\033[0m"; }
green () { echo "\033[0;32m$*\033[0m"; }
yellow () { echo "\033[1;33m$*\033[0m"; }

RESP_FILE=$(mktemp)
trap 'rm -f "$RESP_FILE"' EXIT

# 结果汇总
HEALTH_OK=0
MODELS_OK=0
CHAT_OK=0

echo "======================================================================"
echo "Chat Router 验证（参考 test_chat_router.py 检查项）"
echo "======================================================================"
echo "Service URL: $BASE_URL"
echo ""

# 1. 健康检查
echo "=== 测试健康检查 ==="
code=$(curl -s -o "$RESP_FILE" -w "%{http_code}" "$BASE_URL/health")
if [ "$code" = "200" ]; then
  green "状态码: 200"
  if [ -r "$RESP_FILE" ]; then
    echo "响应: $(head -c 200 "$RESP_FILE")"
  fi
  HEALTH_OK=1
  green "健康检查: 通过"
else
  red "状态码: $code"
  [ -r "$RESP_FILE" ] && head -c 300 "$RESP_FILE" && echo
  red "健康检查: 失败"
fi
echo ""

# 2. 模型列表
echo "=== 测试模型列表 ==="
code=$(curl -s -o "$RESP_FILE" -w "%{http_code}" "$BASE_URL/v1/models")
if [ "$code" = "200" ]; then
  green "状态码: 200"
  if command -v jq >/dev/null 2>&1; then
    echo "模型: $(jq -r '.data[].id' "$RESP_FILE" 2>/dev/null | tr '\n' ' ')"
  else
    head -c 200 "$RESP_FILE" && echo
  fi
  MODELS_OK=1
  green "模型列表: 通过"
else
  red "状态码: $code"
  [ -r "$RESP_FILE" ] && head -c 300 "$RESP_FILE" && echo
  red "模型列表: 失败"
fi
echo ""

# 3. 聊天完成 (与 Python 脚本一致: model=openclaw:main)
echo "=== 测试聊天完成 (非流式) ==="
BODY='{"model":"openclaw:main","messages":[{"role":"user","content":"hi"}],"stream":false}'
code=$(curl -s -o "$RESP_FILE" -w "%{http_code}" -X POST "$BASE_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "$BODY")
if [ "$code" = "200" ]; then
  green "状态码: 200"
  if command -v jq >/dev/null 2>&1; then
    content=$(jq -r '.choices[0].message.content // .error.message // empty' "$RESP_FILE" 2>/dev/null)
    [ -n "$content" ] && echo "AI 回复: $content"
  else
    head -c 400 "$RESP_FILE" && echo
  fi
  CHAT_OK=1
  green "聊天完成: 通过"
else
  red "状态码: $code"
  echo "响应内容:"
  head -c 400 "$RESP_FILE" && echo
  red "聊天完成: 失败"
  if [ -r "$RESP_FILE" ]; then
    err=$(head -c 500 "$RESP_FILE")
    case "$err" in
      *Failed\ to\ connect\ to\ Gateway*)
        echo ""
        yellow "提示: 健康/模型通过但聊天失败，多为 Gateway WebSocket 未连上。请确认："
        echo "  1. 已在本机执行: openclaw gateway --force"
        echo "  2. Chat Router 启动时已加载 OPENCLAW_GATEWAY_HOST/PORT/TOKEN（如 export_env_local.sh）"
        echo "  3. 查看 Chat Router 日志: tail -f .../chat_router.log"
        ;;
    esac
  fi
fi
echo ""

# 汇总（与 Python 测试总结格式一致）
echo "======================================================================"
echo "测试总结"
echo "======================================================================"
[ "$HEALTH_OK" = 1 ] && green "健康检查: ✓ 通过" || red "健康检查: ✗ 失败"
[ "$MODELS_OK" = 1 ] && green "模型列表: ✓ 通过" || red "模型列表: ✗ 失败"
[ "$CHAT_OK" = 1 ] && green "聊天完成: ✓ 通过" || red "聊天完成: ✗ 失败"
echo ""

if [ "$HEALTH_OK" = 1 ] && [ "$MODELS_OK" = 1 ] && [ "$CHAT_OK" = 1 ]; then
  green "全部通过"
  exit 0
else
  red "部分测试失败"
  exit 1
fi
