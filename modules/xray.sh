#!/bin/bash

# ============================================================================
# Xray Module
# Core installation, Configuration generation, and Service management
# ============================================================================

# Load Utils
[ -z "$(type -t log_info)" ] && source "$(dirname "$0")/utils.sh"

install_xray_core() {
    log_info "检查 Xray 内核..."
    
    local out="$HOME/agsbx/xray"
    if [ -f "$out" ] && [ -x "$out" ]; then
        local ver=$("$out" version 2>/dev/null | awk '/^Xray/{print $2}')
        if [ -n "$ver" ]; then
            log_info "检测到本地已存在有效的 Xray 内核 ($ver)，跳过下载。"
            return 0
        fi
        log_warn "检测到本地 Xray 内核异常，将重新下载安装。"
        rm -f "$out"
    fi

    local archive_pattern=""
    local fallback_asset_id=""
    case "$cpu" in
        amd64) 
            archive_pattern="Xray-linux-64"
            fallback_asset_id="383344053"
            ;;
        arm64) 
            archive_pattern="Xray-linux-arm64-v8a"
            fallback_asset_id="383344168"
            ;;
        *) log_error "不支持的架构: $cpu"; return 1 ;;
    esac

    local repo="XTLS/Xray-core"
    local latest_url="https://api.github.com/repos/$repo/releases/latest"
    
    require_jq
    
    local release_json=""
    if command -v curl >/dev/null 2>&1; then
        release_json=$(curl -fsSL --connect-timeout 8 --max-time 15 "$latest_url" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        release_json=$(timeout 15 wget -qO- "$latest_url" 2>/dev/null)
    fi
    
    local asset_api_url=""
    local download_url=""
    local asset_name=""
    if [ -n "$release_json" ]; then
        local re_pat="$archive_pattern(\\.tar\\.gz|\\.tar\\.xz|\\.zip)"
        asset_api_url=$(echo "$release_json" | jq -r --arg re "$re_pat" '.assets[] | select(.name | test($re)) | .url' 2>/dev/null | head -n1)
        download_url=$(echo "$release_json" | jq -r --arg re "$re_pat" '.assets[] | select(.name | test($re)) | .browser_download_url' 2>/dev/null | head -n1)
        asset_name=$(echo "$release_json" | jq -r --arg re "$re_pat" '.assets[] | select(.name | test($re)) | .name' 2>/dev/null | head -n1)
        [ "$asset_api_url" = "null" ] && asset_api_url=""
        [ "$download_url" = "null" ] && download_url=""
        [ "$asset_name" = "null" ] && asset_name=""
    fi

    local temp_dir="$HOME/agsbx/temp_xr"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    local archive_file="$temp_dir/xr_archive"
    local downloaded=false

    # Helper function to verify downloaded archive integrity
    verify_archive() {
        local file="$1"
        [ -f "$file" ] || return 1
        local size=$(wc -c < "$file" 2>/dev/null || echo 0)
        [ "$size" -gt 2000000 ] || return 1
        if echo "$asset_name" | grep -qE '\.zip$' || unzip -tq "$file" >/dev/null 2>&1; then
            unzip -tq "$file" >/dev/null 2>&1 || return 1
        elif echo "$asset_name" | grep -qE '\.tar\.gz$|\.tgz$'; then
            tar -tzf "$file" >/dev/null 2>&1 || return 1
        elif echo "$asset_name" | grep -qE '\.tar\.xz$'; then
            tar -tJf "$file" >/dev/null 2>&1 || return 1
        fi
        return 0
    }

    # Tier 1: GitHub API Stream (bypasses GitHub 504 gateway timeout, direct to Azure/Fastly)
    if [ -n "$asset_api_url" ]; then
        log_info "正在通过 GitHub API 流下载最新 Xray..."
        if command -v curl >/dev/null 2>&1; then
            curl -fL -sS --connect-timeout 10 --max-time 180 --retry 2 \
                 -H "Accept: application/octet-stream" \
                 -o "$archive_file" "$asset_api_url" 2>/dev/null
        fi
        if verify_archive "$archive_file"; then
            downloaded=true
            log_info "Xray 压缩包下载成功 (GitHub API Stream)"
        else
            rm -f "$archive_file"
        fi
    fi

    # Tier 2: Official browser release download URL
    if [ "$downloaded" = false ] && [ -n "$download_url" ]; then
        log_info "尝试官方 Release 链接下载 Xray..."
        if command -v curl >/dev/null 2>&1; then
            curl -fL -sS --connect-timeout 10 --max-time 180 --retry 2 \
                 -o "$archive_file" "$download_url" 2>/dev/null
        elif command -v wget >/dev/null 2>&1; then
            timeout 180 wget -q -O "$archive_file" --tries=2 "$download_url" 2>/dev/null
        fi
        if verify_archive "$archive_file"; then
            downloaded=true
            log_info "Xray 压缩包下载成功 (Official Release)"
        else
            rm -f "$archive_file"
        fi
    fi

    # Tier 3: Known GitHub proxy / acceleration mirrors
    if [ "$downloaded" = false ] && [ -n "$download_url" ]; then
        for mirror in "https://ghproxy.net/" "https://gh-proxy.com/"; do
            log_info "尝试加速镜像下载 Xray ($mirror)..."
            if command -v curl >/dev/null 2>&1; then
                curl -fL -sS --connect-timeout 10 --max-time 180 --retry 1 \
                     -o "$archive_file" "${mirror}${download_url}" 2>/dev/null
            elif command -v wget >/dev/null 2>&1; then
                timeout 180 wget -q -O "$archive_file" --tries=1 "${mirror}${download_url}" 2>/dev/null
            fi
            if verify_archive "$archive_file"; then
                downloaded=true
                log_info "Xray 压缩包下载成功 (Mirror: $mirror)"
                break
            else
                rm -f "$archive_file"
            fi
        done
    fi

    # Extraction
    if [ "$downloaded" = true ] && [ -f "$archive_file" ]; then
        if echo "$asset_name" | grep -qE '\.tar\.gz$|\.tgz$'; then
            tar -xzf "$archive_file" -C "$temp_dir" 2>/dev/null
        elif echo "$asset_name" | grep -qE '\.tar\.xz$'; then
            tar -xJf "$archive_file" -C "$temp_dir" 2>/dev/null
        elif echo "$asset_name" | grep -qE '\.zip$' || unzip -tq "$archive_file" >/dev/null 2>&1; then
            unzip -q "$archive_file" -d "$temp_dir" 2>/dev/null
        else
            unzip -q "$archive_file" -d "$temp_dir" 2>/dev/null || tar -xzf "$archive_file" -C "$temp_dir" 2>/dev/null
        fi
        local bin_path=$(find "$temp_dir" -type f -name 'xray' | head -n1)
        if [ -n "$bin_path" ]; then
            chmod +x "$bin_path"
            if "$bin_path" version >/dev/null 2>&1; then
                mv "$bin_path" "$out"
                chmod +x "$out"
            fi
        fi
    fi

    # Tier 4: Fallback to standalone pre-compiled binary
    if [ ! -f "$out" ] || ! "$out" version >/dev/null 2>&1; then
        log_warn "压缩包解压或验证未成功，启动备用预编译二进制下载..."
        rm -rf "$temp_dir"
        mkdir -p "$temp_dir"
        local fallback_bin="$temp_dir/xray"

        # 4a. Via GitHub API stream for argosbx prebuilt asset
        if [ -n "$fallback_asset_id" ] && command -v curl >/dev/null 2>&1; then
            curl -fL -sS --connect-timeout 10 --max-time 120 --retry 2 \
                 -H "Accept: application/octet-stream" \
                 -o "$fallback_bin" "https://api.github.com/repos/yonggekkk/argosbx/releases/assets/$fallback_asset_id" 2>/dev/null
        fi

        # 4b. Via direct URL or mirror
        if [ ! -f "$fallback_bin" ] || [ $(wc -c < "$fallback_bin" 2>/dev/null || echo 0) -lt 2000000 ]; then
            local fb_url="https://github.com/yonggekkk/argosbx/releases/download/argosbx/xray-$cpu"
            if command -v curl >/dev/null 2>&1; then
                curl -fL -sS --connect-timeout 10 --max-time 120 --retry 2 -o "$fallback_bin" "$fb_url" 2>/dev/null || \
                curl -fL -sS --connect-timeout 10 --max-time 120 --retry 1 -o "$fallback_bin" "https://ghproxy.net/$fb_url" 2>/dev/null
            elif command -v wget >/dev/null 2>&1; then
                timeout 120 wget -q -O "$fallback_bin" --tries=2 "$fb_url" 2>/dev/null || \
                timeout 120 wget -q -O "$fallback_bin" --tries=1 "https://ghproxy.net/$fb_url" 2>/dev/null
            fi
        fi

        if [ -f "$fallback_bin" ] && [ $(wc -c < "$fallback_bin" 2>/dev/null || echo 0) -gt 2000000 ]; then
            chmod +x "$fallback_bin"
            if "$fallback_bin" version >/dev/null 2>&1; then
                mv "$fallback_bin" "$out"
                chmod +x "$out"
            fi
        fi
    fi

    rm -rf "$temp_dir"

    # Final verification
    if [ -f "$out" ] && [ -x "$out" ] && "$out" version >/dev/null 2>&1; then
        local ver=$("$out" version 2>/dev/null | awk '/^Xray/{print $2}')
        log_info "已成功安装 Xray 内核: $ver"
        return 0
    else
        log_error "Xray 内核安装失败，所有镜像与备用源均不可用。"
        return 1
    fi
}

generate_xray_keys() {
    mkdir -p "$HOME/agsbx/xrk"
    chmod 700 "$HOME/agsbx/xrk"
    
    # Reality Keys
    if [ "$xhp" = "yes" ] || [ "$vlp" = "yes" ]; then
        if [ -z "$ym_vl_re" ]; then ym_vl_re=apple.com; fi
        update_config_var "ym_vl_re" "$ym_vl_re"
        
        if [ -z "$xray_key_private" ] || [ -z "$xray_key_public" ]; then
            key_pair=$("$HOME/agsbx/xray" x25519 2>&1)
            private_key=$(echo "$key_pair" | grep "PrivateKey" | awk '{print $2}')
            public_key=$(echo "$key_pair" | grep "Password" | awk '{print $2}')
            short_id=$(date +%s%N | sha256sum | cut -c 1-8)
            
            # Persist to config
            update_config_var "xray_key_private" "$private_key"
            update_config_var "xray_key_public" "$public_key"
            update_config_var "xray_key_shortid" "$short_id"
        fi
    fi
    
    # Encryption Keys for VLESS (Required if vxp, vwp, xhp OR argo_type=vless)
    if [ "$xhp" = "yes" ] || [ "$vxp" = "yes" ] || [ "$vwp" = "yes" ] || [ "$argo_type" = "vless" ]; then
        if [ -z "$xray_key_de" ] || [ -z "$xray_key_en" ]; then
            vlkey=$("$HOME/agsbx/xray" vlessenc)
            dekey=$(echo "$vlkey" | grep '"decryption":' | sed -n '2p' | cut -d' ' -f2- | tr -d '"')
            enkey=$(echo "$vlkey" | grep '"encryption":' | sed -n '2p' | cut -d' ' -f2- | tr -d '"')
            
            update_config_var "xray_key_de" "$dekey"
            update_config_var "xray_key_en" "$enkey"
        fi
    fi
    
    # Export for current session (with strict safety fallback for unexported envs)
    if [ -z "$xray_key_private" ] && [ -f "$HOME/agsbx/config.env" ]; then
        xray_key_private=$(grep "^xray_key_private=" "$HOME/agsbx/config.env" | cut -d'=' -f2- | tr -d '"'\''')
        xray_key_public=$(grep "^xray_key_public=" "$HOME/agsbx/config.env" | cut -d'=' -f2- | tr -d '"'\''')
        xray_key_shortid=$(grep "^xray_key_shortid=" "$HOME/agsbx/config.env" | cut -d'=' -f2- | tr -d '"'\''')
        xray_key_de=$(grep "^xray_key_de=" "$HOME/agsbx/config.env" | cut -d'=' -f2- | tr -d '"'\''')
        xray_key_en=$(grep "^xray_key_en=" "$HOME/agsbx/config.env" | cut -d'=' -f2- | tr -d '"'\''')
    fi

    export private_key_x="${xray_key_private}"
    export public_key_x="${xray_key_public}"
    export short_id_x="${xray_key_shortid}"
    export dekey="${xray_key_de}"
    export enkey="${xray_key_en}"
}

init_xray_config() {
    require_jq
    
    # Calculate optimal buffer size based on system memory or PERF_MODE
    local optimal_buf=512
    case "${PERF_MODE:-auto}" in
        high_throughput|high) optimal_buf=1024 ;;
        low_memory|low)       optimal_buf=128 ;;
        *)
            local total_mem_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
            if [ -n "$total_mem_kb" ]; then
                local total_mem_mb=$((total_mem_kb / 1024))
                if [ "$total_mem_mb" -lt 512 ]; then
                    optimal_buf=128
                elif [ "$total_mem_mb" -lt 1500 ]; then
                    optimal_buf=512
                else
                    optimal_buf=1024
                fi
            else
                optimal_buf=512
            fi
            ;;
    esac
    log_info "Xray 连接缓冲池自适应优化: ${optimal_buf} KB"

    # Init base config using jq
    jq -n --argjson buf "$optimal_buf" '{
      log: { loglevel: "error" },
      dns: {
        servers: [
          "1.1.1.1",
          "8.8.8.8"
        ]
      },
      policy: {
        levels: {
          "0": {
            "handshake": 10,
            "connIdle": 300,
            "uplinkOnly": 2,
            "downlinkOnly": 5,
            "bufferSize": $buf
          }
        }
      },
      inbounds: [],
      outbounds: [],
      routing: { domainStrategy: "IPOnDemand", rules: [] }
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
        "destOverride": ["http", "tls"],
        "metadataOnly": false,
        "routeOnly": true
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
        "metadataOnly": false,
        "routeOnly": true
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
        "metadataOnly": false,
        "routeOnly": true
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
        "metadataOnly": false,
        "routeOnly": true
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

    # Conflict Check: When Argo is enabled with VMess type, skip the general public VMess inbound.
    # The hidden Argo-VMess-WS inbound on port_argo_ws will handle the traffic instead.
    if [ "$argo" = "yes" ] && [ "$argo_type" != "vless" ]; then
        log_warn "Argo-VMess 模式已激活：跳过 Xray 公网 VMess 入站，由 Argo 隐藏通道独占承载。"
        return
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
              "metadataOnly": false,
              "routeOnly": true
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
            "metadataOnly": false,
            "routeOnly": true
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
                "metadataOnly": false,
                "routeOnly": true
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
              "metadataOnly": false,
              "routeOnly": true
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
        \"mtu\": 1280,
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
            \"endpoint\": \"${xendip}:2408\"
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
