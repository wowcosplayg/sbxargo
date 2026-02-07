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

register_warp_local() {
    if ! command -v warp-cli >/dev/null 2>&1; then
        return 1
    fi
    
    log_info "检测到 warp-cli，尝试本地注册..."
    
    # Check if already registered
    if warp-cli --accept-tos status | grep -q "Registration missing"; then
         log_info "注册新 WARP 账户..."
         warp-cli --accept-tos register >/dev/null 2>&1
    fi
    
    # Get Keys
    # Output format varies by version, trying generic parse
    local account_out
    account_out=$(warp-cli --accept-tos account)
    
    # Try to extract keys? warp-cli account usually doesn't show private key easily in newer versions without specific commands or config file reading.
    # Actually, getting private key from warp-cli is hard in recent versions (it's hidden).
    # But for Xray/Singbox wireguard usage, we NEED the private key.
    # If standard warp-cli doesn't output it, we might need to look at /var/lib/cloudflare-warp/reg.json or similar (requires root).
    
    if [ -f "/var/lib/cloudflare-warp/reg.json" ]; then
        if command -v jq >/dev/null 2>&1; then
            pvk=$(jq -r .private_key "/var/lib/cloudflare-warp/reg.json")
            wpv6=$(jq -r .config.interface.v6.ip "/var/lib/cloudflare-warp/reg.json")
            # reserved might need decoding from distinct field or it's part of client id?
            # Simplified: just try to get pvk and ipv6
        fi
    fi
    
    # If we can't get pvk, we can't use this method for Wireguard config.
    if [ -z "$pvk" ]; then
        log_warn "无法从本地 warp-cli 获取私钥 (可能需要 root 或版本不支持)。"
        return 1
    fi
    
    log_info "成功获取本地 WARP 密钥。"
    return 0
}

check_warp_availability(){
    log_info "检查 WARP 配置..."
    
    # Use user provided variables or defaults
    # vars: wpv6 (IPv6), pvk (PrivateKey), res (Reserved)
    
    wpv6="${WARP_IPV6:-$wpv6}"
    pvk="${WARP_PRIVATE_KEY:-$pvk}"
    res="${WARP_RESERVED:-$res}"
    
    # Try local registration if missing
    if [ -z "$pvk" ]; then
        register_warp_local
    fi
    
    if [ -n "$pvk" ]; then
         log_info "WARP 配置有效"
         # Ensure IPv6 is set (if local fetch failed to get it but got pvk?)
         if [ -z "$wpv6" ]; then
             # fallback or warning?
             log_warn "WARP Private Key 存在但 IPv6 缺失，可能导致连接失败。"
         fi
         [ -z "$res" ] && res='[215, 69, 233]' 
    else
        log_warn "未检测到 WARP 密钥配置 (WARP_IPV6, WARP_PRIVATE_KEY)。WARP 功能可能无法使用。"
        log_warn "请在 config.env 中配置或通过脚本输入。"
        if [ "$warp" != "no" ] && [ -z "$warp" ]; then
             warp="no"
        fi
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
