#!/bin/bash

# ============================================================================
# Config Module
# Handles variable initialization, UUID generation, and config validation
# ============================================================================

# Load Utils (if not already loaded)
[ -z "$(type -t log_info)" ] && source "$(dirname "$0")/utils.sh"

init_config() {
    # Default variables from environment or install.sh
    [ -z "${vlpt+x}" ] || vlp=yes
    [ -z "${vmpt+x}" ] || { vmp=yes; vmag=yes; }
    [ -z "${vwpt+x}" ] || { vwp=yes; vmag=yes; }
    [ -z "${hypt+x}" ] || hyp=yes
    [ -z "${tupt+x}" ] || tup=yes
    [ -z "${xhpt+x}" ] || xhp=yes
    [ -z "${vxpt+x}" ] || vxp=yes
    [ -z "${anpt+x}" ] || anp=yes
    [ -z "${sspt+x}" ] || ssp=yes
    [ -z "${arpt+x}" ] || arp=yes
    [ -z "${sopt+x}" ] || sop=yes
    [ -z "${warp+x}" ] || wap=yes
    
    # Export Standard Variables
    # Export Standard Variables
    export uuid=${uuid:-''}
    
    # Handle ports: if set to 'yes', treat as empty (random), otherwise use value
    [ "$vlpt" = "yes" ] && port_vl_re="" || port_vl_re="${vlpt:-''}"
    [ "$vmpt" = "yes" ] && port_vm_ws="" || port_vm_ws="${vmpt:-''}"
    [ "$vwpt" = "yes" ] && port_vw="" || port_vw="${vwpt:-''}"
    [ "$hypt" = "yes" ] && port_hy2="" || port_hy2="${hypt:-''}"
    [ "$tupt" = "yes" ] && port_tu="" || port_tu="${tupt:-''}"
    [ "$xhpt" = "yes" ] && port_xh="" || port_xh="${xhpt:-''}"
    [ "$vxpt" = "yes" ] && port_vx="" || port_vx="${vxpt:-''}"
    [ "$anpt" = "yes" ] && port_an="" || port_an="${anpt:-''}"
    [ "$arpt" = "yes" ] && port_ar="" || port_ar="${arpt:-''}"
    [ "$sspt" = "yes" ] && port_ss="" || port_ss="${sspt:-''}"
    [ "$sopt" = "yes" ] && port_so="" || port_so="${sopt:-''}"

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
    else
        # Allow checking existing uuid
         if [ -s "$HOME/agsbx/uuid" ]; then
            uuid=$(cat "$HOME/agsbx/uuid")
        else
            uuid=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
            echo "$uuid" > "$HOME/agsbx/uuid"
        fi
    fi
    log_info "UUID: $uuid"
}

validate_env_vars() {
    # Check if at least one protocol is active if running installation
    if [ "$1" != "del" ] && [ "$1" != "rep" ]; then
        if [ "$vwp" = yes ] || [ "$sop" = yes ] || [ "$vxp" = yes ] || [ "$ssp" = yes ] || [ "$vlp" = yes ] || [ "$vmp" = yes ] || [ "$hyp" = yes ] || [ "$tup" = yes ] || [ "$xhp" = yes ] || [ "$anp" = yes ] || [ "$arp" = yes ]; then
            return 0
        fi
        
        # If no vars set, try interactive mode if TTY available
        if [ -t 0 ]; then
            interactive_config
        else 
            log_error "未安装argosbx脚本或未设置协议变量。请在运行脚本前设置至少一个协议变量。"
            exit 1
        fi
    fi
}

interactive_config() {
    # Check if autoset (Docker or Env Vars)
    if [ "$vlp" = "yes" ] || [ "$hyp" = "yes" ] || [ "$tup" = "yes" ] || \
       [ "$xhp" = "yes" ] || [ "$vxp" = "yes" ] || [ "$anp" = "yes" ] || \
       [ "$ssp" = "yes" ] || [ "$arp" = "yes" ] || [ "$sop" = "yes" ] || \
       [ "$vwp" = "yes" ] || [ "$vmp" = "yes" ]; then
        log_info "检测到预设配置变量 (或 Docker 环境)，跳过交互式向导..."
        return 0
    fi

    # Also check if we are in a non-interactive shell just in case
    if [ ! -t 0 ]; then
        log_info "非交互式 Shell，跳过向导..."
        return 0
    fi

    echo "========================================================="
    echo "   Argosbx 交互式配置向导"
    echo "========================================================="
    
    # Helper to get current port
    get_v() { cat "$HOME/agsbx/$1" 2>/dev/null; }

    # VLESS-Reality
    local curr=$(get_v port_vl_re)
    local hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 VLESS-Reality? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        vlp=yes
        read -p "请输入端口 ($hint): " input_port
        port_vl_re="${input_port:-$curr}"
    fi

    # VMess-xhttp
    curr=$(get_v port_vm_ws)
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 VMess-xhttp? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        vmp=yes
        read -p "请输入端口 ($hint): " input_port
        port_vm_ws="${input_port:-$curr}"
    fi

    # Hysteria2
    curr=$(get_v port_hy2)
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Hysteria2? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        hyp=yes
        read -p "请输入端口 ($hint): " input_port
        port_hy2="${input_port:-$curr}"
    fi

    # Tuic
    curr=$(get_v port_tu)
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Tuic V5? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        tup=yes
        read -p "请输入端口 ($hint): " input_port
        port_tu="${input_port:-$curr}"
    fi

    # XHTTP
    curr=$(get_v port_xh)
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Vless-XHTTP? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        xhp=yes
        read -p "请输入端口 ($hint): " input_port
        port_xh="${input_port:-$curr}"
    fi

    # Shadowsocks
    curr=$(get_v port_ss)
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Shadowsocks-2022? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        ssp=yes
        read -p "请输入端口 ($hint): " input_port
        port_ss="${input_port:-$curr}"
    fi

    # Socks5
    curr=$(get_v port_so)
    hint="默认随机"
    [ -n "$curr" ] && hint="当前: $curr"
    read -p "是否启用 Socks5? (y/n): " choice
    if [[ "$choice" == "y" ]]; then 
        sop=yes
        read -p "请输入端口 ($hint): " input_port
        port_so="${input_port:-$curr}"
    fi
    
    # UUID Config
    echo "---------------------------------------------------------"
    local curr_uuid=$(cat "$HOME/agsbx/uuid" 2>/dev/null)
    local uuid_hint="默认随机"
    [ -n "$curr_uuid" ] && uuid_hint="当前: $curr_uuid"
    
    read -p "是否自定义 UUID? (y/n, $uuid_hint): " uuid_choice
    if [[ "$uuid_choice" == "y" ]]; then
        read -p "请输入您的 UUID (回车保持当前/随机): " input_uuid
        # Logic: If input empty -> keep current. If current empty -> random generated later.
        if [ -n "$input_uuid" ]; then
             uuid="$input_uuid"
        elif [ -n "$curr_uuid" ]; then
             uuid="$curr_uuid"
        fi
    else
        # If user says No custom, and current exists, usually we keep current?
        # Standard logic in insuuid is: if uuid var empty, check file.
        # So we just leave uuid empty here, insuuid will handle it (Keep existing).
        # But if user WANTS to generate NEW random? 
        # They should choose 'y' and type nothing? No.
        # Let's say: No custom means "Let System Decide" (Keep Existing or Random).
        # This matches `insuuid` logic.
        :
    fi
    [ -n "$uuid" ] && export uuid
    
    # Export chosen vars
    export vlp hyp tup xhp ssp sop
    export port_vl_re port_hy2 port_tu port_xh port_ss port_so
    
    echo "---------------------------------------------------------"
    echo "   高级功能配置 (Argo / WARP)"
    echo "---------------------------------------------------------"
    
    # Argo Config
    read -p "是否启用 Argo 隧道 (隐藏服务器IP / 救活被墙IP)? (y/n): " choice
    if [[ "$choice" == "y" ]]; then
        echo "  [1] 临时隧道 (无需域名，随机生成 trycloudflare.com 链接)"
        echo "  [2] 固定隧道 (需要自备域名并在 CF 绑定 Token)"
        read -p "  请选择 (1/2): " argo_sel
        if [[ "$argo_sel" == "2" ]]; then
             read -p "  请输入 Cloudflare Tunnel Token: " agk
             read -p "  请输入您的域名 (例: argo.example.com): " agn
             export ARGO_AUTH=$agk
             export ARGO_DOMAIN=$agn
        fi
        # Argo usually relies on VMess
        argo="vmpt"
        if [ "$vmp" != "yes" ]; then
             echo "  * 已自动为您启用 Argo 依赖的 VMess 协议"
             vmp=yes
        fi
        export argo vmp
    fi
    
    # WARP Config
    read -p "是否启用 WARP (解决 Google 验证码 / 解锁流媒体)? (y/n): " choice
    if [[ "$choice" == "y" ]]; then
        echo "  [1] 全局接管 (所有流量走 WARP，隐藏真实 IP，适合被墙机器)"
        echo "  [2] 仅 IPv6 优先 (保留 IPv4 原生流量)"
        read -p "  请选择 (1/2): " warp_sel
        if [[ "$warp_sel" == "1" ]]; then
             warp="sx" # All traffic via warp-out
        else
             warp="x6" # Xray Force IPv6, others direct
        fi
        export warp
    fi

    echo "========================================================="
    echo "   配置完成！正在启动安装..."
    echo "========================================================="

    # Check again if anything was enabled
    if [ "$vlp" != yes ] && [ "$hyp" != yes ] && [ "$tup" != yes ] && [ "$xhp" != yes ] && [ "$ssp" != yes ] && [ "$sop" != yes ]; then
        log_warn "未选择任何协议，默认启用 Socks5 端口 50000"
        sop=yes
        port_so=50000
        export sop port_so
    fi
}
