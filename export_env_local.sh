#!/bin/bash

# =============================================================================
# AIO-Pod 本地环境配置文件
# 由配置向导自动生成于: 2026年 2月 7日 星期六 15时34分44秒 CST
# =============================================================================

# =============================================================================
# OpenClaw Gateway 配置 - Chat Router 服务需要
# =============================================================================

# OpenClaw Gateway 地址
export OPENCLAW_GATEWAY_HOST="127.0.0.1"

# OpenClaw Gateway 端口
export OPENCLAW_GATEWAY_PORT="18789"

# OpenClaw Gateway 认证 Token
export OPENCLAW_GATEWAY_TOKEN="sk-lm-gyXsWZIS:opqYGydrY8dwynxrZNT6"

# 默认 Agent ID
export OPENCLAW_DEFAULT_AGENT="main"

# Chat Router 服务端口
export CHAT_ROUTER_PORT="8002"

# =============================================================================
# 腾讯云配置 - 根据需要配置
# =============================================================================

# IoT 角色 ARN
export IOT_ROLE_ARN="${IOT_ROLE_ARN:-qcs::cam::uin/YOUR_UIN:roleName/YOUR_ROLE_NAME}"

# 腾讯云访问凭证
export TC_SECRET_ID="${TC_SECRET_ID:-YOUR_SECRET_ID}"
export TC_SECRET_KEY="${TC_SECRET_KEY:-YOUR_SECRET_KEY}"

# COS 对象存储配置
export COS_OWNER_UIN="${COS_OWNER_UIN:-YOUR_UIN}"
export COS_BUCKET_NAME="${COS_BUCKET_NAME:-your-bucket-name}"
export COS_REGION="${COS_REGION:-ap-guangzhou}"
export COS_BUCKET="${COS_BUCKET:-pixelmug-assets}"

# 通用配置
export DEFAULT_REGION="${DEFAULT_REGION:-ap-guangzhou}"
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
