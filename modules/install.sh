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
    local deps="curl wget unzip"
    
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
}

# ============================================================================
# Generic Download Functions
# ============================================================================

download_file() {
    local url="$1"
    local output="$2"
    local description="${3:-下载文件}"

    log_info "$description: $url"

    if command -v curl >/dev/null 2>&1; then
        if curl -Lo "$output" -# --retry 3 --retry-delay 2 "$url" 2>&1 | tee -a "$HOME/agsbx/argosbx.log" >/dev/null; then
            log_info "下载成功: $output"
            return 0
        fi
    fi

    if command -v wget >/dev/null 2>&1; then
        if timeout 30 wget -O "$output" --tries=3 "$url" 2>&1 | tee -a "$HOME/agsbx/argosbx.log" >/dev/null; then
            log_info "下载成功: $output"
            return 0
        fi
    fi

    log_error "下载失败"
    return 1
}

download_official_release() {
    local repo="$1"           # e.g.: XTLS/Xray-core
    local binary_name="$2"    # e.g.: xray
    local cpu_arch="$3"       # amd64 or arm64
    local output_path="$4"    # Output path
    local archive_pattern="$5" # Archive filename pattern

    log_info "从官方仓库下载 $binary_name (仓库: $repo, 架构: $cpu_arch)"

    # Get latest version
    local latest_url="https://api.github.com/repos/$repo/releases/latest"
    local version=""

    if command -v curl > /dev/null 2>&1; then
        version=$(curl -sL "$latest_url" | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/')
    elif command -v wget > /dev/null 2>&1; then
        version=$(wget -qO- "$latest_url" | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/')
    fi

    if [ -z "$version" ]; then
        log_error "无法获取最新版本信息"
        return 1
    fi

    log_info "检测到最新版本: $version"

    # Construct Download URL
    local download_url="https://github.com/$repo/releases/download/$version/$archive_pattern"
    local temp_dir="$HOME/agsbx/temp_$$"
    local archive_file="$temp_dir/archive"

    mkdir -p "$temp_dir" || {
        log_error "无法创建临时目录"
        return 1
    }

    # Download
    if ! download_file "$download_url" "$archive_file" "下载 $binary_name 压缩包"; then
        rm -rf "$temp_dir"
        return 1
    fi

    # Extract
    log_info "解压缩 $binary_name..."
    case "$archive_pattern" in
        *.zip)
            if ! command -v unzip > /dev/null 2>&1; then
                install_package "unzip"
            fi
            unzip -q -o "$archive_file" -d "$temp_dir" 2>&1 | tee -a "$HOME/agsbx/argosbx.log" > /dev/null
            ;;
        *.tar.gz|*.tgz)
            tar -xzf "$archive_file" -C "$temp_dir" 2>&1 | tee -a "$HOME/agsbx/argosbx.log" > /dev/null
            ;;
        *)
            log_error "不支持的压缩格式: $archive_pattern"
            rm -rf "$temp_dir"
            return 1
            ;;
    esac

    # Find and Move
    local found_binary=$(find "$temp_dir" -type f -name "$binary_name" | head -1)

    if [ -z "$found_binary" ]; then
        log_error "在压缩包中未找到 $binary_name 可执行文件"
        rm -rf "$temp_dir"
        return 1
    fi

    mv "$found_binary" "$output_path" || {
        log_error "无法移动文件到 $output_path"
        rm -rf "$temp_dir"
        return 1
    }

    rm -rf "$temp_dir"
    chmod +x "$output_path"
    
    log_info "$binary_name 下载并配置成功"
    return 0
}

install_package() {
    local package="$1"
    if command -v apt-get >/dev/null 2>&1; then apt-get update -y && apt-get install -y "$package";
    elif command -v apk >/dev/null 2>&1; then apk add --no-cache "$package";
    elif command -v yum >/dev/null 2>&1; then yum install -y "$package";
    fi
}

