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
if [ "$1" = "del" ]; then
    log_info "正在卸载 Argosbx..."
    # Kill processes
    for svc in xr sb arog; do systemctl stop $svc 2>/dev/null; done
    killall -9 xray sing-box cloudflared 2>/dev/null
    rm -rf "$HOME/agsbx"
    log_info "卸载完成. 欢迎下次使用！"
    exit 0
elif [ "$1" = "list" ]; then
    # Show info logic
    # Ideally reuse cip logic or just cat the jh.txt if exists
    if [ -f "$HOME/agsbx/jh.txt" ]; then
        cat "$HOME/agsbx/jh.txt"
    else
        log_warn "未找到节点文件"
    fi
     # List ports
    if [ -f "$HOME/agsbx/ports.conf" ]; then
        cat "$HOME/agsbx/ports.conf"
    fi
    exit 0
fi

# Main Installation Flow
install_flow() {
    # 1. System Check & Dependencies
    check_system_compatibility || exit 1
    install_dependencies
    
    # 2. Config & UUID
    validate_env_vars "$1"
    validate_env_vars "$1"
    insuuid
    
    # 3. Get Public IP
    get_server_ip
    
    # 4. WARP Routing Decision
    check_warp_availability
    configure_warp_routing
    
    # 5. Determine Kernels
    local use_sb=false
    local use_xray=false
    
    # Check Sing-box specific protocols
    if [ -n "$hyp" ] || [ -n "$tup" ] || [ -n "$anp" ] || [ -n "$arp" ] || [ -n "$ssp" ]; then
        use_sb=true
    fi
    
    # Check Xray specific protocols
    if [ -n "$xhp" ] || [ -n "$vlp" ] || [ -n "$vxp" ] || [ -n "$vwp" ]; then
        use_xray=true
    fi
    
    # Default fallback: If neither specific set is selected, but VMess/Socks is, default to Xray
    # (Matching original script behavior)
    if [ "$use_sb" = false ] && [ "$use_xray" = false ]; then
        use_xray=true
    fi
    
    log_info "内核选择: Xray=$use_xray, Sing-box=$use_sb"
    
    # 5. Xray Installation & Configuration
    if [ "$use_xray" = true ]; then
        install_xray_core
        generate_xray_keys
        init_xray_config
        
        add_reality_xray
        add_xhttp_xray
        
        # Cross-platform protocols (VMess, Socks) go to Xray if Xray is active
        add_vmess_xray
        add_socks_xray
        
        configure_xray_outbound
        start_xray_service
    fi
    
    # 6. Sing-box Installation & Configuration
    if [ "$use_sb" = true ]; then
        install_singbox_core
        generate_singbox_keys
        init_singbox_config
        
        add_hysteria2_singbox
        add_tuic_singbox
        add_anytls_singbox
        add_anyreality_singbox
        add_shadowsocks_singbox
        
        # If Xray is NOT active, VMess/Socks go here
        if [ "$use_xray" = false ]; then
            add_vmess_singbox
            add_socks_singbox
        fi
        
        configure_singbox_outbound
        start_singbox_service
    fi
    
    # 7. Argo
    configure_argo_tunnel
    
    # 8. Finalize
    generate_port_config
    generate_all_links
    
    # Generate Links and Show Info (Logic to gather links into jh.txt)
    # Note: Link generation strings are constructed inside the add_* functions in the original script?
    # Actually, the original script constructed links inside a `list` function or `cip` or appended to `jh.txt` inside configuration?
    # Let's check: The original script `xrsbvm` etc. printed to console but didn't explicitly save links to `jh.txt` EXCEPT in `argosbxstatus` or similar?
    # Wait, viewing `sbxargo.sh` lines 2000+ showed `echo "$vma_link..." >> jh.txt`.
    # Ah, the link generation logic (constructing vmess:// strings) was NOT in the config functions in the original!
    # I missed extracting the link generation logic logic!
    # The original put config generation AND link string construction in `xrsbvm`?
    # Let's checks `xrsbvm` in `sbxargo.sh` again.
    
    # Code snippet from memory:
    # `vm_link="vmess://..."`
    # `echo "$vm_link" >> jh.txt` ? 
    # I need to verify where the links are generated.
    # If they are generated in the end, I need a separate "Generate Links" module or function in `utils.sh` that reads UUID/Ports and generates them.
}

# Run Install
install_flow "$@"
