#!/bin/bash

# ============================================================================
# Xray Module
# Core installation, Configuration generation, and Service management
# ============================================================================

# Load Utils
[ -z "$(type -t log_info)" ] && source "$(dirname "$0")/utils.sh"

install_xray_core() {
    log_info "检查 Xray 内核..."
    
    if [ -f "$HOME/agsbx/xray" ]; then
        local ver=$("$HOME/agsbx/xray" version 2>/dev/null | awk '/^Xray/{print $2}')
        log_info "检测到本地已存在 Xray 内核 ($ver)，跳过下载。"
        return 0
    fi
    
    # Check if update is needed or force reinstall logic can be added here
    # reusing the logic from upxray but adapted
    
    local archive_pattern=""
    case "$cpu" in
        amd64) archive_pattern="Xray-linux-64" ;;
        arm64) archive_pattern="Xray-linux-arm64-v8a" ;;
        *) log_error "不支持的架构: $cpu"; return 1 ;;
    esac

    local repo="XTLS/Xray-core"
    local latest_url="https://api.github.com/repos/$repo/releases/latest"
    
    require_jq
    
    local release_json=""
    if command -v curl >/dev/null 2>&1; then
        release_json=$(curl -fsSL "$latest_url")
    elif command -v wget >/dev/null 2>&1; then
        release_json=$(wget -qO- "$latest_url")
    fi
    
    local download_url=""
    if [ -n "$release_json" ]; then
        download_url=$(echo "$release_json" | jq -r --arg re "$archive_pattern(\\.tar\\.gz|\\.tar\\.xz|\\.zip)" '.assets[] | select(.name | test($re)) | .browser_download_url' | head -n1)
    fi

    if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
        log_error "获取 Xray 下载链接失败"
        return 1
    fi

    local out="$HOME/agsbx/xray"
    local temp_dir="$HOME/agsbx/temp_xr"
    mkdir -p "$temp_dir"

    if command -v curl >/dev/null 2>&1; then
        curl -Lo "$temp_dir/xr_archive" -# --retry 2 "$download_url"
    elif command -v wget >/dev/null 2>&1; then
        timeout 30 wget -O "$temp_dir/xr_archive" --tries=2 "$download_url"
    fi

    if [ -f "$temp_dir/xr_archive" ]; then
        if echo "$download_url" | grep -qE '\.tar\.gz$|\.tgz$'; then
            tar -xzf "$temp_dir/xr_archive" -C "$temp_dir"
        elif echo "$download_url" | grep -qE '\.tar\.xz$'; then
            tar -xJf "$temp_dir/xr_archive" -C "$temp_dir"
        elif echo "$download_url" | grep -qE '\.zip$'; then
            unzip -q "$temp_dir/xr_archive" -d "$temp_dir"
        fi
        local bin_path=$(find "$temp_dir" -type f -name 'xray' | head -n1)
        if [ -n "$bin_path" ]; then
            mv "$bin_path" "$out"
            chmod +x "$out"
            rm -rf "$temp_dir"
        else
            log_error "解压失败，未找到 xray 文件。"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        log_error "Xray 下载失败"
        rm -rf "$temp_dir"
        return 1
    fi

    local ver=$("$HOME/agsbx/xray" version 2>/dev/null | awk '/^Xray/{print $2}')
    log_info "已安装 Xray 内核: $ver"
}

generate_xray_keys() {
    mkdir -p "$HOME/agsbx/xrk"
    chmod 700 "$HOME/agsbx/xrk"
    
    # Reality Keys
    if [ -n "$xhp" ] || [ -n "$vlp" ]; then
        if [ -z "$ym_vl_re" ]; then ym_vl_re=apple.com; fi
        update_config_var "ym_vl_re" "$ym_vl_re"
        
        if [ ! -e "$HOME/agsbx/xrk/private_key" ]; then
            key_pair=$("$HOME/agsbx/xray" x25519)
            private_key=$(echo "$key_pair" | awk '/Private key/ {print $3}')
            public_key=$(echo "$key_pair" | awk '/Public key/ {print $3}')
            short_id=$(date +%s%N | sha256sum | cut -c 1-8)
            
            # Persist to config
            update_config_var "xray_key_private" "$private_key"
            update_config_var "xray_key_public" "$public_key"
            update_config_var "xray_key_shortid" "$short_id"
        else
            # If not regenerating, ensure loaded (for safety)
            private_key="${xray_key_private}"
            public_key="${xray_key_public}"
            short_id="${xray_key_shortid}"
        fi
        
        # Write to temp files for internal Xray consistency/fallback if needed by other tools?
        # Ideally we shouldn't need them anymore, but let's keep the key files for purely Xray internal use if referenced by config?
        # The xray config references "$private_key_x" which is an env var.
        # But wait, generate_xray_keys sets `private_key` then exports `private_key_x`.
        # Let's adjust the export section below.
    fi
    
    # Encryption Keys for VLESS (Required if vxp, vwp, xhp OR argo_type=vless)
    if [ -n "$xhp" ] || [ -n "$vxp" ] || [ -n "$vwp" ] || [ "$argo_type" = "vless" ]; then
        if [ ! -e "$HOME/agsbx/xrk/dekey" ]; then
            vlkey=$("$HOME/agsbx/xray" vlessenc)
            dekey=$(echo "$vlkey" | grep '"decryption":' | sed -n '2p' | cut -d' ' -f2- | tr -d '"')
            enkey=$(echo "$vlkey" | grep '"encryption":' | sed -n '2p' | cut -d' ' -f2- | tr -d '"')
            
            update_config_var "xray_key_de" "$dekey"
            update_config_var "xray_key_en" "$enkey"
        fi
    fi
    
    # Export for current session
    export private_key_x="${xray_key_private}"
    export public_key_x="${xray_key_public}"
    export short_id_x="${xray_key_shortid}"
    export dekey="${xray_key_de}"
    export enkey="${xray_key_en}"
}

init_xray_config() {
    require_jq
    
    # Init base config using jq
    jq -n '{
      log: { loglevel: "error" },
      dns: {
        servers: [
          "1.1.1.1",
          "1.0.0.1",
          "localhost"
        ]
      },
      policy: {
        levels: {
          "0": {
            "handshake": 4,
            "connIdle": 300,
            "uplinkOnly": 2,
            "downlinkOnly": 5,
            "bufferSize": 4
          }
        }
      },
      inbounds: [],
      outbounds: [],
      routing: { domainStrategy: "AsIs", rules: [] }
    }' > "$HOME/agsbx/xr.json"
}

add_reality_xray() {
    [ "$vlp" != "yes" ] && return
    
    if [ -z "$port_vl_re" ] && [ ! -e "$HOME/agsbx/port_vl_re" ]; then
        port_vl_re=$(shuf -i 10000-65535 -n 1)
        update_config_var "port_vl_re" "$port_vl_re"
    elif [ -n "$port_vl_re" ]; then
        update_config_var "port_vl_re" "$port_vl_re"
    fi
    LOG_MARKER_VLESS_REALITY="active"
    
    log_info "添加 Vless-Reality: $port_vl_re"
    open_port "$port_vl_re" "tcp"
    
    local json_block
    json_block=$(cat <<EOF
    {
        "tag":"reality-vision",
        "listen": "::",
        "port": $port_vl_re,
        "protocol": "vless",
        "settings": {
            "clients": [
                {
                    "id": "${uuid}",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
                "fingerprint": "chrome",
                "dest": "${ym_vl_re}:443",
                "serverNames": [
                  "${ym_vl_re}"
                ],
                "privateKey": "$private_key_x",
                "shortIds": ["$short_id_x"]
            }
        },
      "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls", "quic"],
      "metadataOnly": false
      }
    }
EOF
)
    # Use tmp file to update
    jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/xr.json" > "$HOME/agsbx/xr.json.tmp" && mv "$HOME/agsbx/xr.json.tmp" "$HOME/agsbx/xr.json"
}

add_xhttp_xray() {
    # Vless-xhttp-reality-enc
    if [ -n "$xhp" ]; then
        if [ -z "$port_xh" ] && [ ! -e "$HOME/agsbx/port_xh" ]; then
            port_xh=$(shuf -i 10000-65535 -n 1)
            update_config_var "port_xh" "$port_xh"
        elif [ -n "$port_xh" ]; then
            update_config_var "port_xh" "$port_xh"
        fi

        log_info "添加 Vless-xhttp-reality: $port_xh"
        open_port "$port_xh" "tcp"
        
        local json_block

        json_block=$(cat <<EOF
    {
      "tag":"xhttp-reality",
      "listen": "::",
      "port": ${port_xh},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "${dekey}"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "chrome",
          "target": "${ym_vl_re}:443",
          "serverNames": [
            "${ym_vl_re}"
          ],
          "privateKey": "$private_key_x",
          "shortIds": ["$short_id_x"]
        },
        "xhttpSettings": {
          "host": "",
          "path": "/${uuid}-xh",
          "mode": "auto"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    }
EOF
)
        jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/xr.json" > "$HOME/agsbx/xr.json.tmp" && mv "$HOME/agsbx/xr.json.tmp" "$HOME/agsbx/xr.json"
    fi

    # Vless-xhttp-enc
    if [ -n "$vxp" ]; then
        if [ -z "$port_vx" ] && [ ! -e "$HOME/agsbx/port_vx" ]; then
            if [ -n "$cdnym" ]; then
                # CDN requires specific HTTPS ports
                port_vx=$(shuf -e 2053 2083 2087 2096 8443 | head -n 1)
            else
                port_vx=$(shuf -i 10000-65535 -n 1)
            fi
            update_config_var "port_vx" "$port_vx"
        elif [ -n "$port_vx" ]; then
            update_config_var "port_vx" "$port_vx"
        fi

        log_info "添加 Vless-xhttp: $port_vx"
        open_port "$port_vx" "tcp"
        
        if [ -n "$cdnym" ]; then
            update_config_var "cdnym" "$cdnym"
        fi
        
        local sec_type="tls"
        local tls_block=$(cat <<EOF
,
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$HOME/agsbx/cert.pem",
              "keyFile": "$HOME/agsbx/private.key"
            }
          ]
        }
EOF
)
        
        local json_block
        json_block=$(cat <<EOF
    {
      "tag":"vless-xhttp",
      "listen": "::",
      "port": ${port_vx},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "${dekey}"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "${sec_type}",
        "xhttpSettings": {
          "host": "",
          "path": "/${uuid}-vx",
          "mode": "auto"
        }${tls_block}
      },
        "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    }
EOF
)
        jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/xr.json" > "$HOME/agsbx/xr.json.tmp" && mv "$HOME/agsbx/xr.json.tmp" "$HOME/agsbx/xr.json"
    fi
    
    # Vless-ws-enc (renamed logic from vwp)
    if [ -n "$vwp" ]; then
        if [ -z "$port_vw" ] && [ ! -e "$HOME/agsbx/port_vw" ]; then
            if [ -n "$cdnym" ] && [ "$argo" != "vwpt" ]; then
                # CDN requires specific HTTPS ports
                port_vw=$(shuf -e 2053 2083 2087 2096 8443 | head -n 1)
            else
                port_vw=$(shuf -i 10000-65535 -n 1)
            fi
            update_config_var "port_vw" "$port_vw"
        elif [ -n "$port_vw" ]; then
            update_config_var "port_vw" "$port_vw"
        fi

        log_info "添加 Vless-ws-enc (xhttp mode): $port_vw"
        open_port "$port_vw" "tcp"
        
        if [ -n "$cdnym" ]; then
            update_config_var "cdnym" "$cdnym"
        fi
        
        local sec_type="none"
        local tls_block=""
        if [ "$argo" != "vwpt" ]; then
            sec_type="tls"
            tls_block=$(cat <<EOF
,
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$HOME/agsbx/cert.pem",
              "keyFile": "$HOME/agsbx/private.key"
            }
          ]
        }
EOF
)
        fi
        
        local json_block
        json_block=$(cat <<EOF
    {
      "tag":"vless-xhttp-cdn",
      "listen": "::",
      "port": ${port_vw},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "${dekey}"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "${sec_type}",
        "xhttpSettings": {
          "path": "/${uuid}-vw",
          "mode": "packet-up"
        }${tls_block}
      },
        "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    }
EOF
)
        jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/xr.json" > "$HOME/agsbx/xr.json.tmp" && mv "$HOME/agsbx/xr.json.tmp" "$HOME/agsbx/xr.json"
    fi
}

add_vmess_xray() {
    [ "$vmp" != "yes" ] && return
    
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

    # Conflict Check: If Sing-box is installed/configured with VMess, we skip Xray VMess on same port
    if [ -f "$HOME/agsbx/sb.json" ] && grep -q "vmess-sb" "$HOME/agsbx/sb.json"; then
        log_warn "检测到 Sing-box 已接管 VMess 协议，Xray VMess 将自动禁用以避免端口冲突。"
        return
    fi

    log_info "添加 Vmess-xhttp: $port_vm_ws"
    open_port "$port_vm_ws" "tcp"
    
    if [ -n "$cdnym" ]; then
        update_config_var "cdnym" "$cdnym"
    fi
    
    local sec_type="none"
    local tls_block=""
    if [ "$argo" != "vmpt" ]; then
        sec_type="tls"
        tls_block=$(cat <<EOF
,
                "tlsSettings": {
                  "certificates": [
                    {
                      "certificateFile": "$HOME/agsbx/cert.pem",
                      "keyFile": "$HOME/agsbx/private.key"
                    }
                  ]
                }
EOF
)
    fi
    
    local json_block
    json_block=$(cat <<EOF
        {
            "tag": "vmess-xhttp",
            "listen": "::",
            "port": ${port_vm_ws},
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid}"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "security": "${sec_type}",
                "wsSettings": {
                  "path": "/${uuid}-vm"
                }${tls_block}
        },
            "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
            "metadataOnly": false
            }
         }
EOF
)
    jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/xr.json" > "$HOME/agsbx/xr.json.tmp" && mv "$HOME/agsbx/xr.json.tmp" "$HOME/agsbx/xr.json"
}

add_argo_inbound_xray() {
    [ "$argo" != "yes" ] && return
    
    # Ensure port is set
    if [ -z "$port_argo_ws" ]; then
        port_argo_ws=$(cat "$HOME/agsbx/port_argo_ws" 2>/dev/null)
        if [ -z "$port_argo_ws" ]; then
            port_argo_ws=$(shuf -i 10000-65535 -n 1)
            update_config_var "port_argo_ws" "$port_argo_ws"
        fi
    fi
    
    log_info "添加 Argo 专用 WebSocket 隐藏入站: $port_argo_ws"
    # Do NOT run open_port for Argo. It must remain explicitly 127.0.0.1 bound for security.

    local json_block
    if [ "$argo_type" == "vless" ]; then
        json_block=$(cat <<EOF
        {
          "tag":"argo-vless-ws",
          "listen": "127.0.0.1",
          "port": ${port_argo_ws},
          "protocol": "vless",
          "settings": {
            "clients": [
              {
                "id": "${uuid}"
              }
            ],
            "decryption": "${dekey}"
          },
          "streamSettings": {
            "network": "ws",
            "security": "none",
            "wsSettings": {
              "path": "/${uuid}-argo"
            }
          },
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
            "metadataOnly": false
          }
        }
EOF
)
    else
        # VMess Default fallback
        json_block=$(cat <<EOF
        {
            "tag": "argo-vmess-ws",
            "listen": "127.0.0.1",
            "port": ${port_argo_ws},
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid}"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "security": "none",
                "wsSettings": {
                  "path": "/${uuid}-argo"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false
            }
        }
EOF
)
    fi

    jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/xr.json" > "$HOME/agsbx/xr.json.tmp" && mv "$HOME/agsbx/xr.json.tmp" "$HOME/agsbx/xr.json"
}

add_socks_xray() {
    [ "$sop" != "yes" ] && return
    
    if [ -z "$port_so" ] && [ ! -e "$HOME/agsbx/port_so" ]; then
        port_so=$(shuf -i 10000-65535 -n 1)
        update_config_var "port_so" "$port_so"
    elif [ -n "$port_so" ]; then
        update_config_var "port_so" "$port_so"
    fi

    # Conflict Check: If Sing-box is installed/configured with Socks5, we skip Xray VMess on same port
    if [ -f "$HOME/agsbx/sb.json" ] && grep -q "socks5-sb" "$HOME/agsbx/sb.json"; then
        log_warn "检测到 Sing-box 已接管 Socks5 协议，Xray Socks5 将自动禁用以避免端口冲突。"
        return
    fi

    log_info "添加 Socks5: $port_so"
    open_port "$port_so" "tcp/udp"
    
    local json_block
    json_block=$(cat <<EOF
        {
         "tag": "socks5-xr",
         "port": ${port_so},
         "listen": "::",
         "protocol": "socks",
         "settings": {
            "auth": "password",
             "accounts": [
               {
               "user": "${uuid}",
               "pass": "${uuid}"
               }
            ],
            "udp": true
          },
            "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
            "metadataOnly": false
            }
         }
EOF
)
    jq --argjson new "$json_block" '.inbounds += [$new]' "$HOME/agsbx/xr.json" > "$HOME/agsbx/xr.json.tmp" && mv "$HOME/agsbx/xr.json.tmp" "$HOME/agsbx/xr.json"
}

configure_xray_outbound() {
    # 1. Add Direct and Warp outbounds
    local outbounds
    outbounds="[]"
    
    # Basic Direct
    outbounds=$(echo "$outbounds" | jq ". + [{
      \"protocol\": \"freedom\",
      \"tag\": \"direct\",
      \"settings\": {
      \"domainStrategy\":\"AsIs\"
     }
    }]")
    
    # Add WARP Proxy Outbound if WARP is used
    if [[ "$x1outtag" == *"warp"* ]] || [[ "$x2outtag" == *"warp"* ]]; then
        outbounds=$(echo "$outbounds" | jq ". + [
    {
      \"tag\": \"x-warp-out\",
      \"protocol\": \"wireguard\",
      \"settings\": {
        \"secretKey\": \"${WARP_PRIVATE_KEY}\",
        \"address\": [
          \"172.16.0.2/32\",
          \"${WARP_IPV6}/128\"
        ],
        \"peers\": [
          {
            \"publicKey\": \"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=\",
            \"allowedIPs\": [
              \"0.0.0.0/0\",
              \"::/0\"
            ],
            \"endpoint\": \"162.159.192.1:2408\"
          }
        ],
        \"reserved\": ${WARP_RESERVED}
      }
    },
    {
      \"tag\":\"warp-out\",
      \"protocol\":\"freedom\",
      \"settings\":{
        \"domainStrategy\":\"${wxryx}\"
      },
      \"proxySettings\":{
        \"tag\":\"x-warp-out\"
      }
    }]")
    fi
    
    # Update Outbounds
    jq --argjson new_out "$outbounds" '.outbounds = $new_out' "$HOME/agsbx/xr.json" > "$HOME/agsbx/xr.json.tmp" && mv "$HOME/agsbx/xr.json.tmp" "$HOME/agsbx/xr.json"
    
    # Update Routing
    local rules
    rules=$(cat <<EOF
    [
      {
        "type": "field",
        "ip": [ ${xip} ],
        "network": "tcp,udp",
        "outboundTag": "${x1outtag}"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "${x2outtag}"
      }
    ]
EOF
)
    jq --argjson new_rules "$rules" '.routing.rules = $new_rules | .routing.domainStrategy = "'${xryx}'"' "$HOME/agsbx/xr.json" > "$HOME/agsbx/xr.json.tmp" && mv "$HOME/agsbx/xr.json.tmp" "$HOME/agsbx/xr.json"
}

start_xray_service() {
    log_info "启动 Xray 服务..."
    if [ "$SYS_INIT" == "systemd" ]; then
        cat > /etc/systemd/system/xr.service <<EOF
[Unit]
Description=xr service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
LimitNPROC=512000
LimitNOFILE=512000
TimeoutStartSec=0
ExecStartPre=/bin/bash ${BASE_DIR}/main.sh regen_no_restart
ExecStart=${HOME}/agsbx/xray run -c ${HOME}/agsbx/xr.json
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable xr >/dev/null 2>&1
        systemctl restart xr >/dev/null 2>&1
    elif [ "$SYS_INIT" == "openrc" ]; then
        cat > /etc/init.d/xray <<EOF
#!/sbin/openrc-run
description="xr service"
command="${HOME}/agsbx/xray"
command_args="run -c ${HOME}/agsbx/xr.json"
command_background=yes
pidfile="/run/xray.pid"
command_background="yes"
depend() {
need net
}
EOF
        chmod +x /etc/init.d/xray >/dev/null 2>&1
        rc-update add xray default >/dev/null 2>&1
        rc-service xray restart >/dev/null 2>&1
    else
        kill -15 $(pgrep -f 'agsbx/xray' 2>/dev/null) 2>/dev/null
        nohup "$HOME/agsbx/xray" run -c "$HOME/agsbx/xr.json" > "$HOME/agsbx/xr.log" 2>&1 &
    fi
}
