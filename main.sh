#!/bin/bash

# ============================================================================
# Main Orchestrator for Argosbx (Modular)
# ============================================================================

# Source Modules
BASE_DIR="$(dirname "$0")"
source "$BASE_DIR/modules/utils.sh"
source "$BASE_DIR/modules/config.sh"
source "$BASE_DIR/modules/install.sh"
source "$BASE_DIR/modules/warp.sh"
source "$BASE_DIR/modules/argo.sh"
source "$BASE_DIR/modules/xray.sh"
source "$BASE_DIR/modules/singbox.sh"

# Global Config
init_config

    
# Configuration Generation Logic (Extracted for Auto-Update)
regenerate_config() {
    log_info "正在重新生成配置文件..."
    
    # 4. Load Configuration (Non-Interactive)
    load_config
    
    # Ensure UUID is set
    insuuid
    
    # 6. Generate Keys & Configs
    generate_xray_keys
    generate_singbox_keys
    
    init_xray_config
    init_singbox_config
    
    # 7. Add Protocols
    # Xray
    add_reality_xray
    add_xhttp_xray
    add_vmess_xray
    add_socks_xray
    add_argo_inbound_xray
    
    # Sing-box
    add_hysteria2_singbox
    add_tuic_singbox
    add_anytls_singbox
    add_anyreality_singbox
    add_shadowsocks_singbox
    add_vmess_singbox
    add_socks_singbox
    
    # 8. Add WARP & Routing
    check_warp_availability
    configure_warp_routing
    
    configure_xray_outbound
    configure_singbox_outbound
    
    # 10. Show Info
    generate_all_links
    
    log_info "配置重新生成完成！"
}

# Main Installation Flow
install_flow() {
    local type="$1"
    
    # 1. System Check
    check_system_compatibility
    get_server_ip
    
    # 2. Interactive Config (only if terminal is interactive and no config exists)
    if [ -t 0 ]; then
        validate_env_vars || interactive_config
    else
        validate_env_vars
    fi
    
    # 3. Install Dependencies
    install_dependencies
    
    # 4. System Optimization
    optimize_system
    enable_bbr
    
    # 5. Core Installation
    # Check if we need to install/update cores
    install_xray_core || { log_error "Xray 安装失败"; exit 1; }
    install_singbox_core || { log_error "Sing-box 安装失败"; exit 1; }
    configure_argo_tunnel || { log_error "Argo 配置失败"; exit 1; }
    
    # Run Generation Logic
    regenerate_config || { log_error "配置生成失败"; exit 1; }
    
    # 9. Start Services
    start_xray_service
    start_singbox_service
    check_argo_status
    
    log_info "Argosbx 部署完成！"
}

# Command Line Args Handling
# Handle Actions
handle_action() {
    local action="$1"
    
    case "$action" in
        del|uninstall)
            log_info "正在卸载 Argosbx..."
    
            # 1. Stop Services
            for svc in xr sb arog xray sing-box cloudflared; do 
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl stop $svc 2>/dev/null
                    systemctl disable $svc 2>/dev/null
                fi
            done
            
            # 2. Kill Processes
            killall -9 xray sing-box cloudflared 2>/dev/null
            
            # 3. Remove Service Files
            rm -f /etc/systemd/system/xr.service \
                  /etc/systemd/system/sb.service \
                  /etc/systemd/system/arog.service \
                  /etc/systemd/system/xray.service \
                  /etc/systemd/system/sing-box.service \
                  /etc/systemd/system/cloudflared.service
                  
            if command -v systemctl >/dev/null 2>&1; then
                systemctl daemon-reload
            fi
            
            # 4. Remove Sysctl Optimization Config
            if [ -f "/etc/sysctl.d/99-argosbx.conf" ]; then
                log_info "移除内核优化配置..."
                rm -f "/etc/sysctl.d/99-argosbx.conf"
            fi
            
            # 5. Remove Docker Container (If exists on Host)
            if command -v docker >/dev/null 2>&1; then
                if docker ps -a --format '{{.Names}}' | grep -q "^argosbx$"; then
                    log_info "发现 Docker 容器 'argosbx'，正在删除..."
                    docker rm -f argosbx >/dev/null 2>&1
                fi
            fi
            
            # 6. Remove Workspace
            rm -rf "$HOME/agsbx"
            
            log_info "卸载完成. 欢迎下次使用！(部分内核参数优化将在重启后还原)"
            exit 0
            ;;
        list|info)
            if [ -f "$HOME/agsbx/jh.txt" ]; then
                echo "=== 节点链接 ==="
                cat "$HOME/agsbx/jh.txt"
                echo ""
            else
                log_warn "未找到节点文件"
            fi
            if [ -f "$HOME/agsbx/ports.conf" ]; then
                echo "=== 端口占用 ==="
                cat "$HOME/agsbx/ports.conf"
                echo ""
            fi
            # Show subscription files path
            if [ -f "$HOME/agsbx/v2ray_sub.txt" ]; then
                echo "V2Ray 订阅文件: $HOME/agsbx/v2ray_sub.txt"
            fi
            exit 0
            ;;
        install|update)
            install_flow "install"
            ;;
        regen)
            check_system_compatibility
            regenerate_config
            # Restart services to apply changes
            if command -v systemctl >/dev/null 2>&1; then
                systemctl restart xr sb argo
                log_info "Configuration regenerated and services restarted."
            else
                log_info "Configuration regenerated. Please restart services manually or via Docker restart."
            fi
            ;;
        regen_no_restart)
            check_system_compatibility
            regenerate_config
            log_info "Configuration regenerated (No Restart)."
            ;;
        service_start)
            # Docker restart path: config already exists in volume.
            # Only restart processes — no config regeneration, no HTTP probes.
            check_system_compatibility
            load_config
            start_xray_service
            start_singbox_service
            # Restart Argo if enabled — kill any existing cloudflared first
            if [ "$argo" = "yes" ]; then
                kill -15 $(pgrep -f 'agsbx/cloudflared' 2>/dev/null) 2>/dev/null
                sleep 1
                # Read fixed tunnel credentials from environment or config.env
                local _argo_auth="${ARGO_AUTH:-$(grep "^sbargotoken=" "$HOME/agsbx/config.env" 2>/dev/null | cut -d'=' -f2- | tr -d '"'\''')}"
                local _argo_domain="${ARGO_DOMAIN:-$(grep "^sbargoym=" "$HOME/agsbx/config.env" 2>/dev/null | cut -d'=' -f2- | tr -d '"'\''')}"

                if [ -n "$_argo_auth" ] && [ -n "$_argo_domain" ]; then
                    nohup "$HOME/agsbx/cloudflared" tunnel \
                        --no-autoupdate --edge-ip-version auto --protocol http2 \
                        run --token "$_argo_auth" > /dev/null 2>&1 &
                elif [ -n "$port_argo_ws" ]; then
                    nohup "$HOME/agsbx/cloudflared" tunnel \
                        --url "http://localhost:${port_argo_ws}" \
                        --edge-ip-version auto --no-autoupdate --protocol http2 \
                        > "$HOME/agsbx/argo.log" 2>&1 &
                    
                    sleep 8
                    local argodomain=$(grep -a trycloudflare.com "$HOME/agsbx/argo.log" 2>/dev/null \
                        | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
                    if [ -n "$argodomain" ]; then
                        update_config_var "sbargoym" "$argodomain"
                        log_info "新临时 Argo 域名: $argodomain"
                        generate_all_links
                    fi
                fi
            fi
            check_argo_status
            log_info "服务进程已重启！"
            ;;
        fast_start)
            # Legacy alias — same as service_start for Docker
            check_system_compatibility
            get_server_ip
            regenerate_config
            start_xray_service
            start_singbox_service
            configure_argo_tunnel
            check_argo_status
            log_info "服务核心已快速热重启！"
            ;;
        *)
            log_error "未知参数: $action"
            exit 1
            ;;
    esac
}

# Main Menu
show_menu() {
    clear
    echo "========================================================="
    echo "   Argosbx 全能脚本 - 管理菜单"
    echo "========================================================="
    echo "   1. 安装 / 更新 (保留配置)"
    echo "   2. 查看节点信息 (Links & Ports)"
    echo "   3. 卸载脚本 (Clean Uninstall)"
    echo "   0. 退出脚本"
    echo "========================================================="
    read -p "请选择 [1-3]: " choice
    
    case "$choice" in
        1)
            handle_action "install"
            ;;
        2)
            handle_action "list"
            ;;
        3)
            read -p "确定要卸载吗？(y/n): " confirm
            if [[ "$confirm" == "y" ]]; then
                handle_action "del"
            else
                echo "已取消"
            fi
            ;;
        0)
            echo "退出."
            exit 0
            ;;
        *)
            echo "无效输入"
            exit 1
            ;;
    esac
}

# Entry Point
if [ -n "$1" ]; then
    handle_action "$1"
else
    show_menu
fi
