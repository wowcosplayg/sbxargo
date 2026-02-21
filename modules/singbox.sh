#!/bin/bash

# ============================================================================
# Sing-box Module
# Core installation, Configuration generation, and Service management
# ============================================================================

# Load Utils
[ -z "$(type -t log_info)" ] && source "$(dirname "$0")/utils.sh"

install_singbox_core() {
    log_info "检查 Sing-box 内核..."
    
    if [ -f "$HOME/agsbx/sing-box" ]; then
        local ver=$("$HOME/agsbx/sing-box" version 2>/dev/null | awk '/version/{print $NF}')
        log_info "检测到本地已存在 Sing-box 内核 ($ver)，跳过下载。"
        return 0
    fi
    
    # Logic from upsingbox
    local archive_pattern=""
    case "$cpu" in
        amd64) archive_pattern="sing-box-.*-linux-amd64" ;;
        arm64) archive_pattern="sing-box-.*-linux-arm64" ;;
        *) log_error "不支持的架构: $cpu"; return 1 ;;
    esac

    # Assuming download_singbox_release is handled here or via similar logic
    # I'll implement the download logic inline or call a shared one if I moved it.
    # To be safe, I'll use the logic I saw in sbxargo.sh
    
    local repo="SagerNet/sing-box"
    local latest_url="https://api.github.com/repos/$repo/releases/latest"
    
    # 依赖检查：由于我们需要 jq 处理 JSON
    require_jq
    
    # 获取最新的释放信息 JSON
    local release_json=""
    if command -v curl >/dev/null 2>&1; then
        release_json=$(curl -fsSL "$latest_url")
    elif command -v wget >/dev/null 2>&1; then
        release_json=$(wget -qO- "$latest_url")
    fi
    
    local download_url=""
    if [ -n "$release_json" ]; then
        # 兼容 tar.gz, tar.xz, zip 格式
        download_url=$(echo "$release_json" | jq -r --arg re "$archive_pattern(\\.tar\\.gz|\\.tar\\.xz|\\.zip)" '.assets[] | select(.name | test($re)) | .browser_download_url' | head -n1)
    fi

    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        log_error "获取 Sing-box 下载链接失败"
        return 1
    fi
    local out="$HOME/agsbx/sing-box"
    local temp_dir="$HOME/agsbx/temp_sb"
    
    mkdir -p "$temp_dir"
    
    if command -v curl >/dev/null 2>&1; then
        curl -Lo "$temp_dir/sb.tar.gz" -# --retry 2 "$download_url"
    elif command -v wget >/dev/null 2>&1; then
        timeout 30 wget -O "$temp_dir/sb.tar.gz" --tries=2 "$download_url"
    fi
    
    if [ -f "$temp_dir/sb.tar.gz" ]; then
        # 兼容不同格式解压
        if echo "$download_url" | grep -qE '\.tar\.gz$|\.tgz$'; then
            tar -xzf "$temp_dir/sb.tar.gz" -C "$temp_dir"
        elif echo "$download_url" | grep -qE '\.tar\.xz$'; then
            tar -xJf "$temp_dir/sb.tar.gz" -C "$temp_dir"
        elif echo "$download_url" | grep -qE '\.zip$'; then
            unzip -q "$temp_dir/sb.tar.gz" -d "$temp_dir"
        fi
        
        local bin_path=$(find "$temp_dir" -type f -name 'sing-box' | head -n1)
        if [ -n "$bin_path" ]; then
            mv "$bin_path" "$out"
            chmod +x "$out"
            rm -rf "$temp_dir"
        else
            log_error "解压失败，未找到 sing-box 文件。"
            rm -rf "$temp_dir"
            return 1
        fi
        local ver=$("$out" version 2>/dev/null | awk '/version/{print $NF}')
        log_info "已安装 Sing-box 内核: $ver"
    else
        log_error "Sing-box 下载失败"
        rm -rf "$temp_dir"
        return 1
    fi
}

generate_singbox_keys() {
    # Certificate for TLS (Hysteria2/Tuic/AnyTLS)
    if [ ! -f "$HOME/agsbx/private.key" ] || [ ! -f "$HOME/agsbx/cert.pem" ]; then
        if command -v openssl >/dev/null 2>&1; then
            local random_cn=$(openssl rand -hex 8).com
            update_config_var "cert_cn" "$random_cn"
            openssl ecparam -genkey -name prime256v1 -out "$HOME/agsbx/private.key" >/dev/null 2>&1
            chmod 600 "$HOME/agsbx/private.key"
            openssl req -new -x509 -days 36500 -key "$HOME/agsbx/private.key" -out "$HOME/agsbx/cert.pem" -subj "/CN=$random_cn" >/dev/null 2>&1
        else
             log_error "openssl 未安装，无法生成证书"
             return 1
        fi
    fi
    
    # Reality Keys
    if [ -n "$arp" ]; then
        if [ -z "$ym_vl_re" ]; then ym_vl_re=apple.com; fi
        update_config_var "ym_vl_re" "$ym_vl_re"
        
        mkdir -p "$HOME/agsbx/sbk"
        chmod 700 "$HOME/agsbx/sbk"
        if [ ! -e "$HOME/agsbx/sbk/private_key" ]; then
            key_pair=$("$HOME/agsbx/sing-box" generate reality-keypair)
            private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
            public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
            short_id=$("$HOME/agsbx/sing-box" generate rand --hex 4)
            
            update_config_var "singbox_key_private" "$private_key"
            update_config_var "singbox_key_public" "$public_key"
            update_config_var "singbox_key_shortid" "$short_id"
            
            # Persist keys
            echo "$private_key" > "$HOME/agsbx/sbk/private_key"
            echo "$public_key" > "$HOME/agsbx/sbk/public_key"
            echo "$short_id" > "$HOME/agsbx/sbk/short_id"
        else
            private_key=$(cat "$HOME/agsbx/sbk/private_key")
            public_key=$(cat "$HOME/agsbx/sbk/public_key")
            short_id=$(cat "$HOME/agsbx/sbk/short_id")
            
            # Ensure env vars are synced
            update_config_var "singbox_key_private" "$private_key"
            update_config_var "singbox_key_public" "$public_key"
            update_config_var "singbox_key_shortid" "$short_id"
        fi
    fi
     
    # Shadowsocks Key
    if [ -n "$ssp" ]; then
        if [ ! -e "$HOME/agsbx/sskey" ]; then
            sskey=$("$HOME/agsbx/sing-box" generate rand 32 --base64)
            update_config_var "sskey" "$sskey"
            
            # Persist key
            echo "$sskey" > "$HOME/agsbx/sskey"
            chmod 600 "$HOME/agsbx/sskey"
            
        elif [ -s "$HOME/agsbx/sskey" ]; then
             # Read existing key
             sskey=$(cat "$HOME/agsbx/sskey")
             update_config_var "sskey" "$sskey"
        fi
    fi
    
    export private_key_s="${singbox_key_private}"
    export public_key_s="${singbox_key_public}"
    export short_id_s="${singbox_key_shortid}"
    export sskey="${sskey}"

    # Hysteria2 Obfs Password
    if [ -n "$hyp" ]; then
        if [ ! -e "$HOME/agsbx/hy2_obfs_pwd" ]; then
            if command -v openssl >/dev/null 2>&1; then
                hy2_obfs_pwd=$(openssl rand -base64 16 | tr -d "\n")
            else
                hy2_obfs_pwd=$(date +%s%N | sha256sum | head -c 16)
            fi
            update_config_var "hy2_obfs_pwd" "$hy2_obfs_pwd"
            
            # Persist key
            echo "$hy2_obfs_pwd" > "$HOME/agsbx/hy2_obfs_pwd"
            chmod 600 "$HOME/agsbx/hy2_obfs_pwd"
        elif [ -s "$HOME/agsbx/hy2_obfs_pwd" ]; then
             hy2_obfs_pwd=$(cat "$HOME/agsbx/hy2_obfs_pwd")
             update_config_var "hy2_obfs_pwd" "$hy2_obfs_pwd"
        fi
    fi
    export hy2_obfs_pwd="${hy2_obfs_pwd}"
    
    # Calculate SHA256 Fingerprint for Pinning (Fixes allowInsecure warning)
    if [ -f "$HOME/agsbx/cert.pem" ] && command -v openssl >/dev/null 2>&1; then
        cert_sha256=$(openssl x509 -noout -fingerprint -sha256 -in "$HOME/agsbx/cert.pem" | awk -F= '{print $2}' | tr -d : | tr '[:upper:]' '[:lower:]')
        echo "$cert_sha256" > "$HOME/agsbx/cert_sha256"
        update_config_var "cert_sha256" "$cert_sha256"
        export cert_sha256
    fi
}

init_singbox_config() {
    require_jq
    
    jq -n '{
      log: {
        disabled: false,
        level: "warn",
        timestamp: true
      },
      dns: {
        servers: [
            { "type": "https", "server": "1.1.1.1", "tag": "remote", "detour": "direct" },
            { "type": "https", "server": "1.0.0.1", "tag": "remote-backup", "detour": "direct" },
            { "type": "local", "tag": "local", "detour": "direct" }
        ],
        strategy: "prefer_ipv4",
        final: "remote"
      },

      inbounds: [],
      outbounds: [],
      route: {}
    }' > "$HOME/agsbx/sb.json"
}

add_hysteria2_singbox() {
    [ "$hyp" != "yes" ] && return
    
    if [ -z "$port_hy2" ] && [ ! -e "$HOME/agsbx/port_hy2" ]; then
        port_hy2=$(shuf -i 10000-65535 -n 1)
        update_config_var "port_hy2" "$port_hy2"
    elif [ -n "$port_hy2" ]; then
        update_config_var "port_hy2" "$port_hy2"
    fi
    log_info "添加 Hysteria2: $port_hy2"
    open_port "$port_hy2" "udp"
    
    local json_block
    json_block=$(cat <<EOF
    {
        "type": "hysteria2",
        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ],
        "ignore_client_bandwidth": false,
        "obfs": {
            "type": "salamander",
            "password": "${hy2_obfs_pwd}"
        },
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$HOME/agsbx/cert.pem",
            "key_path": "$HOME/agsbx/private.key"
        },
        "masquerade": {
            "type": "proxy",
            "url": "https://www.bing.com/"
        }
    }
EOF
)
    jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/sb.json" > "$HOME/agsbx/sb.json.tmp" && mv "$HOME/agsbx/sb.json.tmp" "$HOME/agsbx/sb.json"
}

add_tuic_singbox() {
    [ "$tup" != "yes" ] && return
    
    if [ -z "$port_tu" ] && [ ! -e "$HOME/agsbx/port_tu" ]; then
        port_tu=$(shuf -i 10000-65535 -n 1)
        update_config_var "port_tu" "$port_tu"
    elif [ -n "$port_tu" ]; then
        update_config_var "port_tu" "$port_tu"
    fi
    log_info "添加 Tuic: $port_tu"
    open_port "$port_tu" "udp"
    
    local json_block
    json_block=$(cat <<EOF
        {
            "type":"tuic",
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",

            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$HOME/agsbx/cert.pem",
                "key_path": "$HOME/agsbx/private.key"
            }
        }
EOF
)
    jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/sb.json" > "$HOME/agsbx/sb.json.tmp" && mv "$HOME/agsbx/sb.json.tmp" "$HOME/agsbx/sb.json"
}

add_anytls_singbox() {
    [ "$anp" != "yes" ] && return
    if [ -z "$port_an" ] && [ ! -e "$HOME/agsbx/port_an" ]; then
        port_an=$(shuf -i 10000-65535 -n 1)
        update_config_var "port_an" "$port_an"
    elif [ -n "$port_an" ]; then
        update_config_var "port_an" "$port_an"
    fi
    log_info "添加 Anytls: $port_an"
    open_port "$port_an" "tcp"
    
    local json_block
    json_block=$(cat <<EOF
        {
            "type":"anytls",
            "tag":"anytls-sb",
            "listen":"::",
            "listen_port":${port_an},
            "users":[
                {
                  "name": "${uuid}",
                  "password":"${uuid}"
                }
            ],
            "padding_scheme": [],
            "tls":{
                "enabled": true,
                "certificate_path": "$HOME/agsbx/cert.pem",
                "key_path": "$HOME/agsbx/private.key"
            }
        }
EOF
)
    jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/sb.json" > "$HOME/agsbx/sb.json.tmp" && mv "$HOME/agsbx/sb.json.tmp" "$HOME/agsbx/sb.json"
}

add_anyreality_singbox() {
    [ "$arp" != "yes" ] && return
    
    if [ -z "$port_ar" ] && [ ! -e "$HOME/agsbx/port_ar" ]; then
        port_ar=$(shuf -i 10000-65535 -n 1)
        update_config_var "port_ar" "$port_ar"
    elif [ -n "$port_ar" ]; then
        update_config_var "port_ar" "$port_ar"
    fi
    log_info "添加 Any-Reality: $port_ar"
    open_port "$port_ar" "tcp"
    
    local json_block
    json_block=$(cat <<EOF
        {
            "type": "vless",
            "tag": "vless-reality-sb",
            "listen": "::",
            "listen_port": ${port_ar},
            "users": [
                {
                    "uuid": "${uuid}",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "${ym_vl_re}",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "${ym_vl_re}",
                        "server_port": 443
                    },
                    "private_key": "$private_key_s",
                    "short_id": ["$short_id_s"]
                }
            }
        }
EOF
)
    jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/sb.json" > "$HOME/agsbx/sb.json.tmp" && mv "$HOME/agsbx/sb.json.tmp" "$HOME/agsbx/sb.json"
}

add_shadowsocks_singbox() {
    [ "$ssp" != "yes" ] && return
    if [ -z "$port_ss" ] && [ ! -e "$HOME/agsbx/port_ss" ]; then
        port_ss=$(shuf -i 10000-65535 -n 1)
        update_config_var "port_ss" "$port_ss"
    elif [ -n "$port_ss" ]; then
        update_config_var "port_ss" "$port_ss"
    fi
    log_info "添加 Shadowsocks: $port_ss"
    open_port "$port_ss" "tcp/udp"
    
    local json_block
    json_block=$(cat <<EOF
        {
            "type": "shadowsocks",
            "tag":"ss-2022",
            "listen": "::",
            "listen_port": $port_ss,
            "method": "2022-blake3-aes-256-gcm",
            "password": "$sskey",
            "multiplex": {
                "enabled": true,
                "padding": true
            }
    }
EOF
)
    jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/sb.json" > "$HOME/agsbx/sb.json.tmp" && mv "$HOME/agsbx/sb.json.tmp" "$HOME/agsbx/sb.json"
}

add_vmess_singbox() {
    [ "$vmp" != "yes" ] && return
    
    # Conflict Check: If Xray is installed/configured with VMess, we skip Sing-box VMess on same port
    if [ -f "$HOME/agsbx/xr.json" ] && grep -q "vmess-xhttp-argo" "$HOME/agsbx/xr.json"; then
        log_warn "检测到 Xray 已接管 VMess 协议，Sing-box VMess 将自动禁用以避免端口冲突。"
        return
    fi
    
    if [ -z "$port_vm_ws" ] && [ ! -e "$HOME/agsbx/port_vm_ws" ]; then
        if [ -n "$cdnym" ] && [ "$argo" != "vmpt" ]; then
            # CDN requires specific HTTPS ports
            port_vm_ws=$(shuf -e 2053 2083 2087 2096 8443 | head -n 1)
        else
            port_vm_ws=$(shuf -i 10000-65535 -n 1)
        fi
        update_config_var "port_vm_ws" "$port_vm_ws"
    elif [ -n "$port_vm_ws" ]; then
        update_config_var "port_vm_ws" "$port_vm_ws"
    fi
    log_info "添加 Vmess (Sing-box): $port_vm_ws"
    open_port "$port_vm_ws" "tcp"
    
    local tls_block=""
    if [ "$argo" != "vmpt" ]; then
        tls_block=$(cat <<EOF
,
        "tls": {
            "enabled": true,
            "certificate_path": "$HOME/agsbx/cert.pem",
            "key_path": "$HOME/agsbx/private.key"
        }
EOF
)
    fi
    
    local json_block
    json_block=$(cat <<EOF
{
        "type": "vmess",
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "/${uuid}-vm"
        }${tls_block}
    }
EOF
)
    jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/sb.json" > "$HOME/agsbx/sb.json.tmp" && mv "$HOME/agsbx/sb.json.tmp" "$HOME/agsbx/sb.json"
}

add_socks_singbox() {
    [ "$sop" != "yes" ] && return
    if [ -z "$port_so" ] && [ ! -e "$HOME/agsbx/port_so" ]; then
        port_so=$(shuf -i 10000-65535 -n 1)
        update_config_var "port_so" "$port_so"
    elif [ -n "$port_so" ]; then
        update_config_var "port_so" "$port_so"
    fi
    # Conflict Check: If Xray is installed/configured with Socks5, we skip Sing-box Socks5 on same port
    if [ -f "$HOME/agsbx/xr.json" ] && grep -q "socks5-xr" "$HOME/agsbx/xr.json"; then
        log_warn "检测到 Xray 已接管 Socks5 协议，Sing-box Socks5 将自动禁用以避免端口冲突。"
        return
    fi
     
    log_info "添加 Socks5 (Sing-box): $port_so"
    open_port "$port_so" "tcp/udp"
    
    local json_block
    json_block=$(cat <<EOF
    {
      "tag": "socks5-sb",
      "type": "socks",
      "listen": "::",
      "listen_port": ${port_so},
      "users": [
      {
      "username": "${uuid}",
      "password": "${uuid}"
      }
     ]
    }
EOF
)
    jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/sb.json" > "$HOME/agsbx/sb.json.tmp" && mv "$HOME/agsbx/sb.json.tmp" "$HOME/agsbx/sb.json"
}

configure_singbox_outbound() {
    local outbounds
    outbounds="["
    
    # Defaults
    outbounds+="{\"type\": \"direct\", \"tag\": \"direct\"}"

    # Add WARP Native WireGuard Outbound if WARP is used
    if [[ "$s1outtag" == *"warp"* ]] || [[ "$s2outtag" == *"warp"* ]]; then
        outbounds+=$(cat <<EOF
    ,{
      "type": "wireguard",
      "tag": "warp-out",
      "server": "162.159.192.1",
      "server_port": 2408,
      "local_address": [
        "172.16.0.2/32",
        "${WARP_IPV6}/128"
      ],
      "private_key": "${WARP_PRIVATE_KEY}",
      "peer_public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
      "reserved": ${WARP_RESERVED}
    }
EOF
)
    fi
    outbounds+="]"
    
    # Use variable to update outbounds
    jq --argjson new_out "$outbounds" '.outbounds = $new_out' "$HOME/agsbx/sb.json" > "$HOME/agsbx/sb.json.tmp" && mv "$HOME/agsbx/sb.json.tmp" "$HOME/agsbx/sb.json"
    
    # Route rules (Sing-box 1.11+ Rule Action chain)
    local route
    route=$(cat <<EOF
    {
        "rules": [
            {
                "action": "sniff"
            },
            {
                "ip_is_private": true,
                "outbound": "direct"
            },
            {
                "ip_cidr": [ ${sip} ],
                "outbound": "${s1outtag}"
            }
        ],
        "auto_detect_interface": false,
        "final": "${s2outtag}",
        "default_domain_resolver": "remote"
    }
EOF
)
     jq --argjson new_route "$route" '.route = $new_route' "$HOME/agsbx/sb.json" > "$HOME/agsbx/sb.json.tmp" && mv "$HOME/agsbx/sb.json.tmp" "$HOME/agsbx/sb.json"
}

start_singbox_service() {
    log_info "启动 Sing-box 服务..."
    if [ "$SYS_INIT" == "systemd" ]; then
        cat > /etc/systemd/system/sb.service <<EOF
[Unit]
Description=sb service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
LimitNPROC=512000
LimitNOFILE=512000
TimeoutStartSec=0
ExecStartPre=/bin/bash ${BASE_DIR}/main.sh regen_no_restart
ExecStart=${HOME}/agsbx/sing-box run -c ${HOME}/agsbx/sb.json
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable sb >/dev/null 2>&1
        systemctl restart sb >/dev/null 2>&1
    elif [ "$SYS_INIT" == "openrc" ]; then
        cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
description="sb service"
command="${HOME}/agsbx/sing-box"
command_args="run -c ${HOME}/agsbx/sb.json"
command_background=yes
pidfile="/run/sing-box.pid"
command_background="yes"
depend() {
need net
}
EOF
        chmod +x /etc/init.d/sing-box >/dev/null 2>&1
        rc-update add sing-box default >/dev/null 2>&1
        rc-service sing-box start >/dev/null 2>&1
    else
        kill -15 $(pgrep -f 'agsbx/sing-box' 2>/dev/null) 2>/dev/null
        nohup "$HOME/agsbx/sing-box" run -c "$HOME/agsbx/sb.json" > "$HOME/agsbx/sb.log" 2>&1 &
    fi
}
