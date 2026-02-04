#!/bin/bash
# ============================================================================
# XHTTP + Argo 兼容性测试脚本
# 用法: bash xhttp_argo_test.sh
# ============================================================================

set -e

echo "============================================"
echo "XHTTP + Argo 兼容性测试"
echo "============================================"
echo

# 配置变量
TEST_UUID="${TEST_UUID:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen || echo 'test-uuid-1234')}"
TEST_PORT="${TEST_PORT:-8080}"
XHTTP_PATH="${XHTTP_PATH:-/vmess-xhttp}"
XHTTP_MODE="${XHTTP_MODE:-packet-up}"  # packet-up 对 CDN 兼容性最好

echo "[1/5] 检查 Xray 版本..."
if [ -f "$HOME/agsbx/xray" ]; then
    XRAY_VERSION=$("$HOME/agsbx/xray" version 2>/dev/null | head -1)
    echo "Xray 版本: $XRAY_VERSION"
else
    echo "错误: 未找到 Xray，请先安装"
    exit 1
fi

echo
echo "[2/5] 生成服务端配置 (XHTTP mode=$XHTTP_MODE)..."
cat > "$HOME/agsbx/xr_xhttp_test.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vmess-xhttp-argo",
      "listen": "::",
      "port": ${TEST_PORT},
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${TEST_UUID}"
          }
        ]
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "${XHTTP_PATH}",
          "mode": "${XHTTP_MODE}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF
echo "配置已写入: $HOME/agsbx/xr_xhttp_test.json"

echo
echo "[3/5] 验证配置语法..."
if "$HOME/agsbx/xray" run -test -c "$HOME/agsbx/xr_xhttp_test.json" 2>&1; then
    echo "✓ 配置语法正确"
else
    echo "✗ 配置语法错误"
    exit 1
fi

echo
echo "[4/5] 启动测试服务..."
# 停止可能存在的测试进程
pkill -f "xr_xhttp_test.json" 2>/dev/null || true
sleep 1

# 启动 Xray
nohup "$HOME/agsbx/xray" run -c "$HOME/agsbx/xr_xhttp_test.json" > "$HOME/agsbx/xhttp_test.log" 2>&1 &
XRAY_PID=$!
sleep 2

if kill -0 $XRAY_PID 2>/dev/null; then
    echo "✓ Xray 已启动 (PID: $XRAY_PID)"
else
    echo "✗ Xray 启动失败，查看日志:"
    cat "$HOME/agsbx/xhttp_test.log"
    exit 1
fi

echo
echo "[5/5] 启动 Argo 临时隧道..."
if [ -f "$HOME/agsbx/cloudflared" ]; then
    pkill -f "cloudflared.*${TEST_PORT}" 2>/dev/null || true
    sleep 1

    nohup "$HOME/agsbx/cloudflared" tunnel --url http://localhost:${TEST_PORT} \
        --edge-ip-version auto --no-autoupdate --protocol http2 \
        > "$HOME/agsbx/argo_xhttp_test.log" 2>&1 &

    echo "等待 Argo 隧道建立..."
    sleep 10

    ARGO_DOMAIN=$(grep -a trycloudflare.com "$HOME/agsbx/argo_xhttp_test.log" 2>/dev/null | \
        awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')

    if [ -n "$ARGO_DOMAIN" ]; then
        echo "✓ Argo 隧道已建立"
        echo
        echo "============================================"
        echo "测试环境就绪！"
        echo "============================================"
        echo
        echo "服务端配置:"
        echo "  - 协议: VMess"
        echo "  - 传输: XHTTP (mode=${XHTTP_MODE})"
        echo "  - 端口: ${TEST_PORT}"
        echo "  - 路径: ${XHTTP_PATH}"
        echo "  - UUID: ${TEST_UUID}"
        echo
        echo "Argo 隧道域名: ${ARGO_DOMAIN}"
        echo
        echo "客户端配置 (Xray):"
        cat <<CLIENTEOF
{
  "outbounds": [{
    "protocol": "vmess",
    "settings": {
      "vnext": [{
        "address": "${ARGO_DOMAIN}",
        "port": 443,
        "users": [{"id": "${TEST_UUID}"}]
      }]
    },
    "streamSettings": {
      "network": "xhttp",
      "security": "tls",
      "tlsSettings": {
        "serverName": "${ARGO_DOMAIN}",
        "fingerprint": "chrome"
      },
      "xhttpSettings": {
        "path": "${XHTTP_PATH}",
        "mode": "${XHTTP_MODE}"
      }
    }
  }]
}
CLIENTEOF
        echo
        echo "VMess 链接 (XHTTP-TLS-Argo):"
        echo "vmess://$(echo "{ \"v\": \"2\", \"ps\": \"XHTTP-Argo-Test\", \"add\": \"${ARGO_DOMAIN}\", \"port\": \"443\", \"id\": \"${TEST_UUID}\", \"aid\": \"0\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"${ARGO_DOMAIN}\", \"path\": \"${XHTTP_PATH}\", \"tls\": \"tls\", \"sni\": \"${ARGO_DOMAIN}\" }" | base64 -w0)"
        echo
        echo "测试命令:"
        echo "  curl -x socks5://127.0.0.1:1080 https://www.google.com"
        echo
        echo "停止测试:"
        echo "  pkill -f 'xr_xhttp_test.json'; pkill -f 'cloudflared.*${TEST_PORT}'"
    else
        echo "✗ Argo 隧道建立失败"
        echo "日志内容:"
        cat "$HOME/agsbx/argo_xhttp_test.log"
        exit 1
    fi
else
    echo "未找到 cloudflared，跳过 Argo 测试"
    echo
    echo "本地测试配置已就绪:"
    echo "  - 端口: ${TEST_PORT}"
    echo "  - UUID: ${TEST_UUID}"
    echo "  - 路径: ${XHTTP_PATH}"
fi
