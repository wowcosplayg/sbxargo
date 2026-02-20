#!/bin/bash

# ============================================================================
# Install Module
# System checks, Dependency installation
# ============================================================================

# Load Utils
[ -z "$(type -t log_info)" ] && source "$(dirname "$0")/utils.sh"

check_system_compatibility() {
    log_info "检查系统兼容性..."

    case $(uname -m) in
        arm64|aarch64)
            cpu=arm64
            ;;
        amd64|x86_64)
            cpu=amd64
            ;;
        *)
            log_error "不支持的架构: $(uname -m)"
            return 1
            ;;
    esac
    export cpu
    
    op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
    export op
    
    if pidof systemd >/dev/null 2>&1; then
        export SYS_INIT="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        export SYS_INIT="openrc"
    else
        log_warn "未检测到 systemd 或 OpenRC，将使用 nohup 方式运行"
        export SYS_INIT="nohup"
    fi

    log_info "系统: $op, 架构: $cpu, Init: $SYS_INIT"
    return 0
}

install_dependencies() {
    log_info "检查并安装依赖..."
    local deps="curl unzip jq"
    
    # Simple check function
    check_cmd() { command -v "$1" >/dev/null 2>&1; }
    
    local missing=""
    for cmd in $deps; do
        if ! check_cmd "$cmd"; then
            missing="$missing $cmd"
        fi
    done
    
    if [ -n "$missing" ]; then
        log_info "缺少依赖: $missing，正在安装..."
        if check_cmd apt-get; then
            apt-get update -y >/dev/null 2>&1
            apt-get install -y $missing >/dev/null 2>&1
        elif check_cmd apk; then
            apk add --no-cache $missing >/dev/null 2>&1
        elif check_cmd yum; then
            yum install -y $missing >/dev/null 2>&1
        elif check_cmd dnf; then
            dnf install -y $missing >/dev/null 2>&1
        else
            log_error "无法自动安装依赖: $missing，请手动安装。"
            return 1
        fi
    fi
     
    # Re-check
    for cmd in $deps; do
        if ! check_cmd "$cmd"; then
            log_error "依赖安装失败: $cmd"
            return 1
        fi
    done
    
    # Openssl is special, typically optional but good to have
    if ! check_cmd openssl; then
         log_warn "OpenSSL 未安装，尝试安装..."
         if check_cmd apt-get; then apt-get install -y openssl >/dev/null 2>&1;
         elif check_cmd apk; then apk add openssl >/dev/null 2>&1;
         elif check_cmd yum; then yum install -y openssl >/dev/null 2>&1;
         fi
    fi
    
    
    # Create workspace
    mkdir -p "$HOME/agsbx"
    chmod 700 "$HOME/agsbx"
}

optimize_system() {
    # Skip if in Docker (User usually cannot sysctl in docker unless privileged)
    if [ -f /.dockerenv ]; then
        log_warn "检测到 Docker 环境，跳过内核参数优化 (宿主机权限限制)。建议在宿主机开启 BBR。"
        return 0
    fi
    
    log_info "检查系统性能参数..."
    local need_optimization=0
    
    # Check IP Forwarding
    if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" != "1" ]; then
        need_optimization=1
    fi
    
    # Check BBR
    if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        need_optimization=1
    fi
    
    if [ "$need_optimization" -eq 0 ]; then
        log_info "系统已开启 IP 转发及 BBR 加速，无需重复优化。"
        return 0
    fi

    # Interactive Prompt
    echo ""
    echo "========================================================="
    echo "   性能优化建议"
    echo "========================================================="
    echo "检测到系统未开启 BBR 加速或 IP 转发。"
    echo "优化可显著提升网络吞吐量和并在高丢包环境下改善连接稳定性。"
    echo ""
    read -p "是否执行系统内核优化 (BBR + Sysctl)? (Y/n) [默认: Y]: " choice
    choice=${choice:-Y}
    
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        log_info "正在应用内核优化..."
        
        cat > /etc/sysctl.d/99-argosbx.conf <<EOF
# Argosbx Tuning
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.ipv4.tcp_rmem=4096 87380 26214400
net.ipv4.tcp_wmem=4096 16384 26214400
net.ipv4.tcp_mtu_probing=1
EOF
        sysctl -p /etc/sysctl.d/99-argosbx.conf >/dev/null 2>&1
        
        # Verify
        local bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        if [ "$bbr_status" == "bbr" ]; then
             log_info "优化成功! 当前算法: $bbr_status"
        else
             log_warn "优化完成但 BBR 看来未启用 (可能是内核版本过低 ?)。建议重启系统。"
        fi
    else
        log_info "已跳过优化。"
    fi
}

# ============================================================================
# Generic Download Functions
# ============================================================================

download_file() {
    local url="$1"
    local output="$2"
    local description="${3:-下载文件}"

    log_info "$description: $url"

    if curl -Lo "$output" -# --retry 3 --retry-delay 2 "$url" 2>&1 | tee -a "$HOME/agsbx/argosbx.log" >/dev/null; then
        log_info "下载成功: $output"
        return 0
    else
        log_error "下载失败"
        return 1
    fi
}


install_package() {
    local package="$1"
    if command -v apt-get >/dev/null 2>&1; then apt-get update -y && apt-get install -y "$package";
    elif command -v apk >/dev/null 2>&1; then apk add --no-cache "$package";
    elif command -v yum >/dev/null 2>&1; then yum install -y "$package";
    fi
}
