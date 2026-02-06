#!/bin/bash

# ============================================================================
# Utils Module for Argosbx
# Contains shared functions: Logging, Port config, Link generation
# ============================================================================

# Logging Functions
log_info() {
    echo -e "\033[32m[INFO] $1\033[0m"
}

log_error() {
    echo -e "\033[31m[ERROR] $1\033[0m" >&2
}

log_warn() {
    echo -e "\033[33m[WARN] $1\033[0m"
}


# ============================================================================
# System Information & IP
# ============================================================================

get_server_ip() {
    # Check if manual override IP exists (from Env or Config)
    if [ -n "$ippz" ]; then
        log_info "使用预设 IP: $ippz"
        echo "$ippz" > "$HOME/agsbx/server_ip.log"
        return
    fi

    log_info "正在获取服务器 IP..."
    local ip=""
    
    # Try IPv4 first
    ip=$(curl -s4m5 https://api.ipify.org)
    [ -z "$ip" ] && ip=$(curl -s4m5 https://ipv4.icanhazip.com)
    [ -z "$ip" ] && ip=$(curl -s4m5 https://ifconfig.me)
    [ -z "$ip" ] && ip=$(curl -s4m5 https://checkip.amazonaws.com)
    
    # Try IPv6 if IPv4 fails
    if [ -z "$ip" ]; then
        ip=$(curl -s6m5 https://api64.ipify.org)
    fi
    
    if [ -n "$ip" ]; then
        echo "$ip" > "$HOME/agsbx/server_ip.log"
        log_info "服务器 IP: $ip"
    else
        log_warn "无法获取服务器 IP，将使用 127.0.0.1"
        echo "127.0.0.1" > "$HOME/agsbx/server_ip.log"
    fi
}

# ============================================================================
# Subscription & Link Functions
# ============================================================================

generate_v2ray_subscription() {
    local jh_file=$1
    [ ! -f "$jh_file" ] && return 1
    cat "$jh_file" | base64 -w0
}

decode_vmess_link() {
    local link=$1
    local b64_part="${link#vmess://}"
    local json=$(echo "$b64_part" | base64 -d 2>/dev/null)
    [ -z "$json" ] && return 1

    if command -v jq >/dev/null 2>&1; then
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
    else
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
    export vm_ps vm_add vm_port vm_id vm_aid vm_net vm_type vm_host vm_path vm_tls vm_sni
}

decode_vless_link() {
    local link=$1
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

    export vl_name="$name" vl_uuid="$uuid" vl_host_addr="$host" vl_port="$port"
    export vl_encryption vl_security vl_type vl_host vl_path vl_sni vl_flow vl_fp vl_pbk vl_sid vl_mode
}

generate_clash_vmess_proxy() {
    local link=$1
    decode_vmess_link "$link" || return 1
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

    if [ "$vm_tls" = "tls" ]; then
        cat <<EOF
    tls: true
    skip-cert-verify: true
EOF
        [ -n "$vm_sni" ] && echo "    servername: $vm_sni"
    fi

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

generate_clash_vless_proxy() {
    local link=$1
    decode_vless_link "$link" || return 1
    local name="${vl_name:-VLESS}"

    cat <<EOF
  - name: "$name"
    type: vless
    server: $vl_host_addr
    port: $vl_port
    uuid: $vl_uuid
EOF

    if [ "$vl_security" = "tls" ] || [ "$vl_security" = "reality" ]; then
        cat <<EOF
    tls: true
    skip-cert-verify: true
EOF
        [ -n "$vl_sni" ] && echo "    servername: $vl_sni"

        if [ "$vl_security" = "reality" ]; then
            [ -n "$vl_pbk" ] && echo "    reality-opts:"
            [ -n "$vl_pbk" ] && echo "      public-key: $vl_pbk"
            [ -n "$vl_sid" ] && echo "      short-id: $vl_sid"
        fi

        [ -n "$vl_fp" ] && echo "    client-fingerprint: $vl_fp"
    fi

    [ -n "$vl_flow" ] && echo "    flow: $vl_flow"

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

generate_clash_ss_proxy() {
    local link=$1
    local b64_part="${link#ss://}"
    local name="${b64_part##*#}"
    b64_part="${b64_part%%#*}"

    if [[ "$b64_part" == *"@"* ]]; then
        local method_pass="${b64_part%%@*}"
        local method="${method_pass%%:*}"
        local password="${method_pass#*:}"
        local addr="${b64_part#*@}"
        local server="${addr%%:*}"
        local port="${addr#*:}"
    else
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

generate_clash_hysteria2_proxy() {
    local link=$1
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

generate_clash_tuic_proxy() {
    local link=$1
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

generate_clash_config() {
    local jh_file=$1
    [ ! -f "$jh_file" ] && return 1

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
                proxy_names+=("${line##*#}")
                ;;
            hysteria2://*)
                generate_clash_hysteria2_proxy "$line"
                proxy_names+=("${line##*#}")
                ;;
            tuic://*)
                generate_clash_tuic_proxy "$line"
                proxy_names+=("${line##*#}")
                ;;
        esac
    done < "$jh_file"

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

save_subscription_files() {
    local jh_file=$1
    local output_dir="${2:-$HOME/agsbx}"

    if [ ! -f "$jh_file" ]; then
        log_error "节点文件 $jh_file 不存在"
        return 1
    fi

    mkdir -p "$output_dir"

    echo "正在生成 V2ray 订阅..."
    generate_v2ray_subscription "$jh_file" > "$output_dir/v2ray_sub.txt"
    if [ $? -eq 0 ]; then
        log_info "✓ V2ray 订阅已保存: $output_dir/v2ray_sub.txt"
    else
        log_error "✗ V2ray 订阅生成失败"
        return 1
    fi

    echo "正在生成 Clash 配置..."
    generate_clash_config "$jh_file" > "$output_dir/clash.yaml"
    if [ $? -eq 0 ]; then
        log_info "✓ Clash 配置已保存: $output_dir/clash.yaml"
    else
        log_error "✗ Clash 配置生成失败"
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

# ============================================================================
# Port Config Functions
# ============================================================================

generate_port_config() {
    local port_conf="$HOME/agsbx/ports.conf"
    
    # Header and SSH default
    cat > "$port_conf" <<EOF
# 端口配置（自动生成）
# 默认端口 (安全建议：请确保SSH端口已开放)
tcp:22          # SSH (保留端口防锁死)
EOF

    echo
    echo "========================================================="
    echo " [重要] 请按照以下列表，在您的防火墙/安全组放行端口 "
    echo " 端口配置文件已生成: $port_conf"
    echo "========================================================="
    echo "协议端口信息:"
    
    # Helper to check, print and write to conf
    add_port() {
        local name="$1"
        local var_name="$2"
        local proto="${3:-tcp/udp}" 
        
        local p="${!var_name}"
        
        if [ -n "$p" ]; then
            # Display
            echo " - $name: $p ($proto)"
            
            # Write to ports.conf with Requested Format: protocol:port # Comment
            if [ "$proto" == "tcp/udp" ]; then
                echo "tcp:$p          # $name (tcp)" >> "$port_conf"
                echo "udp:$p          # $name (udp)" >> "$port_conf"
            else
                echo "$proto:$p          # $name" >> "$port_conf"
            fi
        fi
    }

    add_port "VLESS-Reality" "port_vl_re" "tcp"
    add_port "VMess-WS" "port_vm_ws" "tcp"
    add_port "VLESS-WS" "port_vw" "tcp"
    add_port "VLESS-XHTTP" "port_xh" "tcp"
    add_port "VLESS-XHTTP-ENC" "port_vx" "tcp"
    
    add_port "Hysteria2" "port_hy2" "udp"
    add_port "Tuic v5" "port_tu" "udp"
    add_port "Shadowsocks" "port_ss" "tcp/udp"
    add_port "AnyTLS" "port_an" "tcp"
    add_port "Any-Reality" "port_ar" "tcp"
    add_port "Socks5" "port_so" "tcp/udp"
    
    echo "========================================================="
    echo
    cat "$port_conf"
    echo "========================================================="
    echo
}

# ============================================================================
# Link Generation Logic
# ============================================================================

cfip() { echo $((RANDOM % 13 + 1)); }

generate_all_links() {
    log_info "正在生成节点链接..."
    
    rm -rf "$HOME/agsbx/jh.txt"
    
    # Reload config to ensure we have latest vars
    [ -f "$HOME/agsbx/config.env" ] && source "$HOME/agsbx/config.env"
    
    server_ip=$(cat "$HOME/agsbx/server_ip.log" 2>/dev/null)
    [ -z "$server_ip" ] && server_ip="127.0.0.1"
    
    # Use variable directly
    sxname="${name}"
    hostname=$(uname -n)
    
    xvvmcdnym="${cdnym}"
    ym_vl_re="${ym_vl_re}"
    
    # Map keys from config names to local names
    private_key_x="${xray_key_private}"
    public_key_x="${xray_key_public}"
    short_id_x="${xray_key_shortid}"
    enkey="${xray_key_en}"
    
    private_key_s="${singbox_key_private}"
    public_key_s="${singbox_key_public}"
    short_id_s="${singbox_key_shortid}"
    sskey="${sskey}"
    cert_sha256="${cert_sha256}"

    # Check Xray Config
    if [ -f "$HOME/agsbx/xr.json" ]; then
        local xr_content=$(cat "$HOME/agsbx/xr.json")
        
        if echo "$xr_content" | grep -q 'xhttp-reality'; then
            echo "vless://$uuid@$server_ip:$port_xh?encryption=none&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_x&sid=$short_id_x&type=xhttp&path=$uuid-xh&mode=auto#${sxname}vl-xhttp-reality-enc-$hostname" >> "$HOME/agsbx/jh.txt"
        fi
        
        if echo "$xr_content" | grep -q 'vless-xhttp"'; then
             echo "vless://$uuid@$server_ip:$port_vx?encryption=$enkey&type=xhttp&path=$uuid-vx&mode=auto#${sxname}vl-xhttp-enc-$hostname" >> "$HOME/agsbx/jh.txt"
             if [ -n "$xvvmcdnym" ]; then
                 echo "vless://$uuid@yg$(cfip).ygkkk.dpdns.org:$port_vx?encryption=$enkey&type=xhttp&host=$xvvmcdnym&path=$uuid-vx&mode=auto#${sxname}vl-xhttp-enc-cdn-$hostname" >> "$HOME/agsbx/jh.txt"
             fi
        fi
        
        if echo "$xr_content" | grep -q 'vless-xhttp-cdn'; then
             echo "vless://$uuid@$server_ip:$port_vw?encryption=$enkey&type=xhttp&path=$uuid-vw&mode=packet-up#${sxname}vl-xhttp-enc-$hostname" >> "$HOME/agsbx/jh.txt"
             if [ -n "$xvvmcdnym" ]; then
                 echo "vless://$uuid@yg$(cfip).ygkkk.dpdns.org:$port_vw?encryption=$enkey&type=xhttp&host=$xvvmcdnym&path=$uuid-vw&mode=packet-up#${sxname}vl-xhttp-enc-cdn-$hostname" >> "$HOME/agsbx/jh.txt"
             fi
        fi
        
        if echo "$xr_content" | grep -q 'reality-vision'; then
            echo "vless://$uuid@$server_ip:$port_vl_re?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_x&sid=$short_id_x&type=tcp&headerType=none#${sxname}vl-reality-vision-$hostname" >> "$HOME/agsbx/jh.txt"
        fi
    fi
    
    # Check Sing-box Config
    if [ -f "$HOME/agsbx/sb.json" ]; then
        local sb_content=$(cat "$HOME/agsbx/sb.json")
        
        if echo "$sb_content" | grep -q 'ss-2022'; then
            echo "ss://$(echo -n "2022-blake3-aes-256-gcm:$sskey@$server_ip:$port_ss" | base64 -w0)#${sxname}Shadowsocks-2022-$hostname" >> "$HOME/agsbx/jh.txt"
        fi
        
        if echo "$sb_content" | grep -q 'socks5-sb'; then
             echo "socks5://$uuid:$uuid@$server_ip:$port_so#${sxname}socks5-$hostname" >> "$HOME/agsbx/jh.txt"
        fi
        
        if echo "$sb_content" | grep -q 'anytls-sb'; then
            echo "anytls://$uuid@$server_ip:$port_an?insecure=1&allowInsecure=1#${sxname}anytls-$hostname" >> "$HOME/agsbx/jh.txt"
        fi
        
        if echo "$sb_content" | grep -q 'vless-reality-sb'; then
             echo "anytls://$uuid@$server_ip:$port_ar?security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_s&sid=$short_id_s&type=tcp&headerType=none#${sxname}any-reality-$hostname" >> "$HOME/agsbx/jh.txt"
        fi
        
        if echo "$sb_content" | grep -q 'hy2-sb'; then
             random_cn="${cert_cn:-www.bing.com}"
             
             if [ -n "$cert_sha256" ]; then
                 # Use Pinning (Recommended)
                 echo "hysteria2://$uuid@$server_ip:$port_hy2?security=tls&alpn=h3&pinSHA256=$cert_sha256&sni=$random_cn#${sxname}hy2-$hostname" >> "$HOME/agsbx/jh.txt"
             else
                 # Fallback to insecure if no cert hash
                 echo "hysteria2://$uuid@$server_ip:$port_hy2?security=tls&alpn=h3&insecure=1&sni=$random_cn#${sxname}hy2-$hostname" >> "$HOME/agsbx/jh.txt"
             fi
        fi
        
        if echo "$sb_content" | grep -q 'tuic5-sb'; then
             random_cn="${cert_cn:-www.bing.com}"
             
             if [ -n "$cert_sha256" ]; then
                echo "tuic://$uuid:$uuid@$server_ip:$port_tu?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$random_cn&pinSHA256=$cert_sha256#${sxname}tuic-$hostname" >> "$HOME/agsbx/jh.txt"
             else
                echo "tuic://$uuid:$uuid@$server_ip:$port_tu?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$random_cn&allow_insecure=1&allowInsecure=1#${sxname}tuic-$hostname" >> "$HOME/agsbx/jh.txt"
             fi
        fi
    fi
    
    # Check VMess (Can be in either)
    if grep -q 'vmess-xhttp' "$HOME/agsbx/xr.json" 2>/dev/null || grep -q 'vmess-sb' "$HOME/agsbx/sb.json" 2>/dev/null; then
        echo "vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vm-ws-$hostname\", \"add\": \"$server_ip\", \"port\": \"$port_vm_ws\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"www.bing.com\", \"path\": \"/$uuid-vm\", \"tls\": \"\"}" | base64 -w0)" >> "$HOME/agsbx/jh.txt"
        
        if [ -n "$xvvmcdnym" ]; then
             echo "vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vm-ws-cdn-$hostname\", \"add\": \"yg$(cfip).ygkkk.dpdns.org\", \"port\": \"$port_vm_ws\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$xvvmcdnym\", \"path\": \"/$uuid-vm\", \"tls\": \"\"}" | base64 -w0)" >> "$HOME/agsbx/jh.txt"
        fi
    fi
    
    # Argo Links
    argodomain="${sbargoym}"
    [ -z "$argodomain" ] && argodomain=$(grep -a trycloudflare.com "$HOME/agsbx/argo.log" 2>/dev/null | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    
    if [ -n "$argodomain" ]; then
        vlvm="${vlvm}"
        if [ "$vlvm" = "Vmess" ]; then
             echo "vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-ws-tls-argo-$hostname-443\", \"add\": \"yg1.ygkkk.dpdns.org\", \"port\": \"443\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"chrome\"}" | base64 -w0)" >> "$HOME/agsbx/jh.txt"
        elif [ "$vlvm" = "Vless" ]; then
             echo "vless://$uuid@yg$(cfip).ygkkk.dpdns.org:443?encryption=$enkey&type=xhttp&host=$argodomain&path=$uuid-vw&mode=packet-up&security=tls&sni=$argodomain&fp=chrome&insecure=0&allowInsecure=0#${sxname}vless-xhttp-tls-argo-enc-$hostname" >> "$HOME/agsbx/jh.txt"
        fi
    fi
    
    log_info "节点链接已生成: $HOME/agsbx/jh.txt"
    if [ -f "$HOME/agsbx/jh.txt" ]; then
        echo "========================================================="
        cat "$HOME/agsbx/jh.txt"
        echo "========================================================="
    fi
    
    # Autosaving subscription files
    save_subscription_files "$HOME/agsbx/jh.txt" "$HOME/agsbx"
}
