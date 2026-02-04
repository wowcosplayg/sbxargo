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

configure_argo_tunnel() {
    # Check if Argo is requested
    [ -z "$argo" ] && return 0
    [ -z "$vmag" ] && return 0 # Check dependency on other protocols if needed (vmag is set in config if vmpt/vwpt)

    log_info "启用 Cloudflared-argo 内核"
    install_argo_core
    
    # Set helper file for port
    if [ "$argo" = "vmpt" ]; then 
        argoport=$(cat "$HOME/agsbx/port_vm_ws" 2>/dev/null)
        echo "Vmess" > "$HOME/agsbx/vlvm"
    elif [ "$argo" = "vwpt" ]; then 
        argoport=$(cat "$HOME/agsbx/port_vw" 2>/dev/null)
        echo "Vless" > "$HOME/agsbx/vlvm"
    fi
    echo "$argoport" > "$HOME/agsbx/argoport.log"

    if [ -n "${ARGO_DOMAIN}" ] && [ -n "${ARGO_AUTH}" ]; then
        argoname='固定'
        log_info "配置固定 Argo 隧道"
        
        if [ "$SYS_INIT" == "systemd" ]; then
            cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=argo service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=/root/agsbx/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "${ARGO_AUTH}"
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
command="/root/agsbx/cloudflared tunnel"
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
        
        echo "${ARGO_DOMAIN}" > "$HOME/agsbx/sbargoym.log"
        echo "${ARGO_AUTH}" > "$HOME/agsbx/sbargotoken.log"
    else
        argoname='临时'
        log_info "申请临时 Argo 隧道"
        nohup "$HOME/agsbx/cloudflared" tunnel --url http://localhost:$(cat $HOME/agsbx/argoport.log) --edge-ip-version auto --no-autoupdate --protocol http2 > $HOME/agsbx/argo.log 2>&1 &
    fi
    
    log_info "申请 Argo$argoname 隧道中……请稍等"
    sleep 8
    
    if [ -n "${ARGO_DOMAIN}" ] && [ -n "${ARGO_AUTH}" ]; then
        argodomain=$(cat "$HOME/agsbx/sbargoym.log" 2>/dev/null)
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
