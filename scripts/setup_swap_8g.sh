#!/usr/bin/env bash
# 关闭当前 swap，删除旧 swap 文件，新建 8G swap（/swapfile）并启用
# 需要 root 执行：sudo bash setup_swap_8g.sh

set -e

SWAP_FILE="/swapfile"
SWAP_SIZE_GB=8

echo "=== 1. 关闭当前 swap ==="
if swapon --show | grep -q .; then
    swapoff -a
    echo "已关闭所有 swap"
else
    echo "当前无活跃 swap"
fi

echo ""
echo "=== 2. 删除旧 swap 文件 ==="
for old in /tmp/swapfile /swapfile; do
    if [[ -f "$old" ]]; then
        echo "删除: $old"
        rm -f "$old"
    fi
done

echo ""
echo "=== 3. 创建 ${SWAP_SIZE_GB}G swap 文件: $SWAP_FILE ==="
fallocate -l "${SWAP_SIZE_GB}G" "$SWAP_FILE"
chmod 600 "$SWAP_FILE"
mkswap "$SWAP_FILE"

echo ""
echo "=== 4. 启用新 swap ==="
swapon "$SWAP_FILE"

echo ""
echo "=== 5. 配置开机自动挂载（/etc/fstab）==="
if grep -q "^${SWAP_FILE} " /etc/fstab; then
    echo "fstab 中已存在 $SWAP_FILE 条目，跳过"
else
    # 移除本脚本管理的 swap 文件行（/swapfile、/tmp/swapfile）
    sed -i.bak -e '/^\/swapfile /d' -e '/^\/tmp\/swapfile /d' /etc/fstab 2>/dev/null || true
    echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
    echo "已添加 $SWAP_FILE 到 /etc/fstab"
fi

echo ""
echo "=== 完成 ==="
swapon --show
free -h
