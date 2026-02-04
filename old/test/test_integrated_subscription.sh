#!/bin/bash
# 测试集成到主脚本的订阅功能

set -e

echo "============================================"
echo "测试 argosbx.sh 集成的订阅功能"
echo "============================================"
echo

# 创建测试目录和节点文件
TEST_DIR="/tmp/argosbx_sub_test"
mkdir -p "$TEST_DIR"

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

echo "[2/3] 提取订阅函数..."
# 从主脚本提取订阅函数
awk '/^generate_v2ray_subscription\(\)/,/^}$/ {print}
     /^decode_vmess_link\(\)/,/^}$/ {print}
     /^decode_vless_link\(\)/,/^}$/ {print}
     /^generate_clash_vmess_proxy\(\)/,/^}$/ {print}
     /^generate_clash_vless_proxy\(\)/,/^}$/ {print}
     /^generate_clash_ss_proxy\(\)/,/^}$/ {print}
     /^generate_clash_hysteria2_proxy\(\)/,/^}$/ {print}
     /^generate_clash_tuic_proxy\(\)/,/^}$/ {print}
     /^generate_clash_config\(\)/,/^}$/ {print}
     /^save_subscription_files\(\)/,/^}$/ {print}' argosbx.sh > "$TEST_DIR/sub_functions.sh"

echo "✓ 函数已提取 ($(wc -l < "$TEST_DIR/sub_functions.sh") 行)"
echo

echo "[3/3] 测试订阅生成..."
source "$TEST_DIR/sub_functions.sh"
save_subscription_files "$TEST_DIR/jh.txt" "$TEST_DIR"

echo
echo "============================================"
echo "测试完成！"
echo "============================================"
echo

if [ -f "$TEST_DIR/v2ray_sub.txt" ] && [ -f "$TEST_DIR/clash.yaml" ]; then
    echo "✓ V2ray 订阅: $TEST_DIR/v2ray_sub.txt ($(wc -c < "$TEST_DIR/v2ray_sub.txt") bytes)"
    echo "✓ Clash 配置: $TEST_DIR/clash.yaml ($(wc -l < "$TEST_DIR/clash.yaml") lines)"
    echo
    echo "V2ray 订阅解码预览:"
    echo "---------------------------------------------------------"
    cat "$TEST_DIR/v2ray_sub.txt" | base64 -d | head -2
    echo "..."
    echo
    echo "Clash 配置预览:"
    echo "---------------------------------------------------------"
    head -30 "$TEST_DIR/clash.yaml"
    echo "..."
    echo
    echo "✓ 所有测试通过！订阅功能已成功集成到 argosbx.sh"
else
    echo "✗ 测试失败：订阅文件未生成"
    exit 1
fi

# 清理
rm -rf "$TEST_DIR"
echo "测试文件已清理"
