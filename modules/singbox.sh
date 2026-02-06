#!/bin/bash

# ============================================================================
# Sing-box Module
# Core installation, Configuration generation, and Service management
# ============================================================================

# Load Utils
[ -z "$(type -t log_info)" ] && source "$(dirname "$0")/utils.sh"

install_singbox_core() {
    log_info "检查 Sing-box 内核..."
    
    # Logic from upsingbox
    local archive_pattern=""
    case "$cpu" in
        amd64) archive_pattern="sing-box-.*-linux-amd64.tar.gz" ;;
        arm64) archive_pattern="sing-box-.*-linux-arm64.tar.gz" ;;
        *) log_error "不支持的架构: $cpu"; return 1 ;;
    esac

    # Assuming download_singbox_release is handled here or via similar logic
    # I'll implement the download logic inline or call a shared one if I moved it.
    # To be safe, I'll use the logic I saw in sbxargo.sh
    
    local repo="SagerNet/sing-box"
    local latest_url="https://api.github.com/repos/$repo/releases/latest"
    local version=""

    if command -v curl > /dev/null 2>&1; then
        version=$(curl -sL "$latest_url" | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/' | sed 's/^v//')
    elif command -v wget > /dev/null 2>&1; then
        version=$(wget -qO- "$latest_url" | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/' | sed 's/^v//')
    fi
    
    if [ -z "$version" ]; then
        log_error "无法获取 Sing-box 版本信息"
        return 1
    fi
    
    local archive_name="sing-box-${version}-linux-${cpu}.tar.gz"
    local download_url="https://github.com/$repo/releases/download/v${version}/$archive_name"
    local out="$HOME/agsbx/sing-box"
    local temp_dir="$HOME/agsbx/temp_sb"
    
    mkdir -p "$temp_dir"
    
    if command -v curl >/dev/null 2>&1; then
        curl -Lo "$temp_dir/sb.tar.gz" -# --retry 2 "$download_url"
    elif command -v wget >/dev/null 2>&1; then
        timeout 30 wget -O "$temp_dir/sb.tar.gz" --tries=2 "$download_url"
    fi
    
    if [ -f "$temp_dir/sb.tar.gz" ]; then
        tar -xzf "$temp_dir/sb.tar.gz" -C "$temp_dir"
        mv "$temp_dir"/sing-box-*/sing-box "$out"
        chmod +x "$out"
        rm -rf "$temp_dir"
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
            echo "$random_cn" > "$HOME/agsbx/cert_cn"
            openssl ecparam -genkey -name prime256v1 -out "$HOME/agsbx/private.key" >/dev/null 2>&1
            openssl req -new -x509 -days 36500 -key "$HOME/agsbx/private.key" -out "$HOME/agsbx/cert.pem" -subj "/CN=$random_cn" >/dev/null 2>&1
        else
             log_error "openssl 未安装，无法生成证书"
             return 1
        fi
    fi
    
    # Reality Keys
    if [ -n "$arp" ]; then
        if [ -z "$ym_vl_re" ]; then ym_vl_re=apple.com; fi
        echo "$ym_vl_re" > "$HOME/agsbx/ym_vl_re"
        
        mkdir -p "$HOME/agsbx/sbk"
        if [ ! -e "$HOME/agsbx/sbk/private_key" ]; then
            key_pair=$("$HOME/agsbx/sing-box" generate reality-keypair)
            private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
            public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
            short_id=$("$HOME/agsbx/sing-box" generate rand --hex 4)
            echo "$private_key" > "$HOME/agsbx/sbk/private_key"
            echo "$public_key" > "$HOME/agsbx/sbk/public_key"
            echo "$short_id" > "$HOME/agsbx/sbk/short_id"
        fi
    fi
     
    # Shadowsocks Key
    if [ -n "$ssp" ]; then
        if [ ! -e "$HOME/agsbx/sskey" ]; then
            sskey=$("$HOME/agsbx/sing-box" generate rand 32 --base64)
            echo "$sskey" > "$HOME/agsbx/sskey"
        fi
    fi
    
    export private_key_s=$(cat "$HOME/agsbx/sbk/private_key" 2>/dev/null)
    export public_key_s=$(cat "$HOME/agsbx/sbk/public_key" 2>/dev/null)
    export short_id_s=$(cat "$HOME/agsbx/sbk/short_id" 2>/dev/null)
    export short_id_s=$(cat "$HOME/agsbx/sbk/short_id" 2>/dev/null)
    export sskey=$(cat "$HOME/agsbx/sskey" 2>/dev/null)
    
    # Calculate SHA256 Fingerprint for Pinning (Fixes allowInsecure warning)
    if [ -f "$HOME/agsbx/cert.pem" ] && command -v openssl >/dev/null 2>&1; then
        cert_sha256=$(openssl x509 -noout -fingerprint -sha256 -in "$HOME/agsbx/cert.pem" | awk -F= '{print $2}' | tr -d : | tr '[:upper:]' '[:lower:]')
        echo "$cert_sha256" > "$HOME/agsbx/cert_sha256"
        export cert_sha256
    fi
}

init_singbox_config() {
    cat > "$HOME/agsbx/sb.json" <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
EOF
}

add_hysteria2_singbox() {
    [ -z "$hyp" ] && return
    
    if [ -z "$port_hy2" ] && [ ! -e "$HOME/agsbx/port_hy2" ]; then
        port_hy2=$(shuf -i 10000-65535 -n 1)
        echo "$port_hy2" > "$HOME/agsbx/port_hy2"
    elif [ -n "$port_hy2" ]; then
        echo "$port_hy2" > "$HOME/agsbx/port_hy2"
    fi
    port_hy2=$(cat "$HOME/agsbx/port_hy2")
    log_info "添加 Hysteria2: $port_hy2"
    
    cat >> "$HOME/agsbx/sb.json" <<EOF
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
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$HOME/agsbx/cert.pem",
            "key_path": "$HOME/agsbx/private.key"
        }
    },
EOF
}

add_tuic_singbox() {
    [ -z "$tup" ] && return
    
    if [ -z "$port_tu" ] && [ ! -e "$HOME/agsbx/port_tu" ]; then
        port_tu=$(shuf -i 10000-65535 -n 1)
        echo "$port_tu" > "$HOME/agsbx/port_tu"
    elif [ -n "$port_tu" ]; then
        echo "$port_tu" > "$HOME/agsbx/port_tu"
    fi
    port_tu=$(cat "$HOME/agsbx/port_tu")
    log_info "添加 Tuic: $port_tu"
    
    cat >> "$HOME/agsbx/sb.json" <<EOF
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
        },
EOF
}

add_anytls_singbox() {
    [ -z "$anp" ] && return
    if [ -z "$port_an" ] && [ ! -e "$HOME/agsbx/port_an" ]; then
        port_an=$(shuf -i 10000-65535 -n 1)
        echo "$port_an" > "$HOME/agsbx/port_an"
    elif [ -n "$port_an" ]; then
        echo "$port_an" > "$HOME/agsbx/port_an"
    fi
    port_an=$(cat "$HOME/agsbx/port_an")
    log_info "添加 Anytls: $port_an"
    
    cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type":"anytls",
            "tag":"anytls-sb",
            "listen":"::",
            "listen_port":${port_an},
            "users":[
                {
                  "password":"${uuid}"
                }
            ],
            "padding_scheme":[],
            "tls":{
                "enabled": true,
                "certificate_path": "$HOME/agsbx/cert.pem",
                "key_path": "$HOME/agsbx/private.key"
            }
        },
EOF
}

add_anyreality_singbox() {
    [ -z "$arp" ] && return
    
    if [ -z "$port_ar" ] && [ ! -e "$HOME/agsbx/port_ar" ]; then
        port_ar=$(shuf -i 10000-65535 -n 1)
        echo "$port_ar" > "$HOME/agsbx/port_ar"
    elif [ -n "$port_ar" ]; then
        echo "$port_ar" > "$HOME/agsbx/port_ar"
    fi
    port_ar=$(cat "$HOME/agsbx/port_ar")
    log_info "添加 Any-Reality: $port_ar"
    
    cat >> "$HOME/agsbx/sb.json" <<EOF
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
        },
EOF
}

add_shadowsocks_singbox() {
    [ -z "$ssp" ] && return
    if [ -z "$port_ss" ] && [ ! -e "$HOME/agsbx/port_ss" ]; then
        port_ss=$(shuf -i 10000-65535 -n 1)
        echo "$port_ss" > "$HOME/agsbx/port_ss"
    elif [ -n "$port_ss" ]; then
        echo "$port_ss" > "$HOME/agsbx/port_ss"
    fi
    port_ss=$(cat "$HOME/agsbx/port_ss")
    log_info "添加 Shadowsocks: $port_ss"
    
    cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type": "shadowsocks",
            "tag":"ss-2022",
            "listen": "::",
            "listen_port": $port_ss,
            "method": "2022-blake3-aes-256-gcm",
            "password": "$sskey"
    },  
EOF
}

add_vmess_singbox() {
    [ -z "$vmp" ] && return
    
    # Conflict Check: If Xray is installed/configured with VMess, we skip Sing-box VMess on same port
    if [ -f "$HOME/agsbx/xr.json" ] && grep -q "vmess-xhttp-argo" "$HOME/agsbx/xr.json"; then
        log_warn "检测到 Xray 已接管 VMess 协议，Sing-box VMess 将自动禁用以避免端口冲突。"
        return
    fi
    
    if [ -z "$port_vm_ws" ] && [ ! -e "$HOME/agsbx/port_vm_ws" ]; then
        port_vm_ws=$(shuf -i 10000-65535 -n 1)
        echo "$port_vm_ws" > "$HOME/agsbx/port_vm_ws"
    elif [ -n "$port_vm_ws" ]; then
        echo "$port_vm_ws" > "$HOME/agsbx/port_vm_ws"
    fi
    port_vm_ws=$(cat "$HOME/agsbx/port_vm_ws")
    log_info "添加 Vmess (Sing-box): $port_vm_ws"
    
    cat >> "$HOME/agsbx/sb.json" <<EOF
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
            "type": "http",
            "path": "${uuid}-vm"
        }
    },
EOF
}

add_socks_singbox() {
    [ -z "$sop" ] && return
    if [ -z "$port_so" ] && [ ! -e "$HOME/agsbx/port_so" ]; then
        port_so=$(shuf -i 10000-65535 -n 1)
        echo "$port_so" > "$HOME/agsbx/port_so"
    elif [ -n "$port_so" ]; then
        echo "$port_so" > "$HOME/agsbx/port_so"
    fi
    port_so=$(cat "$HOME/agsbx/port_so")
    log_info "添加 Socks5 (Sing-box): $port_so"
    
    cat >> "$HOME/agsbx/sb.json" <<EOF
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
    },
EOF
}

configure_singbox_outbound() {
    # Fix trailing comma
    sed -i '${s/,\s*$//}' "$HOME/agsbx/sb.json"
    
    cat >> "$HOME/agsbx/sb.json" <<EOF
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
EOF

    # Add Wireguard if WARP is used
    if [[ "$s1outtag" == *"warp"* ]] || [[ "$s2outtag" == *"warp"* ]]; then
        cat >> "$HOME/agsbx/sb.json" <<EOF
    ,{
      "type": "wireguard",
      "tag": "warp-out",
      "mtu": 1280,
      "address": [
        "172.16.0.2/32",
        "${wpv6}/128"
      ],
      "private_key": "${pvk}",
      "peers": [
        {
          "server": "${sendip}",
          "server_port": 2408,
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0",
            "::/0"
          ],
          "reserved": $res
        }
      ]
    }
EOF
    fi

    cat >> "$HOME/agsbx/sb.json" <<EOF
  ],
  "route": {
        "rules": [
            {
                "protocol": "dns",
                "outbound": "dns-out"
            },
            {
                "ip_is_private": true,
                "outbound": "direct"
            },
            {
                "ip_cidr": [ ${sip} ],
                "outbound": "${s1outtag}"
            },
            {
                "outbound": "${s2outtag}"
            }
        ],
        "auto_detect_interface": true,
        "final": "${s2outtag}"
    }
}
EOF
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
ExecStart=/root/agsbx/sing-box run -c /root/agsbx/sb.json
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
command="/root/agsbx/sing-box"
command_args="run -c /root/agsbx/sb.json"
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
        nohup "$HOME/agsbx/sing-box" run -c "$HOME/agsbx/sb.json" >/dev/null 2>&1 &
    fi
}
