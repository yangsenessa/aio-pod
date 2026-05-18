#!/usr/bin/env bash
# 启动 openclaw gateway 到后台，日志重定向到 /home/mixlab/openclaw/logs
# 必须以 mixlab 用户执行（勿用 root；否则 gateway 进程环境与凭证目录不一致）。

set -euo pipefail

REQUIRED_USER="mixlab"
if [[ "$(id -un)" != "${REQUIRED_USER}" ]]; then
  echo "错误：本脚本必须由用户 ${REQUIRED_USER} 执行。当前用户: $(id -un)" >&2
  echo "示例: su - ${REQUIRED_USER} -c '/home/mixlab/openclaw/start-gateway.sh'" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_BIN="${HOME}/.npm-global/bin/openclaw"
if [[ -x "${OPENCLAW_BIN}" ]]; then
  :
else
  export PATH="${HOME}/.npm-global/bin:${PATH:-}"
  if ! command -v openclaw &>/dev/null; then
    echo "错误：未找到 openclaw，请先在该用户下执行: npm i -g openclaw" >&2
    exit 1
  fi
  OPENCLAW_BIN="openclaw"
fi

# 在启动前注入 ~/.openclaw/.env，确保 nohup 子进程能解析配置里的 ${DASHSCOPE_API_KEY} 等变量
#（仅依赖 OpenClaw 内部 loadDotEnv 时，部分环境下会出现 MissingEnvVarError）
ENV_FILE="${HOME}/.openclaw/.env"
if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/gateway.log"
PID_FILE="${SCRIPT_DIR}/gateway.pid"

mkdir -p "$LOG_DIR"

if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "gateway 已在运行 (PID: $OLD_PID)，如需重启请先执行: kill $OLD_PID"
    exit 1
  fi
  rm -f "$PID_FILE"
fi

nohup "${OPENCLAW_BIN}" gateway --force >> "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
echo "openclaw gateway 已启动到后台，PID: $(cat "$PID_FILE")"
echo "日志文件: $LOG_FILE"
