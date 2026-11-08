#!/bin/bash

# ============================================================================
# Argo Module
# Cloudflared installation and Tunnel configuration
# ============================================================================

# Load Utils
[ -z "$(type -t log_info)" ] && source "$(dirname "$0")/utils.sh"

install_argo_core() {
    log_info "检查 Argo 环境..."
    local out="$HOME/agsbx/cloudflared"
    if [ -f "$out" ] && [ -x "$out" ]; then
        if "$out" --version >/dev/null 2>&1; then
            local cf_ver=$("$out" --version 2>/dev/null | awk '{print $3}')
            log_info "检测到本地已存在有效的 Cloudflared 内核 ($cf_ver)，跳过下载。"
            return 0
        fi
        log_warn "检测到本地 Cloudflared 内核异常，将重新下载安装。"
        rm -f "$out"
    fi

    log_info "下载 Cloudflared-argo 核心..."
    require_jq

    local repo="cloudflare/cloudflared"
    local latest_url="https://api.github.com/repos/$repo/releases/latest"
    local release_json=""
    if command -v curl >/dev/null 2>&1; then
        release_json=$(curl -fsSL --connect-timeout 8 --max-time 15 "$latest_url" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        release_json=$(timeout 15 wget -qO- "$latest_url" 2>/dev/null)
    fi

    local target_name="cloudflared-linux-$cpu"
    local asset_api_url=""
    local download_url=""
    if [ -n "$release_json" ]; then
        asset_api_url=$(echo "$release_json" | jq -r --arg n "$target_name" '.assets[] | select(.name == $n) | .url' 2>/dev/null | head -n1)
        download_url=$(echo "$release_json" | jq -r --arg n "$target_name" '.assets[] | select(.name == $n) | .browser_download_url' 2>/dev/null | head -n1)
        [ "$asset_api_url" = "null" ] && asset_api_url=""
        [ "$download_url" = "null" ] && download_url=""
    fi
    [ -z "$download_url" ] && download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/$target_name"

    local temp_bin="$HOME/agsbx/cloudflared.tmp"
    rm -f "$temp_bin"

    # Tier 1: GitHub API stream (bypasses GitHub 504 gateway timeout, direct to Azure/Fastly)
    if [ -n "$asset_api_url" ] && command -v curl >/dev/null 2>&1; then
        log_info "正在通过 GitHub API 流下载 Cloudflared..."
        curl -fL -sS --connect-timeout 10 --max-time 180 --retry 2 \
             -H "Accept: application/octet-stream" \
             -o "$temp_bin" "$asset_api_url" 2>/dev/null
    fi

    # Tier 2: Official browser release download
    if [ ! -f "$temp_bin" ] || [ $(wc -c < "$temp_bin" 2>/dev/null || echo 0) -lt 5000000 ]; then
        rm -f "$temp_bin"
        log_info "尝试官方 Release 链接下载 Cloudflared..."
        if command -v curl >/dev/null 2>&1; then
            curl -fL -sS --connect-timeout 10 --max-time 180 --retry 2 -o "$temp_bin" "$download_url" 2>/dev/null
        elif command -v wget >/dev/null 2>&1; then
            timeout 180 wget -q -O "$temp_bin" --tries=2 "$download_url" 2>/dev/null
        fi
    fi

    # Tier 3: Mirrors
    if [ ! -f "$temp_bin" ] || [ $(wc -c < "$temp_bin" 2>/dev/null || echo 0) -lt 5000000 ]; then
        rm -f "$temp_bin"
        for mirror in "https://ghproxy.net/" "https://gh-proxy.com/"; do
            log_info "尝试加速镜像下载 Cloudflared ($mirror)..."
            if command -v curl >/dev/null 2>&1; then
                curl -fL -sS --connect-timeout 10 --max-time 180 --retry 1 -o "$temp_bin" "${mirror}${download_url}" 2>/dev/null
            elif command -v wget >/dev/null 2>&1; then
                timeout 180 wget -q -O "$temp_bin" --tries=1 "${mirror}${download_url}" 2>/dev/null
            fi
            if [ -f "$temp_bin" ] && [ $(wc -c < "$temp_bin" 2>/dev/null || echo 0) -gt 5000000 ]; then
                break
            fi
            rm -f "$temp_bin"
        done
    fi

    if [ -f "$temp_bin" ] && [ $(wc -c < "$temp_bin" 2>/dev/null || echo 0) -gt 5000000 ]; then
        chmod +x "$temp_bin"
        if "$temp_bin" --version >/dev/null 2>&1; then
            mv "$temp_bin" "$out"
            chmod +x "$out"
            local cf_ver=$("$out" --version 2>/dev/null | awk '{print $3}')
            log_info "已成功安装 Cloudflared 内核: $cf_ver"
            return 0
        fi
    fi

    rm -f "$temp_bin"
    log_error "Cloudflared 下载或校验失败"
    return 1
}

disable_argo_core() {
    log_info "检查并停用 Argo 隧道服务..."
    if [ "$SYS_INIT" == "systemd" ] && systemctl is-active --quiet argo 2>/dev/null; then
        systemctl stop argo >/dev/null 2>&1
        systemctl disable argo >/dev/null 2>&1
    elif [ "$SYS_INIT" == "openrc" ] && rc-service argo status 2>/dev/null | grep -q started; then
        rc-service argo stop >/dev/null 2>&1
        rc-update del argo default >/dev/null 2>&1
    else
        kill -15 $(pgrep -f 'cloudflared' 2>/dev/null) >/dev/null 2>&1
    fi
    rm -f "$HOME/agsbx/argo.log"
}

configure_argo_tunnel() {
    # On re-installs, argo/vmag/ARGO_AUTH/ARGO_DOMAIN may only exist in config.env
    # (init_config only processes env vars, config.env is not yet loaded at this point)
    # Save env-var-sourced values so they take priority over config.env
    local _saved_argo="$argo" _saved_auth="$ARGO_AUTH" _saved_domain="$ARGO_DOMAIN"
    [ -f "$HOME/agsbx/config.env" ] && source "$HOME/agsbx/config.env"
    # Restore env vars (env vars override config.env)
    [ -n "$_saved_argo" ] && argo="$_saved_argo"
    [ -n "$_saved_auth" ] && ARGO_AUTH="$_saved_auth"
    [ -n "$_saved_domain" ] && ARGO_DOMAIN="$_saved_domain"
    # Check if Argo is requested
    [ -z "$argo" ] && return 0
    [ "$argo" = "no" ] && { disable_argo_core; return 0; }
    [ "$argo" != "yes" ] && { disable_argo_core; return 0; }

    log_info "启用 Cloudflared-argo 内核"
    install_argo_core
    
    # Pre-assign port if not yet available
    if [ -z "$port_argo_ws" ]; then
        port_argo_ws=$(shuf -i 10000-65535 -n 1)
        update_config_var "port_argo_ws" "$port_argo_ws"
    fi
    argoport="${port_argo_ws}"
    update_config_var "argoport" "$argoport"

    if [ -n "${ARGO_DOMAIN}" ] && [ -n "${ARGO_AUTH}" ]; then
        # ============================================================
        # 固定隧道 (Token 模式)
        # 入站路由由 Cloudflare Zero Trust 仪表盘远程管理：
        #   Zero Trust → Networks → Tunnels → [隧道名] → Public Hostname
        #   配置域名指向 http://localhost:${argoport}
        # 命令中不使用 --url（该参数仅适用于临时隧道）
        # ============================================================
        argoname='固定'
        log_info "配置固定 Argo 隧道 (端口: $argoport)"
        log_warn "请确保已在 Cloudflare 仪表盘配置入站规则: ${ARGO_DOMAIN} → http://localhost:${argoport}"
        
        if [ "$SYS_INIT" == "systemd" ]; then
            cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=argo service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
LimitNPROC=512000
LimitNOFILE=512000
TimeoutStartSec=0
ExecStart=${HOME}/agsbx/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "${ARGO_AUTH}"
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload >/dev/null 2>&1
            systemctl enable argo >/dev/null 2>&1
            systemctl start argo >/dev/null 2>&1
        elif [ "$SYS_INIT" == "openrc" ]; then
            cat > /etc/init.d/argo <<EOF
#!/sbin/openrc-run
description="argo service"
command="${HOME}/agsbx/cloudflared tunnel"
command_args="--no-autoupdate --edge-ip-version auto --protocol http2 run --token ${ARGO_AUTH}"
pidfile="/run/argo.pid"
command_background="yes"
depend() {
need net
}
EOF
            chmod +x /etc/init.d/argo >/dev/null 2>&1
            rc-update add argo default >/dev/null 2>&1
            rc-service argo start >/dev/null 2>&1
        else
            nohup "$HOME/agsbx/cloudflared" tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "${ARGO_AUTH}" >/dev/null 2>&1 &
        fi
        
        update_config_var "sbargoym" "${ARGO_DOMAIN}"
        update_config_var "sbargotoken" "${ARGO_AUTH}"
    else
        # ============================================================
        # 临时隧道 (Quick Tunnel 模式)
        # --url 指定本地回源端口，CF 自动分配 trycloudflare.com 域名
        # ============================================================
        argoname='临时'
        log_info "申请临时 Argo 隧道 (回源端口: $argoport)"
        nohup "$HOME/agsbx/cloudflared" tunnel --url http://localhost:${argoport} --edge-ip-version auto --no-autoupdate --protocol http2 > $HOME/agsbx/argo.log 2>&1 &
    fi
    
    log_info "申请 Argo$argoname 隧道中……请稍等"
    sleep 8
    
    if [ -n "${ARGO_DOMAIN}" ] && [ -n "${ARGO_AUTH}" ]; then
        argodomain="${ARGO_DOMAIN}"
    else
        argodomain=$(grep -a trycloudflare.com "$HOME/agsbx/argo.log" 2>/dev/null | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
    fi
    
    if [ -n "${argodomain}" ]; then
        log_info "Argo$argoname 隧道申请成功: $argodomain"
    else
        log_error "Argo$argoname 隧道申请失败，请稍后再试"
    fi
}

check_argo_status() {
    if pgrep -f 'agsbx/c' >/dev/null 2>&1 || pgrep -f 'cloudflared' >/dev/null 2>&1; then
        local ver=$("$HOME/agsbx/cloudflared" version 2>/dev/null | awk '{print $3}')
        echo "Argo (版本V$ver)：运行中"
    else
        echo "Argo：未启用"
    fi
}
