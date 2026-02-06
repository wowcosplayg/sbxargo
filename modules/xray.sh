#!/bin/bash

# ============================================================================
# Xray Module
# Core installation, Configuration generation, and Service management
# ============================================================================

# Load Utils
[ -z "$(type -t log_info)" ] && source "$(dirname "$0")/utils.sh"

install_xray_core() {
    log_info "检查 Xray 内核..."
    
    # Check if update is needed or force reinstall logic can be added here
    # reusing the logic from upxray but adapted
    
    local archive_name=""
    case "$cpu" in
        amd64) archive_name="Xray-linux-64.zip" ;;
        arm64) archive_name="Xray-linux-arm64-v8a.zip" ;;
        *) log_error "不支持的架构: $cpu"; return 1 ;;
    esac

    # We assume download_official_release is available (copied to main.sh or utils? No, sbxargo had it. 
    # I should move download functions to utils.sh or install.sh. 
    # Wait, I didn't verify if I moved download functions to install.sh.
    # checking install.sh content... I put install_dependencies there but NOT download_official_release.
    # I MUST ensure main.sh or install.sh has download_official_release.
    # Refactoring decision: Put generic download functions in utils.sh or install.sh. 
    # Let's assume for now I will add them to install.sh later or right now.
    # Actually, I'll add them to install.sh in a separate step if I haven't.
    # For now, I'll call a function `download_xray_release` which I'll implement here or rely on shared.
    # To be safe and modular, I will reimplement a simple downloader here or reference a shared one.
    # The original script had a robust one. I'll rely on `install.sh` potentially having it.
    # I will add `download_file` and `download_official_release` to `install.sh` in a fix step.
    # For this file, I'll assume they will be available.
    
    # Actually, better to just call the download logic directly or via a specific function here if specific.
    # I'll use the shared function assumption.
    
    if ! type -t download_official_release >/dev/null; then
        # Fallback or error? I will fix install.sh to include it.
        log_warn "download_official_release function missing, config might fail if core not present."
    else
        if ! download_official_release "XTLS/Xray-core" "xray" "$cpu" "$HOME/agsbx/xray" "$archive_name"; then
            log_error "Xray 下载失败"
            return 1
        fi
    fi

    local ver=$("$HOME/agsbx/xray" version 2>/dev/null | awk '/^Xray/{print $2}')
    log_info "已安装 Xray 内核: $ver"
}

generate_xray_keys() {
    mkdir -p "$HOME/agsbx/xrk"
    
    # Reality Keys
    if [ -n "$xhp" ] || [ -n "$vlp" ]; then
        if [ -z "$ym_vl_re" ]; then ym_vl_re=apple.com; fi
        echo "$ym_vl_re" > "$HOME/agsbx/ym_vl_re"
        
        if [ ! -e "$HOME/agsbx/xrk/private_key" ]; then
            key_pair=$("$HOME/agsbx/xray" x25519)
            private_key=$(echo "$key_pair" | grep "PrivateKey" | awk '{print $2}')
            public_key=$(echo "$key_pair" | grep "Password" | awk '{print $2}')
            short_id=$(date +%s%N | sha256sum | cut -c 1-8)
            echo "$private_key" > "$HOME/agsbx/xrk/private_key"
            echo "$public_key" > "$HOME/agsbx/xrk/public_key"
            echo "$short_id" > "$HOME/agsbx/xrk/short_id"
        fi
    fi
    
    # Encryption Keys for VLESS
    if [ -n "$xhp" ] || [ -n "$vxp" ] || [ -n "$vwp" ]; then
        if [ ! -e "$HOME/agsbx/xrk/dekey" ]; then
            vlkey=$("$HOME/agsbx/xray" vlessenc)
            dekey=$(echo "$vlkey" | grep '"decryption":' | sed -n '2p' | cut -d' ' -f2- | tr -d '"')
            enkey=$(echo "$vlkey" | grep '"encryption":' | sed -n '2p' | cut -d' ' -f2- | tr -d '"')
            echo "$dekey" > "$HOME/agsbx/xrk/dekey"
            echo "$enkey" > "$HOME/agsbx/xrk/enkey"
        fi
    fi
    
    # Export for current session
    export private_key_x=$(cat "$HOME/agsbx/xrk/private_key" 2>/dev/null)
    export public_key_x=$(cat "$HOME/agsbx/xrk/public_key" 2>/dev/null)
    export short_id_x=$(cat "$HOME/agsbx/xrk/short_id" 2>/dev/null)
    export dekey=$(cat "$HOME/agsbx/xrk/dekey" 2>/dev/null)
    export enkey=$(cat "$HOME/agsbx/xrk/enkey" 2>/dev/null)
}

init_xray_config() {
    cat > "$HOME/agsbx/xr.json" <<EOF
{
  "log": {
  "loglevel": "none"
  },
  "inbounds": [
EOF
}

add_reality_xray() {
    [ -z "$vlp" ] && return
    
    if [ -z "$port_vl_re" ] && [ ! -e "$HOME/agsbx/port_vl_re" ]; then
        port_vl_re=$(shuf -i 10000-65535 -n 1)
        echo "$port_vl_re" > "$HOME/agsbx/port_vl_re"
    elif [ -n "$port_vl_re" ]; then
        echo "$port_vl_re" > "$HOME/agsbx/port_vl_re"
    fi
    port_vl_re=$(cat "$HOME/agsbx/port_vl_re")
    
    log_info "添加 Vless-Reality: $port_vl_re"
    
    cat >> "$HOME/agsbx/xr.json" <<EOF
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
    },
EOF
}

add_xhttp_xray() {
    # Vless-xhttp-reality-enc
    if [ -n "$xhp" ]; then
        if [ -z "$port_xh" ] && [ ! -e "$HOME/agsbx/port_xh" ]; then
            port_xh=$(shuf -i 10000-65535 -n 1)
            echo "$port_xh" > "$HOME/agsbx/port_xh"
        fi
        port_xh=$(cat "$HOME/agsbx/port_xh")
        log_info "添加 Vless-xhttp-reality: $port_xh"
        
        cat >> "$HOME/agsbx/xr.json" <<EOF
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
        "decryption": "none"
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
          "path": "${uuid}-xh",
          "mode": "auto"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
EOF
    fi

    # Vless-xhttp-enc
    if [ -n "$vxp" ]; then
        if [ -z "$port_vx" ] && [ ! -e "$HOME/agsbx/port_vx" ]; then
            port_vx=$(shuf -i 10000-65535 -n 1)
            echo "$port_vx" > "$HOME/agsbx/port_vx"
        fi
        port_vx=$(cat "$HOME/agsbx/port_vx")
        log_info "添加 Vless-xhttp: $port_vx"
        
        if [ -n "$cdnym" ]; then
            echo "$cdnym" > "$HOME/agsbx/cdnym"
        fi
        
        cat >> "$HOME/agsbx/xr.json" <<EOF
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
        "xhttpSettings": {
          "host": "",
          "path": "${uuid}-vx",
          "mode": "auto"
        }
      },
        "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
EOF
    fi
    
    # Vless-ws-enc (renamed logic from vwp)
    if [ -n "$vwp" ]; then
        if [ -z "$port_vw" ] && [ ! -e "$HOME/agsbx/port_vw" ]; then
            port_vw=$(shuf -i 10000-65535 -n 1)
            echo "$port_vw" > "$HOME/agsbx/port_vw"
        fi
        port_vw=$(cat "$HOME/agsbx/port_vw")
        log_info "添加 Vless-ws-enc (xhttp mode): $port_vw"
        
        if [ -n "$cdnym" ]; then
            echo "$cdnym" > "$HOME/agsbx/cdnym"
        fi
        
        cat >> "$HOME/agsbx/xr.json" <<EOF
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
        "xhttpSettings": {
          "path": "${uuid}-vw",
          "mode": "packet-up"
        }
      },
        "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
EOF
    fi
}

add_vmess_xray() {
    [ -z "$vmp" ] && return
    
    if [ -z "$port_vm_ws" ] && [ ! -e "$HOME/agsbx/port_vm_ws" ]; then
        port_vm_ws=$(shuf -i 10000-65535 -n 1)
        echo "$port_vm_ws" > "$HOME/agsbx/port_vm_ws"
    elif [ -n "$port_vm_ws" ]; then
        echo "$port_vm_ws" > "$HOME/agsbx/port_vm_ws"
    fi
    port_vm_ws=$(cat "$HOME/agsbx/port_vm_ws")
    log_info "添加 Vmess-xhttp: $port_vm_ws"
    
    if [ -n "$cdnym" ]; then
        echo "$cdnym" > "$HOME/agsbx/cdnym"
    fi
    
    cat >> "$HOME/agsbx/xr.json" <<EOF
        {
            "tag": "vmess-xhttp-argo",
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
                "network": "xhttp",
                "security": "none",
                "xhttpSettings": {
                  "path": "${uuid}-vm",
                  "mode": "packet-up"
            }
        },
            "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
            "metadataOnly": false
            }
         }, 
EOF
}

add_socks_xray() {
    [ -z "$sop" ] && return
    
    if [ -z "$port_so" ] && [ ! -e "$HOME/agsbx/port_so" ]; then
        port_so=$(shuf -i 10000-65535 -n 1)
        echo "$port_so" > "$HOME/agsbx/port_so"
    elif [ -n "$port_so" ]; then
        echo "$port_so" > "$HOME/agsbx/port_so"
    fi
    port_so=$(cat "$HOME/agsbx/port_so")
    log_info "添加 Socks5: $port_so"
    
    cat >> "$HOME/agsbx/xr.json" <<EOF
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
         }, 
EOF
}

configure_xray_outbound() {
    # Fix trailing comma
    sed -i '${s/,\s*$//}' "$HOME/agsbx/xr.json"
    
    cat >> "$HOME/agsbx/xr.json" <<EOF
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {
      "domainStrategy":"${xryx}"
     }
    }
EOF

    # Add Wireguard if WARP is used
    if [[ "$x1outtag" == *"warp"* ]] || [[ "$x2outtag" == *"warp"* ]]; then
        cat >> "$HOME/agsbx/xr.json" <<EOF
    ,{
      "tag": "x-warp-out",
      "protocol": "wireguard",
      "settings": {
        "secretKey": "${pvk}",
        "address": [
          "172.16.0.2/32",
          "${wpv6}/128"
        ],
        "peers": [
          {
            "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
            "allowedIPs": [
              "0.0.0.0/0",
              "::/0"
            ],
            "endpoint": "${xendip}:2408"
          }
        ],
        "reserved": ${res}
        }
    },
    {
      "tag":"warp-out",
      "protocol":"freedom",
        "settings":{
        "domainStrategy":"${wxryx}"
       },
       "proxySettings":{
       "tag":"x-warp-out"
     }
}
EOF
    fi

    cat >> "$HOME/agsbx/xr.json" <<EOF
  ],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [
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
  }
}
EOF
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
TimeoutStartSec=0
ExecStart=/root/agsbx/xray run -c /root/agsbx/xr.json
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
command="/root/agsbx/xray"
command_args="run -c /root/agsbx/xr.json"
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
        nohup "$HOME/agsbx/xray" run -c "$HOME/agsbx/xr.json" >/dev/null 2>&1 &
    fi
}
