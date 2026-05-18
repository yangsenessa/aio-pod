#!/usr/bin/env bash
# 重新登录 Qwen Portal OAuth（设备码流程，需在「真实终端」里运行，不能用管道/后台）。
# 必须以 mixlab 用户执行（勿用 root；否则会读错 ~/.openclaw）。
# 用法：
#   su - mixlab
#   /home/mixlab/openclaw/reauth-qwen.sh
# 按提示在浏览器打开链接并输入用户码；完成后建议重启 gateway 使会话加载新凭证。

set -euo pipefail

REQUIRED_USER="mixlab"
if [[ "$(id -un)" != "${REQUIRED_USER}" ]]; then
  echo "错误：本脚本必须由用户 ${REQUIRED_USER} 执行。当前用户: $(id -un)" >&2
  echo "示例: su - ${REQUIRED_USER} -c '/home/mixlab/openclaw/reauth-qwen.sh'" >&2
  exit 1
fi

# 始终优先使用该用户 npm 全局安装的 CLI，避免 PATH 里另有 openclaw 导致版本/插件不一致
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
cd "${HOME}"

if [[ ! -d "${HOME}/.openclaw" ]]; then
  echo "错误：未找到 ${HOME}/.openclaw，请先在该用户下完成 OpenClaw 初始化。" >&2
  exit 1
fi

if [[ ! -t 0 ]]; then
  echo "错误：请在交互式终端中运行本脚本（需要 TTY）。例如：ssh 登录后直接执行，不要用管道重定向。" >&2
  exit 1
fi

exec "${OPENCLAW_BIN}" models auth login --provider qwen-portal --set-default --method device
