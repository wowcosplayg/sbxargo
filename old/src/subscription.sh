#!/bin/bash

################################################################################
# 文件名: subscription.sh
# 功能: V2ray 订阅和 Clash 配置生成
# 依赖: base64, jq (可选)
################################################################################

################################################################################
# 函数名: generate_v2ray_subscription
# 功能: 生成 V2ray 订阅链接（base64 编码）
# 参数: $1 - jh.txt 文件路径
# 返回: 输出 base64 编码的订阅内容
################################################################################
generate_v2ray_subscription() {
    local jh_file=$1

    if [ ! -f "$jh_file" ]; then
        echo "错误: 节点文件 $jh_file 不存在" >&2
        return 1
    fi

    # 读取所有节点链接并进行 base64 编码
    cat "$jh_file" | base64 -w0
}

################################################################################
# 函数名: decode_vmess_link
# 功能: 解析 VMess 链接
# 参数: $1 - vmess:// 链接
# 返回: 输出解析后的 JSON 变量
################################################################################
decode_vmess_link() {
    local link=$1
    local b64_part="${link#vmess://}"

    # 尝试解码 base64
    local json=$(echo "$b64_part" | base64 -d 2>/dev/null)

    if [ -z "$json" ]; then
        return 1
    fi

    # 提取关键字段（兼容不同 JSON 工具）
    if command -v jq >/dev/null 2>&1; then
        # 使用 jq 解析
        vm_ps=$(echo "$json" | jq -r '.ps // ""')
        vm_add=$(echo "$json" | jq -r '.add // ""')
        vm_port=$(echo "$json" | jq -r '.port // ""')
        vm_id=$(echo "$json" | jq -r '.id // ""')
        vm_aid=$(echo "$json" | jq -r '.aid // "0"')
        vm_net=$(echo "$json" | jq -r '.net // "tcp"')
        vm_type=$(echo "$json" | jq -r '.type // "none"')
        vm_host=$(echo "$json" | jq -r '.host // ""')
        vm_path=$(echo "$json" | jq -r '.path // ""')
        vm_tls=$(echo "$json" | jq -r '.tls // ""')
        vm_sni=$(echo "$json" | jq -r '.sni // .host // ""')
        vm_alpn=$(echo "$json" | jq -r '.alpn // ""')
    else
        # 使用 grep/sed 解析（无 jq 时的备选方案）
        vm_ps=$(echo "$json" | grep -oP '"ps"\s*:\s*"\K[^"]+' || echo "")
        vm_add=$(echo "$json" | grep -oP '"add"\s*:\s*"\K[^"]+' || echo "")
        vm_port=$(echo "$json" | grep -oP '"port"\s*:\s*"\K[^"]+' || echo "")
        vm_id=$(echo "$json" | grep -oP '"id"\s*:\s*"\K[^"]+' || echo "")
        vm_aid=$(echo "$json" | grep -oP '"aid"\s*:\s*"\K[^"]+' || echo "0")
        vm_net=$(echo "$json" | grep -oP '"net"\s*:\s*"\K[^"]+' || echo "tcp")
        vm_type=$(echo "$json" | grep -oP '"type"\s*:\s*"\K[^"]+' || echo "none")
        vm_host=$(echo "$json" | grep -oP '"host"\s*:\s*"\K[^"]+' || echo "")
        vm_path=$(echo "$json" | grep -oP '"path"\s*:\s*"\K[^"]+' || echo "")
        vm_tls=$(echo "$json" | grep -oP '"tls"\s*:\s*"\K[^"]+' || echo "")
        vm_sni=$(echo "$json" | grep -oP '"sni"\s*:\s*"\K[^"]+' || echo "$vm_host")
    fi

    # 导出变量供调用者使用
    export vm_ps vm_add vm_port vm_id vm_aid vm_net vm_type vm_host vm_path vm_tls vm_sni vm_alpn
}

################################################################################
# 函数名: decode_vless_link
# 功能: 解析 VLESS 链接
# 参数: $1 - vless:// 链接
# 返回: 输出解析后的参数变量
################################################################################
decode_vless_link() {
    local link=$1

    # vless://UUID@HOST:PORT?params#name
    local uuid_part="${link#vless://}"
    local name="${uuid_part##*#}"
    uuid_part="${uuid_part%%#*}"

    local uuid="${uuid_part%%@*}"
    local addr_part="${uuid_part#*@}"

    local host="${addr_part%%:*}"
    local port_part="${addr_part#*:}"
    local port="${port_part%%\?*}"

    local params="${link#*\?}"
    params="${params%%#*}"

    # 解析参数
    vl_encryption=$(echo "$params" | grep -oP 'encryption=\K[^&]+' || echo "none")
    vl_security=$(echo "$params" | grep -oP 'security=\K[^&]+' || echo "none")
    vl_type=$(echo "$params" | grep -oP 'type=\K[^&]+' || echo "tcp")
    vl_host=$(echo "$params" | grep -oP 'host=\K[^&]+' || echo "")
    vl_path=$(echo "$params" | grep -oP 'path=\K[^&]+' || echo "")
    vl_sni=$(echo "$params" | grep -oP 'sni=\K[^&]+' || echo "$vl_host")
    vl_flow=$(echo "$params" | grep -oP 'flow=\K[^&]+' || echo "")
    vl_fp=$(echo "$params" | grep -oP 'fp=\K[^&]+' || echo "")
    vl_pbk=$(echo "$params" | grep -oP 'pbk=\K[^&]+' || echo "")
    vl_sid=$(echo "$params" | grep -oP 'sid=\K[^&]+' || echo "")
    vl_mode=$(echo "$params" | grep -oP 'mode=\K[^&]+' || echo "")

    # 导出变量
    export vl_name="$name" vl_uuid="$uuid" vl_host_addr="$host" vl_port="$port"
    export vl_encryption vl_security vl_type vl_host vl_path vl_sni vl_flow vl_fp vl_pbk vl_sid vl_mode
}

################################################################################
# 函数名: generate_clash_vmess_proxy
# 功能: 生成 VMess 协议的 Clash 代理配置
# 参数: $1 - vmess:// 链接
# 返回: 输出 YAML 格式的代理配置
################################################################################
generate_clash_vmess_proxy() {
    local link=$1

    decode_vmess_link "$link" || return 1

    # VMess 名称处理
    local name="${vm_ps:-VMess}"

    cat <<EOF
  - name: "$name"
    type: vmess
    server: $vm_add
    port: $vm_port
    uuid: $vm_id
    alterId: $vm_aid
    cipher: auto
EOF

    # 添加 TLS 配置
    if [ "$vm_tls" = "tls" ]; then
        cat <<EOF
    tls: true
    skip-cert-verify: true
EOF
        [ -n "$vm_sni" ] && echo "    servername: $vm_sni"
    fi

    # 添加传输层配置
    case "$vm_net" in
        ws)
            cat <<EOF
    network: ws
EOF
            [ -n "$vm_path" ] && echo "    ws-opts:"
            [ -n "$vm_path" ] && echo "      path: $vm_path"
            [ -n "$vm_host" ] && echo "      headers:"
            [ -n "$vm_host" ] && echo "        Host: $vm_host"
            ;;
        xhttp|http)
            # Clash Meta 支持 HTTP/2
            cat <<EOF
    network: http
EOF
            [ -n "$vm_path" ] && echo "    http-opts:"
            [ -n "$vm_path" ] && echo "      path:"
            [ -n "$vm_path" ] && echo "        - $vm_path"
            [ -n "$vm_host" ] && echo "      headers:"
            [ -n "$vm_host" ] && echo "        Host:"
            [ -n "$vm_host" ] && echo "          - $vm_host"
            ;;
        grpc)
            cat <<EOF
    network: grpc
EOF
            [ -n "$vm_path" ] && echo "    grpc-opts:"
            [ -n "$vm_path" ] && echo "      grpc-service-name: $vm_path"
            ;;
    esac
}

################################################################################
# 函数名: generate_clash_vless_proxy
# 功能: 生成 VLESS 协议的 Clash 代理配置
# 参数: $1 - vless:// 链接
# 返回: 输出 YAML 格式的代理配置
################################################################################
generate_clash_vless_proxy() {
    local link=$1

    decode_vless_link "$link" || return 1

    # VLESS 名称处理
    local name="${vl_name:-VLESS}"

    cat <<EOF
  - name: "$name"
    type: vless
    server: $vl_host_addr
    port: $vl_port
    uuid: $vl_uuid
EOF

    # TLS 配置
    if [ "$vl_security" = "tls" ] || [ "$vl_security" = "reality" ]; then
        cat <<EOF
    tls: true
    skip-cert-verify: true
EOF
        [ -n "$vl_sni" ] && echo "    servername: $vl_sni"

        # Reality 配置
        if [ "$vl_security" = "reality" ]; then
            [ -n "$vl_pbk" ] && echo "    reality-opts:"
            [ -n "$vl_pbk" ] && echo "      public-key: $vl_pbk"
            [ -n "$vl_sid" ] && echo "      short-id: $vl_sid"
        fi

        [ -n "$vl_fp" ] && echo "    client-fingerprint: $vl_fp"
    fi

    # Flow 配置（Reality 专用）
    [ -n "$vl_flow" ] && echo "    flow: $vl_flow"

    # 传输层配置
    case "$vl_type" in
        ws)
            cat <<EOF
    network: ws
EOF
            [ -n "$vl_path" ] && echo "    ws-opts:"
            [ -n "$vl_path" ] && echo "      path: $vl_path"
            [ -n "$vl_host" ] && echo "      headers:"
            [ -n "$vl_host" ] && echo "        Host: $vl_host"
            ;;
        xhttp|http)
            cat <<EOF
    network: http
EOF
            [ -n "$vl_path" ] && echo "    http-opts:"
            [ -n "$vl_path" ] && echo "      path:"
            [ -n "$vl_path" ] && echo "        - $vl_path"
            [ -n "$vl_host" ] && echo "      headers:"
            [ -n "$vl_host" ] && echo "        Host:"
            [ -n "$vl_host" ] && echo "          - $vl_host"
            ;;
        grpc)
            cat <<EOF
    network: grpc
EOF
            [ -n "$vl_path" ] && echo "    grpc-opts:"
            [ -n "$vl_path" ] && echo "      grpc-service-name: $vl_path"
            ;;
    esac
}

################################################################################
# 函数名: generate_clash_ss_proxy
# 功能: 生成 Shadowsocks 的 Clash 代理配置
# 参数: $1 - ss:// 链接
# 返回: 输出 YAML 格式的代理配置
################################################################################
generate_clash_ss_proxy() {
    local link=$1

    # ss://method:password@host:port#name
    local b64_part="${link#ss://}"
    local name="${b64_part##*#}"
    b64_part="${b64_part%%#*}"

    # 尝试直接解析或 base64 解码
    if [[ "$b64_part" == *"@"* ]]; then
        # 未编码格式
        local method_pass="${b64_part%%@*}"
        local method="${method_pass%%:*}"
        local password="${method_pass#*:}"
        local addr="${b64_part#*@}"
        local server="${addr%%:*}"
        local port="${addr#*:}"
    else
        # base64 编码格式
        local decoded=$(echo "$b64_part" | base64 -d 2>/dev/null)
        local method_pass="${decoded%%@*}"
        local method="${method_pass%%:*}"
        local password="${method_pass#*:}"
        local addr="${decoded#*@}"
        local server="${addr%%:*}"
        local port="${addr#*:}"
    fi

    cat <<EOF
  - name: "$name"
    type: ss
    server: $server
    port: $port
    cipher: $method
    password: "$password"
EOF
}

################################################################################
# 函数名: generate_clash_hysteria2_proxy
# 功能: 生成 Hysteria2 的 Clash 代理配置
# 参数: $1 - hysteria2:// 链接
# 返回: 输出 YAML 格式的代理配置
################################################################################
generate_clash_hysteria2_proxy() {
    local link=$1

    # hysteria2://password@host:port?params#name
    local pwd_part="${link#hysteria2://}"
    local name="${pwd_part##*#}"
    pwd_part="${pwd_part%%#*}"

    local password="${pwd_part%%@*}"
    local addr_part="${pwd_part#*@}"
    local host="${addr_part%%:*}"
    local port_part="${addr_part#*:}"
    local port="${port_part%%\?*}"

    local params="${link#*\?}"
    params="${params%%#*}"

    # 解析参数
    local insecure=$(echo "$params" | grep -oP 'insecure=\K[^&]+' || echo "0")
    local sni=$(echo "$params" | grep -oP 'sni=\K[^&]+' || echo "$host")

    cat <<EOF
  - name: "$name"
    type: hysteria2
    server: $host
    port: $port
    password: "$password"
    skip-cert-verify: true
EOF
    [ -n "$sni" ] && [ "$sni" != "$host" ] && echo "    sni: $sni"
}

################################################################################
# 函数名: generate_clash_tuic_proxy
# 功能: 生成 TUIC 的 Clash 代理配置
# 参数: $1 - tuic:// 链接
# 返回: 输出 YAML 格式的代理配置
################################################################################
generate_clash_tuic_proxy() {
    local link=$1

    # tuic://uuid:password@host:port?params#name
    local uuid_pwd_part="${link#tuic://}"
    local name="${uuid_pwd_part##*#}"
    uuid_pwd_part="${uuid_pwd_part%%#*}"

    local uuid="${uuid_pwd_part%%:*}"
    local pwd_addr="${uuid_pwd_part#*:}"
    local password="${pwd_addr%%@*}"
    local addr_part="${pwd_addr#*@}"
    local host="${addr_part%%:*}"
    local port_part="${addr_part#*:}"
    local port="${port_part%%\?*}"

    local params="${link#*\?}"
    params="${params%%#*}"

    local congestion=$(echo "$params" | grep -oP 'congestion_control=\K[^&]+' || echo "bbr")
    local alpn=$(echo "$params" | grep -oP 'alpn=\K[^&]+' || echo "h3")

    cat <<EOF
  - name: "$name"
    type: tuic
    server: $host
    port: $port
    uuid: $uuid
    password: "$password"
    alpn: [$alpn]
    disable-sni: false
    reduce-rtt: true
    congestion-controller: $congestion
    skip-cert-verify: true
EOF
}

################################################################################
# 函数名: generate_clash_config
# 功能: 生成完整的 Clash 配置文件
# 参数: $1 - jh.txt 文件路径
# 返回: 输出完整的 Clash YAML 配置
################################################################################
generate_clash_config() {
    local jh_file=$1

    if [ ! -f "$jh_file" ]; then
        echo "错误: 节点文件 $jh_file 不存在" >&2
        return 1
    fi

    # 生成 Clash 配置头部
    cat <<'EOF'
# Clash 配置文件
# 由 argosbx.sh 自动生成

port: 7890
socks-port: 7891
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090

dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
  fallback:
    - 8.8.8.8
    - 1.1.1.1

proxies:
EOF

    # 读取并转换每个节点
    local proxy_names=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue

        case "$line" in
            vmess://*)
                generate_clash_vmess_proxy "$line"
                decode_vmess_link "$line"
                proxy_names+=("${vm_ps:-VMess}")
                ;;
            vless://*)
                generate_clash_vless_proxy "$line"
                decode_vless_link "$line"
                proxy_names+=("${vl_name:-VLESS}")
                ;;
            ss://*)
                generate_clash_ss_proxy "$line"
                local name_part="${line##*#}"
                proxy_names+=("$name_part")
                ;;
            hysteria2://*)
                generate_clash_hysteria2_proxy "$line"
                local name_part="${line##*#}"
                proxy_names+=("$name_part")
                ;;
            tuic://*)
                generate_clash_tuic_proxy "$line"
                local name_part="${line##*#}"
                proxy_names+=("$name_part")
                ;;
        esac
    done < "$jh_file"

    # 生成代理组
    cat <<EOF

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
EOF

    for name in "${proxy_names[@]}"; do
        echo "      - \"$name\""
    done

    cat <<EOF
      - DIRECT

  - name: "AUTO"
    type: url-test
    proxies:
EOF

    for name in "${proxy_names[@]}"; do
        echo "      - \"$name\""
    done

    cat <<'EOF'
    url: 'http://www.gstatic.com/generate_204'
    interval: 300

rules:
  - DOMAIN-SUFFIX,google.com,PROXY
  - DOMAIN-KEYWORD,google,PROXY
  - DOMAIN,google.com,PROXY
  - DOMAIN-SUFFIX,youtube.com,PROXY
  - DOMAIN-SUFFIX,github.com,PROXY
  - DOMAIN-SUFFIX,githubusercontent.com,PROXY
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF
}

################################################################################
# 函数名: save_subscription_files
# 功能: 保存订阅文件到指定目录
# 参数:
#   $1 - jh.txt 文件路径
#   $2 - 输出目录（可选，默认为 $HOME/agsbx）
# 返回: 0=成功 1=失败
################################################################################
save_subscription_files() {
    local jh_file=$1
    local output_dir="${2:-$HOME/agsbx}"

    if [ ! -f "$jh_file" ]; then
        echo "错误: 节点文件 $jh_file 不存在"
        return 1
    fi

    mkdir -p "$output_dir"

    # 生成 V2ray 订阅
    echo "正在生成 V2ray 订阅..."
    generate_v2ray_subscription "$jh_file" > "$output_dir/v2ray_sub.txt"

    if [ $? -eq 0 ]; then
        echo "✓ V2ray 订阅已保存: $output_dir/v2ray_sub.txt"
    else
        echo "✗ V2ray 订阅生成失败"
        return 1
    fi

    # 生成 Clash 配置
    echo "正在生成 Clash 配置..."
    generate_clash_config "$jh_file" > "$output_dir/clash.yaml"

    if [ $? -eq 0 ]; then
        echo "✓ Clash 配置已保存: $output_dir/clash.yaml"
    else
        echo "✗ Clash 配置生成失败"
        return 1
    fi

    echo ""
    echo "订阅文件生成完成！"
    echo ""
    echo "V2ray 订阅内容（base64）:"
    echo "  文件: $output_dir/v2ray_sub.txt"
    echo "  使用: 复制文件内容到 V2ray 客户端订阅地址"
    echo ""
    echo "Clash 配置文件:"
    echo "  文件: $output_dir/clash.yaml"
    echo "  使用: 复制到 Clash 配置目录或导入客户端"
    echo ""

    return 0
}
