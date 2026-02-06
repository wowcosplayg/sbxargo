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
