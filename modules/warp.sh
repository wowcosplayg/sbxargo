#!/bin/bash

# ============================================================================
# WARP Module
# IP Detection, WARP availability check and Routing Logic
# ============================================================================

# Load Utils
[ -z "$(type -t log_info)" ] && source "$(dirname "$0")/utils.sh"

v4v6(){
    v4=$( (command -v curl > /dev/null 2>&1 && curl -s4m5 -k "$v46url" 2>/dev/null) || (command -v wget > /dev/null 2>&1 && timeout 3 wget -4 --tries=2 -qO- "$v46url" 2>/dev/null) )
    v6=$( (command -v curl > /dev/null 2>&1 && curl -s6m5 -k "$v46url" 2>/dev/null) || (command -v wget > /dev/null 2>&1 && timeout 3 wget -6 --tries=2 -qO- "$v46url" 2>/dev/null) )
    v4dq=$( (command -v curl > /dev/null 2>&1 && curl -s4m5 -k https://ip.fm | sed -E 's/.*Location: ([^,]+(, [^,]+)*),.*/\1/' 2>/dev/null) || (command -v wget > /dev/null 2>&1 && timeout 3 wget -4 --tries=2 -qO- https://ip.fm | grep '<span class="has-text-grey-light">Location:' | tail -n1 | sed -E 's/.*>Location: <\/span>([^<]+)<.*/\1/' 2>/dev/null) )
    v6dq=$( (command -v curl > /dev/null 2>&1 && curl -s6m5 -k https://ip.fm | sed -E 's/.*Location: ([^,]+(, [^,]+)*),.*/\1/' 2>/dev/null) || (command -v wget > /dev/null 2>&1 && timeout 3 wget -6 --tries=2 -qO- https://ip.fm | grep '<span class="has-text-grey-light">Location:' | tail -n1 | sed -E 's/.*>Location: <\/span>([^<]+)<.*/\1/' 2>/dev/null) )
    
    export v4 v6 v4dq v6dq
}

register_warp_native_api() {
    log_info "正在向 Cloudflare API 申请原生 WARP WireGuard 配置..."
    
    if ! command -v wg >/dev/null 2>&1; then
        log_warn "未检测到 wg 命令，尝试自动安装 wireguard-tools..."
        if command -v apt-get >/dev/null 2>&1; then apt-get update -y && apt-get install -y wireguard-tools >/dev/null 2>&1;
        elif command -v apk >/dev/null 2>&1; then apk add wireguard-tools >/dev/null 2>&1;
        elif command -v yum >/dev/null 2>&1; then yum install -y wireguard-tools >/dev/null 2>&1;
        elif command -v dnf >/dev/null 2>&1; then dnf install -y wireguard-tools >/dev/null 2>&1;
        fi
    fi

    if command -v wg >/dev/null 2>&1; then
        local priv=$(wg genkey)
        local pub=$(echo "$priv" | wg pubkey)
        
        local response=""
        if command -v curl >/dev/null 2>&1; then
            response=$(curl -sm10 -X POST "https://api.cloudflareclient.com/v0a2158/reg" \
                -H "User-Agent: okhttp/3.12.1" \
                -H "Content-Type: application/json" \
                -d "{\"key\":\"$pub\"}" 2>/dev/null)
        elif command -v wget >/dev/null 2>&1; then
            response=$(wget -qO- --timeout=10 --header="User-Agent: okhttp/3.12.1" --header="Content-Type: application/json" --post-data="{\"key\":\"$pub\"}" "https://api.cloudflareclient.com/v0a2158/reg" 2>/dev/null)
        fi
        
        local v6=$(echo "$response" | grep -oE '"v6":"[^"]+"' | cut -d'"' -f4)
        if [ -n "$v6" ]; then
            WARP_IPV6="$v6"
            WARP_PRIVATE_KEY="$priv"
            WARP_RESERVED="[0,0,0]"
            log_info "原生存根生成成功! 动态分配 IPv6: $WARP_IPV6"
            update_config_var "WARP_IPV6" "$WARP_IPV6"
            update_config_var "WARP_PRIVATE_KEY" "$WARP_PRIVATE_KEY"
            update_config_var "WARP_RESERVED" "$WARP_RESERVED"
            return 0
        fi
    fi
    
    log_warn "原生注册失败或缺少关键编译包，自动降级至后备备用池..."
    local warpurl=""
    if command -v curl >/dev/null 2>&1; then
        warpurl=$(curl -sm5 -k https://warp.xijp.eu.org 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        warpurl=$(timeout 5 wget --tries=2 -qO- https://warp.xijp.eu.org 2>/dev/null)
    fi
    
    if echo "$warpurl" | grep -q html || [ -z "$warpurl" ]; then
        log_warn "后备池拉取失败，启用内置救星应急金钥。"
        WARP_IPV6='2606:4700:110:8d8d:1845:c39f:2dd5:a03a'
        WARP_PRIVATE_KEY='52cuYFgCJXp0LAq7+nWJIbCXXgU9eGggOc+Hlfz5u6A='
        WARP_RESERVED='[215, 69, 233]'
    else
        WARP_PRIVATE_KEY=$(echo "$warpurl" | awk -F'：' '/Private_key/{print $2}' | xargs)
        WARP_IPV6=$(echo "$warpurl" | awk -F'：' '/IPV6/{print $2}' | xargs)
        WARP_RESERVED=$(echo "$warpurl" | awk -F'：' '/reserved/{print $2}' | xargs)
    fi
    
    update_config_var "WARP_IPV6" "$WARP_IPV6"
    update_config_var "WARP_PRIVATE_KEY" "$WARP_PRIVATE_KEY"
    update_config_var "WARP_RESERVED" "$WARP_RESERVED"
    log_info "配置完毕！"
    return 0
}

check_warp_availability(){
    log_info "检查 WARP 内嵌配置..."
    
    if [ "$warp" == "no" ] || [ -z "$warp" ]; then
        return 0
    fi
    
    if [ -z "$WARP_PRIVATE_KEY" ] || [ -z "$WARP_IPV6" ]; then
         register_warp_native_api
    else
         log_info "读取到已存在的 WARP 密钥对，跳过注册验证。 (修改配置菜单可重置)"
    fi
}

configure_warp_routing(){
    if [ -n "$name" ]; then
        sxname=$name-
        echo "$sxname" > "$HOME/agsbx/name"
        log_info "所有节点名称前缀：$name"
    fi
    
    v4v6
    
    # Check if current IP is already WARP
    if echo "$v6" | grep -q '^2a09' || echo "$v4" | grep -q '^104.28'; then
        s1outtag=direct; s2outtag=direct; x1outtag=direct; x2outtag=direct; xip='"::/0", "0.0.0.0/0"'; sip='"::/0", "0.0.0.0/0"'; wap=warpargo
        log_warn "检测到当前已使用 WARP IP，禁用脚本内 WARP 路由"
    else
        if [ "$wap" != yes ]; then
            s1outtag=direct; s2outtag=direct; x1outtag=direct; x2outtag=direct; xip='"::/0", "0.0.0.0/0"'; sip='"::/0", "0.0.0.0/0"'; wap=warpargo
        else
            log_info "配置 WARP 路由规则: $warp"
            case "$warp" in
                ""|sx|xs) s1outtag=warp-out; s2outtag=warp-out; x1outtag=warp-out; x2outtag=warp-out; xip='"::/0", "0.0.0.0/0"'; sip='"::/0", "0.0.0.0/0"'; wap=warp ;;
                s ) s1outtag=warp-out; s2outtag=warp-out; x1outtag=direct; x2outtag=direct; xip='"::/0", "0.0.0.0/0"'; sip='"::/0", "0.0.0.0/0"'; wap=warp ;;
                s4) s1outtag=warp-out; s2outtag=direct; x1outtag=direct; x2outtag=direct; xip='"::/0", "0.0.0.0/0"'; sip='"0.0.0.0/0"'; wap=warp ;;
                s6) s1outtag=warp-out; s2outtag=direct; x1outtag=direct; x2outtag=direct; xip='"::/0", "0.0.0.0/0"'; sip='"::/0"'; wap=warp ;;
                x ) s1outtag=direct; s2outtag=direct; x1outtag=warp-out; x2outtag=warp-out; xip='"::/0", "0.0.0.0/0"'; sip='"::/0", "0.0.0.0/0"'; wap=warp ;;
                x4) s1outtag=direct; s2outtag=direct; x1outtag=warp-out; x2outtag=direct; xip='"0.0.0.0/0"'; sip='"::/0", "0.0.0.0/0"'; wap=warp ;;
                x6) s1outtag=direct; s2outtag=direct; x1outtag=warp-out; x2outtag=direct; xip='"::/0"'; sip='"::/0", "0.0.0.0/0"'; wap=warp ;;
                s4x4|x4s4) s1outtag=warp-out; s2outtag=direct; x1outtag=warp-out; x2outtag=direct; xip='"0.0.0.0/0"'; sip='"0.0.0.0/0"'; wap=warp ;;
                s4x6|x6s4) s1outtag=warp-out; s2outtag=direct; x1outtag=warp-out; x2outtag=direct; xip='"::/0"'; sip='"0.0.0.0/0"'; wap=warp ;;
                s6x4|x4s6) s1outtag=warp-out; s2outtag=direct; x1outtag=warp-out; x2outtag=direct; xip='"0.0.0.0/0"'; sip='"::/0"'; wap=warp ;;
                s6x6|x6s6) s1outtag=warp-out; s2outtag=direct; x1outtag=warp-out; x2outtag=direct; xip='"::/0"'; sip='"::/0"'; wap=warp ;;
                sx4|x4s) s1outtag=warp-out; s2outtag=warp-out; x1outtag=warp-out; x2outtag=direct; xip='"0.0.0.0/0"'; sip='"::/0", "0.0.0.0/0"'; wap=warp ;;
                sx6|x6s) s1outtag=warp-out; s2outtag=warp-out; x1outtag=warp-out; x2outtag=direct; xip='"::/0"'; sip='"::/0", "0.0.0.0/0"'; wap=warp ;;
                xs4|s4x) s1outtag=warp-out; s2outtag=direct; x1outtag=warp-out; x2outtag=warp-out; xip='"::/0", "0.0.0.0/0"'; sip='"0.0.0.0/0"'; wap=warp ;;
                xs6|s6x) s1outtag=warp-out; s2outtag=direct; x1outtag=warp-out; x2outtag=warp-out; xip='"::/0", "0.0.0.0/0"'; sip='"::/0"'; wap=warp ;;
                * ) s1outtag=direct; s2outtag=direct; x1outtag=direct; x2outtag=direct; xip='"::/0", "0.0.0.0/0"'; sip='"::/0", "0.0.0.0/0"'; wap=warpargo ;;
            esac
        fi
    fi
    
    export s1outtag s2outtag x1outtag x2outtag xip sip wap
    
    # Configure routing strategy vars
    case "$warp" in *x4*) wxryx='ForceIPv4' ;; *x6*) wxryx='ForceIPv6' ;; *) wxryx='ForceIPv6v4' ;; esac
    
    if command -v curl > /dev/null 2>&1; then
        curl -s4m5 -k "$v46url" >/dev/null 2>&1 && v4_ok=true
    elif command -v wget > /dev/null 2>&1; then
        timeout 3 wget -4 --tries=2 -qO- "$v46url" >/dev/null 2>&1 && v4_ok=true
    fi
    if command -v curl > /dev/null 2>&1; then
        curl -s6m5 -k "$v46url" >/dev/null 2>&1 && v6_ok=true
    elif command -v wget > /dev/null 2>&1; then
        timeout 3 wget -6 --tries=2 -qO- "$v46url" >/dev/null 2>&1 && v6_ok=true
    fi
    
    if [ "$v4_ok" = true ] && [ "$v6_ok" = true ]; then
        case "$warp" in *s4*) sbyx='prefer_ipv4' ;; *) sbyx='prefer_ipv6' ;; esac
        case "$warp" in *x4*) xryx='ForceIPv4v6' ;; *x*) xryx='ForceIPv6v4' ;; *) xryx='ForceIPv4v6' ;; esac
    elif [ "$v4_ok" = true ] && [ "$v6_ok" != true ]; then
        case "$warp" in *s4*) sbyx='ipv4_only' ;; *) sbyx='prefer_ipv6' ;; esac
        case "$warp" in *x4*) xryx='ForceIPv4' ;; *x*) xryx='ForceIPv6v4' ;; *) xryx='ForceIPv4v6' ;; esac
    elif [ "$v4_ok" != true ] && [ "$v6_ok" = true ]; then
        case "$warp" in *s6*) sbyx='ipv6_only' ;; *) sbyx='prefer_ipv4' ;; esac
        case "$warp" in *x6*) xryx='ForceIPv6' ;; *x*) xryx='ForceIPv4v6' ;; *) xryx='ForceIPv6v4' ;; esac
    fi
    
    export wxryx sbyx xryx
    
    # Set sendip
    if [ "$v6_ok" = true ]; then
        sendip="2606:4700:d0::a29f:c001"
        xendip="[2606:4700:d0::a29f:c001]"
    else
        sendip="162.159.192.1"
        xendip="162.159.192.1"
    fi
    export sendip xendip
}
