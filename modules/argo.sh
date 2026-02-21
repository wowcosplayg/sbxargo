#!/bin/bash

# ============================================================================
# Argo Module
# Cloudflared installation and Tunnel configuration
# ============================================================================

# Load Utils
[ -z "$(type -t log_info)" ] && source "$(dirname "$0")/utils.sh"

install_argo_core() {
    log_info "检查 Argo 环境..."
    if [ ! -e "$HOME/agsbx/cloudflared" ]; then
        if command -v curl >/dev/null 2>&1; then
            argocore=$(curl -Ls https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared | grep -Eo '"[0-9.]+"' | sed -n 1p | tr -d '",')
        else
            argocore=$(wget -qO- https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared | grep -Eo '"[0-9.]+"' | sed -n 1p | tr -d '",')
        fi
        log_info "下载 Cloudflared-argo 最新正式版内核：$argocore"
        
        local url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu"
        local out="$HOME/agsbx/cloudflared"
        
        if command -v curl >/dev/null 2>&1; then
            curl -Lo "$out" -# --retry 2 "$url"
        elif command -v wget >/dev/null 2>&1; then
            timeout 30 wget -O "$out" --tries=2 "$url"
        fi
        
        chmod +x "$HOME/agsbx/cloudflared"
    fi
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
ExecStart=${HOME}/agsbx/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol auto --token "${ARGO_AUTH}"
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
command_args="--no-autoupdate --edge-ip-version auto --protocol auto --token ${ARGO_AUTH}"
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
            nohup "$HOME/agsbx/cloudflared" tunnel --no-autoupdate --edge-ip-version auto --protocol auto --token "${ARGO_AUTH}" >/dev/null 2>&1 &
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
        nohup "$HOME/agsbx/cloudflared" tunnel --url http://localhost:${argoport} --edge-ip-version auto --no-autoupdate --protocol auto > $HOME/agsbx/argo.log 2>&1 &
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
