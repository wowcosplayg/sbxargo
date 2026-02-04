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

check_warp_availability(){
    log_info "检查 WARP 可用性..."
    warpurl=$( (command -v curl > /dev/null 2>&1 && curl -sm5 -k https://warp.xijp.eu.org 2>/dev/null) || (command -v wget > /dev/null 2>&1 && timeout 3 wget --tries=2 -qO- https://warp.xijp.eu.org 2>/dev/null) )
    if echo "$warpurl" | grep -q html; then
        wpv6='2606:4700:110:8d8d:1845:c39f:2dd5:a03a'
        pvk='52cuYFgCJXp0LAq7+nWJIbCXXgU9eGggOc+Hlfz5u6A='
        res='[215, 69, 233]'
    else
        pvk=$(echo "$warpurl" | awk -F'：' '/Private_key/{print $2}' | xargs)
        wpv6=$(echo "$warpurl" | awk -F'：' '/IPV6/{print $2}' | xargs)
        res=$(echo "$warpurl" | awk -F'：' '/reserved/{print $2}' | xargs)
    fi
    export wpv6 pvk res
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
