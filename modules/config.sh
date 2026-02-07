#!/bin/bash

# ============================================================================
# Config Module
# Handles variable initialization, UUID generation, and config validation
# ============================================================================

# Load Utils (if not already loaded)
[ -z "$(type -t log_info)" ] && source "$(dirname "$0")/utils.sh"

init_config() {
    # Process Environment Variables with Precedence
    # If env var (e.g. vlpt) is set, it overrides config file.
    
    process_env() {
        if [ -n "${!1+x}" ]; then
            export $2="yes"
            [ "${!1}" != "yes" ] && export $3="${!1}"
        fi
    }

    process_env vlpt vlp port_vl_re
    process_env vmpt vmp port_vm_ws
    process_env vwpt vwp port_vw
    process_env hypt hyp port_hy2
    process_env tupt tup port_tu
    process_env xhpt xhp port_xh
    process_env vxpt vxp port_vx
    process_env anpt anp port_an
    process_env arpt arp port_ar
    process_env sspt ssp port_ss
    process_env sopt sop port_so

    # WARP
    [ -n "${warp+x}" ] || warp=${wap:-''}
    
    # Export Standard Variables (Preserve existing if not overridden)
    if [ -n "$uuid" ]; then
        update_config_var "uuid" "$uuid"
    else
        export uuid=${uuid:-''}
    fi
        
    [ -n "$ippz" ] && update_config_var "ippz" "$ippz"

    export port_vl_re port_vm_ws port_vw port_hy2 port_tu port_xh port_vx port_an port_ar port_ss port_so
    export ym_vl_re=${reym:-''}
    export cdnym=${cdnym:-''}
    export argo=${argo:-''}
    export ARGO_DOMAIN=${agn:-''}
    export ARGO_AUTH=${agk:-''}
    export ippz=${ippz:-''}
    export warp=${warp:-''}
    export name=${name:-''}
    export oap=${oap:-''}
    
    # URLs
    export v46url="https://icanhazip.com"
    export agsbxurl="https://raw.githubusercontent.com/wowcosplayg/sbxargo/main/sbxargo.sh"
}

insuuid(){
    if [ -n "$uuid" ]; then
        echo "$uuid" > "$HOME/agsbx/uuid"
        chmod 600 "$HOME/agsbx/uuid"
    else
        # Allow checking existing uuid
         if [ -s "$HOME/agsbx/uuid" ]; then
            uuid=$(cat "$HOME/agsbx/uuid")
        else
            uuid=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
            echo "$uuid" > "$HOME/agsbx/uuid"
            chmod 600 "$HOME/agsbx/uuid"
        fi
    fi
    log_info "UUID: $uuid"
}

validate_env_vars() {
    # Check if at least one protocol is active
    if [ "$vwp" = yes ] || [ "$sop" = yes ] || [ "$vxp" = yes ] || [ "$ssp" = yes ] || [ "$vlp" = yes ] || [ "$vmp" = yes ] || [ "$hyp" = yes ] || [ "$tup" = yes ] || [ "$xhp" = yes ] || [ "$anp" = yes ] || [ "$arp" = yes ]; then
        return 0
    fi
     # If purely non-interactive and no config, fail
    if [ ! -t 0 ]; then
        log_error "未检测到有效配置。请先运行通过脚本生成配置文件或设置环境变量。"
        exit 1
    fi
}



update_config_var() {
    local key="$1"
    local value="$2"
    local config_dir="$HOME/agsbx"
    local config_file="$config_dir/config.env"
    
    # Ensure dir exists
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
    fi
    
    # 1. Update in-memory variable
    export "${key}=${value}"
    
    # 2. Update config file
    if [ -f "$config_file" ]; then
        if grep -q "^${key}=" "$config_file"; then
            # Update existing line
            sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$config_file"
        else
            # Append new line
            echo "${key}=\"${value}\"" >> "$config_file"
        fi
    else
        # Create new file
        echo "${key}=\"${value}\"" > "$config_file"
        chmod 600 "$config_file"
    fi
}

load_config() {
    local config_file="$HOME/agsbx/config.env"
    if [ -f "$config_file" ]; then
        log_info "加载配置文件: $config_file"
        source "$config_file"
    fi
    
    # Init defaults after load
    init_config
}

interactive_config() {
    echo "========================================================="
    echo "   Argosbx 交互式配置向导"
    echo "========================================================="
    
    # Check existing config to pre-fill
    [ -f "$HOME/agsbx/config.env" ] && source "$HOME/agsbx/config.env"
    
    # Helper to get current port/value
    get_v() { cat "$HOME/agsbx/$1" 2>/dev/null; }

    # Reality Domain Config
    echo "---------------------------------------------------------"
    local curr_ym=$(get_v ym_vl_re)
    [ -n "$curr_ym" ] || curr_ym="www.apple.com"
    read -p "请输入 Reality 偷取域名 (默认: $curr_ym): " input_ym
    ym_vl_re="${input_ym:-$curr_ym}"
    update_config_var "ym_vl_re" "$ym_vl_re"

    # CDN Domain Config (for XHTTP/WS)
    local curr_cdn=$(get_v cdnym)
    read -p "请输入优选 CDN 域名 (可选, 回车跳过): " input_cdn
    cdnym="${input_cdn:-$curr_cdn}"
    [ -n "$cdnym" ] && update_config_var "cdnym" "$cdnym"
    
    # Routing Default
    xryx="IPOnDemand"
    wxryx="IPOnDemand"
    
    echo "---------------------------------------------------------"

    # VLESS-Reality
    local curr=${port_vl_re:-$(get_v port_vl_re)}
    local hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 VLESS-Reality [推荐] (适合大部分网络环境)? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        vlp=yes
        read -p "请输入端口 ($hint): " input_port
        port_vl_re="${input_port:-$curr}"
    else
        vlp=no
    fi
    update_config_var "vlp" "$vlp"
    [ "$vlp" = "yes" ] && update_config_var "port_vl_re" "$port_vl_re"

    # Hysteria2
    curr=${port_hy2:-$(get_v port_hy2)}
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Hysteria2 [推荐] (暴力加速，适合线路差环境)? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        hyp=yes
        read -p "请输入端口 ($hint): " input_port
        port_hy2="${input_port:-$curr}"
    else
        hyp=no
    fi
    update_config_var "hyp" "$hyp"
    [ "$hyp" = "yes" ] && update_config_var "port_hy2" "$port_hy2"

    # Tuic
    curr=${port_tu:-$(get_v port_tu)}
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Tuic V5 [推荐] (低延迟，高性能)? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        tup=yes
        read -p "请输入端口 ($hint): " input_port
        port_tu="${input_port:-$curr}"
    else
        tup=no
    fi
    update_config_var "tup" "$tup"
    [ "$tup" = "yes" ] && update_config_var "port_tu" "$port_tu"

    # Vless-XHTTP
    curr=${port_xh:-$(get_v port_xh)}
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Vless-XHTTP (新协议)? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        xhp=yes
        read -p "请输入端口 ($hint): " input_port
        port_xh="${input_port:-$curr}"
    else
        xhp=no
    fi
    update_config_var "xhp" "$xhp"
    [ "$xhp" = "yes" ] && update_config_var "port_xh" "$port_xh"
    
    # Vless-XHTTP-ENC (New)
    curr=${port_vx:-$(get_v port_vx)}
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Vless-XHTTP-ENC (带加密)? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        vxp=yes
        read -p "请输入端口 ($hint): " input_port
        port_vx="${input_port:-$curr}"
    else
        vxp=no
    fi
    update_config_var "vxp" "$vxp"
    [ "$vxp" = "yes" ] && update_config_var "port_vx" "$port_vx"

    # VMess-xhttp
    curr=${port_vm_ws:-$(get_v port_vm_ws)}
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 VMess-xhttp (通用性好)? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        vmp=yes
        read -p "请输入端口 ($hint): " input_port
        port_vm_ws="${input_port:-$curr}"
    else
        vmp=no
    fi
    update_config_var "vmp" "$vmp"
    [ "$vmp" = "yes" ] && update_config_var "port_vm_ws" "$port_vm_ws"
    
    # Vless-WS-CDN
    curr=${port_vw:-$(get_v port_vw)}
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Vless-WS-CDN (Vless-xhttp模式)? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        vwp=yes
        read -p "请输入端口 ($hint): " input_port
        port_vw="${input_port:-$curr}"
    else
        vwp=no
    fi
    update_config_var "vwp" "$vwp"
    [ "$vwp" = "yes" ] && update_config_var "port_vw" "$port_vw"

    # Shadowsocks
    curr=${port_ss:-$(get_v port_ss)}
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Shadowsocks-2022? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        ssp=yes
        read -p "请输入端口 ($hint): " input_port
        port_ss="${input_port:-$curr}"
    else
        ssp=no
    fi
    update_config_var "ssp" "$ssp"
    [ "$ssp" = "yes" ] && update_config_var "port_ss" "$port_ss"
    
    # AnyTLS
    curr=${port_an:-$(get_v port_an)}
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 AnyTLS (Sing-box)? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        anp=yes
        read -p "请输入端口 ($hint): " input_port
        port_an="${input_port:-$curr}"
    else
        anp=no
    fi
    update_config_var "anp" "$anp"
    [ "$anp" = "yes" ] && update_config_var "port_an" "$port_an"
    
    # Any-Reality
    curr=${port_ar:-$(get_v port_ar)}
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Any-Reality (Sing-box Reality)? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        arp=yes
        read -p "请输入端口 ($hint): " input_port
        port_ar="${input_port:-$curr}"
    else
        arp=no
    fi
    update_config_var "arp" "$arp"
    [ "$arp" = "yes" ] && update_config_var "port_ar" "$port_ar"

    # Socks5
    curr=${port_so:-$(get_v port_so)}
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Socks5? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        sop=yes
        read -p "请输入端口 ($hint): " input_port
        port_so="${input_port:-$curr}"
    else
        sop=no
    fi
    update_config_var "sop" "$sop"
    [ "$sop" = "yes" ] && update_config_var "port_so" "$port_so"
    
    # UUID Config
    echo "---------------------------------------------------------"
    local curr_uuid=$(cat "$HOME/agsbx/uuid" 2>/dev/null)
    [ -n "$uuid" ] && curr_uuid="$uuid"
    
    local uuid_hint="默认随机"
    [ -n "$curr_uuid" ] && uuid_hint="当前: $curr_uuid"
    
    read -p "是否自定义 UUID? (y/n, $uuid_hint): " uuid_choice
    if [[ "$uuid_choice" == "y" ]]; then
        read -p "请输入您的 UUID (回车保持当前/随机): " input_uuid
        if [ -n "$input_uuid" ]; then
             uuid="$input_uuid"
        elif [ -n "$curr_uuid" ]; then
             uuid="$curr_uuid"
        fi
    else
        [ -n "$curr_uuid" ] && uuid="$curr_uuid"
    fi
    if [ -z "$uuid" ]; then
        uuid=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    fi
    update_config_var "uuid" "$uuid"
    
    
    # IP Config (New)
    echo "---------------------------------------------------------"
    read -p "是否手动指定公网 IP (解决 Docker 内无法获取 IP 问题)? (y/n): " ip_choice
    if [[ "$ip_choice" == "y" ]]; then
        read -p "请输入公网 IP: " input_ip
        [ -n "$input_ip" ] && ippz="$input_ip"
        update_config_var "ippz" "$ippz"
    fi

    echo "---------------------------------------------------------"
    echo "   高级功能配置 (Argo / WARP)"
    echo "---------------------------------------------------------"
    
    # Argo Config
    read -p "是否启用 Argo 隧道? (y/n): " choice
    if [[ "$choice" == "y" ]]; then
        echo "  [1] 临时隧道"
        echo "  [2] 固定隧道"
        read -p "  请选择 (1/2): " argo_sel
        if [[ "$argo_sel" == "2" ]]; then
             read -p "  请输入 Cloudflare Tunnel Token: " agk
             read -p "  请输入您的域名: " agn
             export ARGO_AUTH=$agk
             export ARGO_DOMAIN=$agn
             update_config_var "ARGO_AUTH" "$agk"
             update_config_var "ARGO_DOMAIN" "$agn"
        fi
        argo="vmpt"
        if [ "$vmp" != "yes" ]; then
             echo "  * 已自动为您启用 Argo 依赖的 VMess 协议"
             vmp=yes
             update_config_var "vmp" "yes"
        fi
        update_config_var "argo" "vmpt"
    else
        argo=no
        update_config_var "argo" "no"
    fi
    
    # WARP Config
    read -p "是否启用 WARP? (y/n): " choice
    if [[ "$choice" == "y" ]]; then
        echo "  [1] 全局接管"
        echo "  [2] 仅 IPv6 优先"
        read -p "  请选择 (1/2): " warp_sel
        if [[ "$warp_sel" == "1" ]]; then
             warp="x6" 
        fi
        
        # Ask for keys
        read -p "  请输入 WARP IPv6 (留空则使用默认/环境变量): " input_wipv6
        read -p "  请输入 WARP Private Key (留空则使用默认/环境变量): " input_wpvk
        read -p "  请输入 WARP Reserved (格式 [a,b,c], 留空默认): " input_wres
        
        [ -n "$input_wipv6" ] && update_config_var "WARP_IPV6" "$input_wipv6"
        [ -n "$input_wpvk" ] && update_config_var "WARP_PRIVATE_KEY" "$input_wpvk" 
        [ -n "$input_wres" ] && update_config_var "WARP_RESERVED" "$input_wres"
        
        update_config_var "warp" "$warp"
    else
        warp=no
        update_config_var "warp" "no"
    fi

    echo "========================================================="
    echo "   配置收集完成"
    echo "========================================================="

    # Default fallback
    if [ "$vlp" != "yes" ] && [ "$hyp" != "yes" ] && [ "$tup" != "yes" ] && [ "$xhp" != "yes" ] && [ "$vxp" != "yes" ] && [ "$vmp" != "yes" ] && [ "$vwp" != "yes" ] && [ "$ssp" != "yes" ] && [ "$anp" != "yes" ] && [ "$arp" != "yes" ] && [ "$sop" != "yes" ]; then
        log_warn "未选择任何协议，默认启用 Socks5 端口 50000"
        sop=yes
        port_so=50000
        update_config_var "sop" "yes"
        update_config_var "port_so" "50000"
    fi
}
