#!/bin/bash
# ============================================================================
# 订阅功能测试脚本
# 用法: bash test_subscription.sh
# ============================================================================

set -e

echo "============================================"
echo "订阅功能测试"
echo "============================================"
echo

# 测试目录
TEST_DIR="$HOME/agsbx_test"
mkdir -p "$TEST_DIR"

# 创建测试节点文件
cat > "$TEST_DIR/jh.txt" <<'EOF'
vmess://eyJ2IjoiMiIsInBzIjoidGVzdC12bWVzcy14aHR0cCIsImFkZCI6InRlc3QuY29tIiwicG9ydCI6IjQ0MyIsImlkIjoidGVzdC11dWlkLTEyMzQiLCJhaWQiOiIwIiwibmV0IjoieGh0dHAiLCJ0eXBlIjoibm9uZSIsImhvc3QiOiJ0ZXN0LmNvbSIsInBhdGgiOiIvdm1lc3MtcGF0aCIsInRscyI6InRscyIsInNuaSI6InRlc3QuY29tIn0=
vless://test-uuid-5678@test.example.com:443?encryption=none&security=tls&type=xhttp&host=test.example.com&path=/vless-path&sni=test.example.com&mode=packet-up#test-vless-xhttp
ss://MjAyMi1ibGFrZTMtYWVzLTEyOC1nY206dGVzdC1wYXNzd29yZA==@test.ss.com:8388#test-ss-2022
hysteria2://test-password@test.hy2.com:8443?insecure=1&sni=test.hy2.com#test-hysteria2
tuic://test-uuid-9999:test-tuic-pass@test.tuic.com:8443?congestion_control=bbr&alpn=h3#test-tuic5
EOF

echo "[1/3] 测试节点文件已创建"
echo "节点数量: $(wc -l < "$TEST_DIR/jh.txt")"
echo

echo "[2/3] 加载订阅生成模块..."
if [ -f "src/subscription.sh" ]; then
    source src/subscription.sh
    echo "✓ 模块加载成功 (src/subscription.sh)"
elif [ -f "D:/project/a/src/subscription.sh" ]; then
    source "D:/project/a/src/subscription.sh"
    echo "✓ 模块加载成功 (D:/project/a/src/subscription.sh)"
else
    echo "✗ 找不到订阅生成模块"
    exit 1
fi

echo
echo "[3/3] 生成订阅文件..."
save_subscription_files "$TEST_DIR/jh.txt" "$TEST_DIR"

echo
echo "============================================"
echo "测试完成！"
echo "============================================"
echo
echo "生成的文件:"
echo "  V2ray 订阅: $TEST_DIR/v2ray_sub.txt"
echo "  Clash 配置: $TEST_DIR/clash.yaml"
echo
echo "验证 V2ray 订阅 (base64 解码):"
echo "---------------------------------------------------------"
if [ -f "$TEST_DIR/v2ray_sub.txt" ]; then
    cat "$TEST_DIR/v2ray_sub.txt" | base64 -d | head -5
    echo "..."
    echo "(共 $(cat "$TEST_DIR/v2ray_sub.txt" | base64 -d | wc -l) 行)"
fi
echo

echo "验证 Clash 配置 (前 50 行):"
echo "---------------------------------------------------------"
if [ -f "$TEST_DIR/clash.yaml" ]; then
    head -50 "$TEST_DIR/clash.yaml"
    echo "..."
    echo "(共 $(wc -l < "$TEST_DIR/clash.yaml") 行)"
fi
echo

echo "清理测试文件:"
read -p "是否删除测试目录 $TEST_DIR? (y/n): " confirm
if [ "$confirm" = "y" ]; then
    rm -rf "$TEST_DIR"
    echo "✓ 测试目录已删除"
else
    echo "保留测试文件供手动检查"
fi
