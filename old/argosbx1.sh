#!/bin/bash
export LANG=en_US.UTF-8

# ============================================================================
# Argosbx 一键无交互脚本 - 统一版本
# 版本: V25.11.20-Unified
# 原作者: yonggekkk
# 优化整合: 错误处理 + 日志系统 + 依赖检查 + 配置验证
# 项目地址: https://github.com/yonggekkk/argosbx
# ============================================================================

# ============================================================================
# 日志系统
# ============================================================================
LOG_FILE="$HOME/agsbx/argosbx.log"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S' 2>/dev/null || date)

    case "$LOG_LEVEL" in
        DEBUG) ;;
        INFO) [ "$level" = "DEBUG" ] && return ;;
        WARN) [ "$level" = "DEBUG" ] || [ "$level" = "INFO" ] && return ;;
        ERROR) [ "$level" != "ERROR" ] && return ;;
    esac

    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" 2>/dev/null || echo "[$timestamp] [$level] $message"
}

log_debug() { log "DEBUG" "$@"; }
log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# ============================================================================
# 错误处理和回滚机制
# ============================================================================

handle_error() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    if [ $exit_code -ne 0 ]; then
        log_error "命令执行失败 (退出码: $exit_code, 行: $line_number): $command"
        return $exit_code
    fi
    return 0
}

backup_config() {
    local backup_dir="$HOME/agsbx/backup_$(date +%Y%m%d_%H%M%S 2>/dev/null || echo 'backup')"
    log_info "创建配置备份到: $backup_dir"

    mkdir -p "$backup_dir" 2>/dev/null || {
        log_error "无法创建备份目录: $backup_dir"
        return 1
    }

    for file in uuid port_* ym_vl_re cdnym name xr.json sb.json xrk sbk sskey; do
        if [ -e "$HOME/agsbx/$file" ]; then
            cp -r "$HOME/agsbx/$file" "$backup_dir/" 2>/dev/null || log_warn "备份文件失败: $file"
        fi
    done

    echo "$backup_dir" > "$HOME/agsbx/.last_backup"
    log_info "备份完成"
    return 0
}

rollback_config() {
    local backup_dir=$(cat "$HOME/agsbx/.last_backup" 2>/dev/null)

    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        log_error "未找到备份目录，无法回滚"
        return 1
    fi

    log_warn "开始回滚到备份: $backup_dir"
    stop_services
    cp -r "$backup_dir"/* "$HOME/agsbx/" 2>/dev/null || {
        log_error "回滚失败"
        return 1
    }

    log_info "回滚成功"
    return 0
}

stop_services() {
    log_info "停止所有服务..."

    for P in /proc/[0-9]*; do
        if [ -L "$P/exe" ]; then
            TARGET=$(readlink -f "$P/exe" 2>/dev/null)
            if echo "$TARGET" | grep -qE '/agsbx/c|/agsbx/s|/agsbx/x'; then
                PID=$(basename "$P")
                kill "$PID" 2>/dev/null && log_debug "已停止进程: $PID"
            fi
        fi
    done

    kill -15 $(pgrep -f 'agsbx/s' 2>/dev/null) $(pgrep -f 'agsbx/c' 2>/dev/null) $(pgrep -f 'agsbx/x' 2>/dev/null) >/dev/null 2>&1

    if pidof systemd >/dev/null 2>&1; then
        for svc in xr sb argo; do
            systemctl stop "$svc" >/dev/null 2>&1
        done
    elif command -v rc-service >/dev/null 2>&1; then
        for svc in sing-box xray argo; do
            rc-service "$svc" stop >/dev/null 2>&1
        done
    fi
}

# ============================================================================
# 依赖项检查
# ============================================================================

REQUIRED_DEPS="grep awk sed tar"
OPTIONAL_DEPS="wget openssl jq base64 unzip"

check_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        log_debug "依赖检查通过: $cmd"
        return 0
    else
        log_warn "未找到命令: $cmd"
        return 1
    fi
}

check_dependencies() {
    log_info "开始检查系统依赖项..."

    local missing_required=""
    local missing_optional=""

    for cmd in $REQUIRED_DEPS; do
        if ! check_command "$cmd"; then
            missing_required="$missing_required $cmd"
        fi
    done

    for cmd in $OPTIONAL_DEPS; do
        if ! check_command "$cmd"; then
            missing_optional="$missing_optional $cmd"
        fi
    done

    if [ -n "$missing_required" ]; then
        log_error "缺少必需依赖项:$missing_required"
        echo "请安装以下软件包后重试:$missing_required"
        return 1
    fi

    if [ -n "$missing_optional" ]; then
        log_warn "缺少可选依赖项:$missing_optional (某些功能可能受限)"
    fi

    if ! check_command "curl" && ! check_command "wget"; then
        log_error "curl 和 wget 至少需要安装一个"
        return 1
    fi

    log_info "依赖检查完成"
    return 0
}

check_system_compatibility() {
    log_info "检查系统兼容性..."

    case $(uname -m) in
        arm64|aarch64)
            cpu=arm64
            log_info "检测到 ARM64 架构"
            ;;
        amd64|x86_64)
            cpu=amd64
            log_info "检测到 AMD64/x86_64 架构"
            ;;
        *)
            log_error "不支持的架构: $(uname -m)"
            echo "目前脚本不支持$(uname -m)架构"
            return 1
            ;;
    esac

    if pidof systemd >/dev/null 2>&1; then
        log_info "检测到 systemd 服务管理器"
    elif command -v rc-service >/dev/null 2>&1; then
        log_info "检测到 OpenRC 服务管理器"
    else
        log_warn "未检测到 systemd 或 OpenRC，将使用 nohup 方式运行"
    fi

    return 0
}

# ============================================================================
# 配置验证
# ============================================================================

validate_json_config() {
    local json_file="$1"

    if [ ! -f "$json_file" ]; then
        log_error "配置文件不存在: $json_file"
        return 1
    fi

    log_info "验证配置文件: $json_file"

    if command -v jq >/dev/null 2>&1; then
        if jq empty "$json_file" 2>/dev/null; then
            log_info "JSON 格式验证通过: $json_file"
            return 0
        else
            log_error "JSON 格式验证失败: $json_file"
            return 1
        fi
    else
        log_warn "jq 未安装，跳过详细 JSON 验证"
        if grep -q '^{' "$json_file" && grep -q '}$' "$json_file"; then
            log_info "基本 JSON 结构检查通过"
            return 0
        else
            log_error "配置文件不是有效的 JSON 格式"
            return 1
        fi
    fi
}

validate_port() {
    local port="$1"
    if ! echo "$port" | grep -Eq '^[0-9]+$'; then
        log_error "无效的端口号: $port"
        return 1
    fi
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "端口号超出范围: $port"
        return 1
    fi
    log_debug "端口验证通过: $port"
    return 0
}

validate_uuid() {
    local uuid="$1"
    if [ -z "$uuid" ]; then
        log_error "UUID 不能为空"
        return 1
    fi
    if echo "$uuid" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
        log_debug "UUID 格式验证通过"
        return 0
    else
        log_warn "UUID 格式可能不标准: $uuid"
        return 0
    fi
}

validate_domain() {
    local domain="$1"
    [ -z "$domain" ] && return 0
    if echo "$domain" | grep -Eq '^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'; then
        log_debug "域名格式验证通过: $domain"
        return 0
    else
        log_warn "域名格式可能不正确: $domain"
        return 0
    fi
}

# ============================================================================
# 通用下载函数
# ============================================================================

download_file() {
    local url="$1"
    local output="$2"
    local description="${3:-下载文件}"

    log_info "$description: $url"

    if command -v curl >/dev/null 2>&1; then
        if curl -Lo "$output" -# --retry 3 --retry-delay 2 "$url" 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
            log_info "下载成功: $output"
            return 0
        fi
    fi

    if command -v wget >/dev/null 2>&1; then
        if timeout 30 wget -O "$output" --tries=3 "$url" 2>&1 | tee -a "$LOG_FILE" >/dev/null; then
            log_info "下载成功: $output"
            return 0
        fi
    fi

    log_error "下载失败"
    return 1
}

download_binary() {
    local name="$1"
    local cpu_arch="$2"
    local base_url="$3"
    local output_path="$4"

    local url="${base_url}${name}-${cpu_arch}"

    log_info "下载 $name 二进制文件 (架构: $cpu_arch)"

    if ! download_file "$url" "$output_path" "下载 $name"; then
        return 1
    fi

    if ! chmod +x "$output_path"; then
        log_error "无法设置执行权限: $output_path"
        return 1
    fi

    if [ ! -x "$output_path" ]; then
        log_error "文件不可执行: $output_path"
        return 1
    fi

    log_info "$name 下载并配置成功"
    return 0
}

# 从官方 GitHub releases 下载并解压二进制文件
download_official_release() {
    local repo="$1"           # 例如: XTLS/Xray-core
    local binary_name="$2"    # 例如: xray
    local cpu_arch="$3"       # amd64 或 arm64
    local output_path="$4"    # 输出路径
    local archive_pattern="$5" # 压缩包文件名模式

    log_info "从官方仓库下载 $binary_name (仓库: $repo, 架构: $cpu_arch)"
    echo "正在从官方仓库下载 $binary_name..."

    # 获取最新版本号
    local latest_url="https://api.github.com/repos/$repo/releases/latest"
    local version=""

    log_info "正在获取最新版本信息: $latest_url"
    if command -v curl > /dev/null 2>&1; then
        version=$(curl -sL "$latest_url" | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/')
    elif command -v wget > /dev/null 2>&1; then
        version=$(wget -qO- "$latest_url" | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/')
    fi

    if [ -z "$version" ]; then
        log_error "无法获取最新版本信息，可能是网络问题或 GitHub API 限制"
        echo "错误：无法获取 $binary_name 的版本信息"
        return 1
    fi

    log_info "检测到最新版本: $version"
    echo "最新版本: $version"

    # 构造下载 URL
    local download_url="https://github.com/$repo/releases/download/$version/$archive_pattern"
    local temp_dir="$HOME/agsbx/temp_$$"
    local archive_file="$temp_dir/archive"

    mkdir -p "$temp_dir" || {
        log_error "无法创建临时目录"
        return 1
    }

    # 下载压缩包
    log_info "下载URL: $download_url"
    if ! download_file "$download_url" "$archive_file" "下载 $binary_name 压缩包"; then
        log_error "下载失败: $download_url"
        echo "错误：下载 $binary_name 失败"
        rm -rf "$temp_dir"
        return 1
    fi

    # 检查下载的文件大小
    if [ ! -s "$archive_file" ]; then
        log_error "下载的文件为空"
        echo "错误：下载的文件为空"
        rm -rf "$temp_dir"
        return 1
    fi

    # 解压缩
    log_info "解压缩 $binary_name..."
    echo "正在解压缩..."

    case "$archive_pattern" in
        *.zip)
            if ! command -v unzip > /dev/null 2>&1; then
                log_error "需要 unzip 工具来解压 .zip 文件，请安装: apt install unzip 或 yum install unzip"
                echo "错误：系统缺少 unzip 工具，请先安装"
                rm -rf "$temp_dir"
                return 1
            fi
            if ! unzip -q -o "$archive_file" -d "$temp_dir" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then
                log_error "解压 zip 文件失败"
                echo "错误：解压失败"
                rm -rf "$temp_dir"
                return 1
            fi
            ;;
        *.tar.gz|*.tgz)
            if ! tar -xzf "$archive_file" -C "$temp_dir" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then
                log_error "解压 tar.gz 文件失败"
                echo "错误：解压失败"
                rm -rf "$temp_dir"
                return 1
            fi
            ;;
        *)
            log_error "不支持的压缩格式: $archive_pattern"
            echo "错误：不支持的压缩格式"
            rm -rf "$temp_dir"
            return 1
            ;;
    esac

    # 查找并移动可执行文件
    local found_binary=$(find "$temp_dir" -type f -name "$binary_name" | head -1)

    if [ -z "$found_binary" ]; then
        log_error "在压缩包中未找到 $binary_name 可执行文件"
        echo "错误：压缩包中未找到可执行文件"
        log_info "临时目录内容:"
        ls -la "$temp_dir" | tee -a "$LOG_FILE"
        rm -rf "$temp_dir"
        return 1
    fi

    log_info "找到可执行文件: $found_binary"

    # 移动到目标位置
    mv "$found_binary" "$output_path" || {
        log_error "无法移动文件到 $output_path"
        echo "错误：无法移动文件"
        rm -rf "$temp_dir"
        return 1
    }

    # 清理临时文件
    rm -rf "$temp_dir"

    # 设置执行权限
    if ! chmod +x "$output_path"; then
        log_error "无法设置执行权限: $output_path"
        return 1
    fi

    if [ ! -x "$output_path" ]; then
        log_error "文件不可执行: $output_path"
        return 1
    fi

    log_info "$binary_name 下载并配置成功"
    echo "$binary_name 安装成功"
    return 0
}

# ============================================================================
# 原始脚本变量初始化
# ============================================================================

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

# 参数验证
if find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -Eq 'agsbx/(s|x)' || pgrep -f 'agsbx/(s|x)' >/dev/null 2>&1; then
    if [ "$1" = "rep" ]; then
        [ "$vwp" = yes ] || [ "$sop" = yes ] || [ "$vxp" = yes ] || [ "$ssp" = yes ] || [ "$vlp" = yes ] || [ "$vmp" = yes ] || [ "$hyp" = yes ] || [ "$tup" = yes ] || [ "$xhp" = yes ] || [ "$anp" = yes ] || [ "$arp" = yes ] || {
            log_error "rep重置协议时，请在脚本前至少设置一个协议变量"
            echo "提示：rep重置协议时，请在脚本前至少设置一个协议变量哦，再见！💣"
            exit 1
        }
    fi
else
    [ "$1" = "del" ] || [ "$vwp" = yes ] || [ "$sop" = yes ] || [ "$vxp" = yes ] || [ "$ssp" = yes ] || [ "$vlp" = yes ] || [ "$vmp" = yes ] || [ "$hyp" = yes ] || [ "$tup" = yes ] || [ "$xhp" = yes ] || [ "$anp" = yes ] || [ "$arp" = yes ] || {
        log_error "未安装argosbx脚本，请在脚本前至少设置一个协议变量"
        echo "提示：未安装argosbx脚本，请在脚本前至少设置一个协议变量哦，再见！💣"
        exit 1
    }
fi

# 导出环境变量
export uuid=${uuid:-''}
export port_vl_re=${vlpt:-''}
export port_vm_ws=${vmpt:-''}
export port_vw=${vwpt:-''}
export port_hy2=${hypt:-''}
export port_tu=${tupt:-''}
export port_xh=${xhpt:-''}
export port_vx=${vxpt:-''}
export port_an=${anpt:-''}
export port_ar=${arpt:-''}
export port_ss=${sspt:-''}
export port_so=${sopt:-''}
export ym_vl_re=${reym:-''}
export cdnym=${cdnym:-''}
export argo=${argo:-''}
export ARGO_DOMAIN=${agn:-''}
export ARGO_AUTH=${agk:-''}
export ippz=${ippz:-''}
export warp=${warp:-''}
export name=${name:-''}
export oap=${oap:-''}

v46url="https://icanhazip.com"
agsbxurl="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"

# ============================================================================
# 显示函数
# ============================================================================

showmode(){
    echo "Argosbx脚本一键SSH命令生成器在线网址：https://yonggekkk.github.io/argosbx/"
    echo "主脚本：bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh) 或 bash <(wget -qO- https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh)"
    echo "显示节点信息命令：agsbx list 【或者】 主脚本 list"
    echo "生成订阅文件命令：agsbx sub 【或者】 主脚本 sub"
    echo "重置变量组命令：自定义各种协议变量组 agsbx rep 【或者】 自定义各种协议变量组 主脚本 rep"
    echo "更新脚本命令：原已安装的自定义各种协议变量组 主脚本 rep"
    echo "更新Xray或Singbox内核命令：agsbx upx或ups 【或者】 主脚本 upx或ups"
    echo "重启脚本命令：agsbx res 【或者】 主脚本 res"
    echo "卸载脚本命令：agsbx del 【或者】 主脚本 del"
    echo "双栈VPS显示IPv4/IPv6节点配置命令：ippz=4或6 agsbx list 【或者】 ippz=4或6 主脚本 list"
    echo "---------------------------------------------------------"
    echo
}

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "甬哥Github项目 ：github.com/yonggekkk"
echo "甬哥Blogger博客 ：ygkkk.blogspot.com"
echo "甬哥YouTube频道 ：www.youtube.com/@ygkkk"
echo "Argosbx一键无交互小钢炮脚本💣 - 统一优化版"
echo "当前版本：V25.11.20-Unified"
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

hostname=$(uname -a | awk '{print $2}')
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
[ -z "$(systemd-detect-virt 2>/dev/null)" ] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)

mkdir -p "$HOME/agsbx" 2>/dev/null || {
    log_error "无法创建工作目录"
    exit 1
}

# ============================================================================
# 内核下载和安装函数 (使用优化后的下载函数)
# ============================================================================

upxray(){
    log_info "开始从官方仓库下载 Xray 内核..."

    # 根据架构确定压缩包文件名
    local archive_name=""
    case "$cpu" in
        amd64)
            archive_name="Xray-linux-64.zip"
            ;;
        arm64)
            archive_name="Xray-linux-arm64-v8a.zip"
            ;;
        *)
            log_error "不支持的架构: $cpu"
            return 1
            ;;
    esac

    if ! download_official_release "XTLS/Xray-core" "xray" "$cpu" "$HOME/agsbx/xray" "$archive_name"; then
        log_error "Xray 下载失败"
        return 1
    fi

    sbcore=$("$HOME/agsbx/xray" version 2>/dev/null | awk '/^Xray/{print $2}')
    log_info "已安装Xray正式版内核：$sbcore"
    echo "已安装Xray正式版内核：$sbcore"
    return 0
}

upsingbox(){
    log_info "开始从官方仓库下载 Sing-box 内核..."

    # Sing-box 官方使用统一的命名格式
    # sing-box-{version}-linux-{arch}.tar.gz
    # 但我们需要动态获取版本号,所以在 download_official_release 中处理

    # 根据架构确定压缩包文件名模式（使用占位符，会在函数中替换版本号）
    local archive_pattern=""
    case "$cpu" in
        amd64)
            archive_pattern="sing-box-.*-linux-amd64.tar.gz"
            ;;
        arm64)
            archive_pattern="sing-box-.*-linux-arm64.tar.gz"
            ;;
        *)
            log_error "不支持的架构: $cpu"
            return 1
            ;;
    esac

    if ! download_singbox_release "$cpu" "$HOME/agsbx/sing-box"; then
        log_error "Sing-box 下载失败"
        return 1
    fi

    sbcore=$("$HOME/agsbx/sing-box" version 2>/dev/null | awk '/version/{print $NF}')
    log_info "已安装Sing-box正式版内核：$sbcore"
    echo "已安装Sing-box正式版内核：$sbcore"
    return 0
}

# Sing-box 专用下载函数（因为其文件名包含版本号）
download_singbox_release() {
    local cpu_arch="$1"
    local output_path="$2"
    local repo="SagerNet/sing-box"

    log_info "从官方仓库下载 sing-box (架构: $cpu_arch)"
    echo "正在从官方仓库下载 Sing-box..."

    # 获取最新版本号
    local latest_url="https://api.github.com/repos/$repo/releases/latest"
    local version=""

    log_info "正在获取最新版本信息: $latest_url"
    if command -v curl > /dev/null 2>&1; then
        version=$(curl -sL "$latest_url" | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/' | sed 's/^v//')
    elif command -v wget > /dev/null 2>&1; then
        version=$(wget -qO- "$latest_url" | grep -o '"tag_name": *"[^"]*"' | sed 's/"tag_name": *"\(.*\)"/\1/' | sed 's/^v//')
    fi

    if [ -z "$version" ]; then
        log_error "无法获取最新版本信息，可能是网络问题或 GitHub API 限制"
        echo "错误：无法获取 Sing-box 的版本信息"
        return 1
    fi

    log_info "检测到最新版本: $version"
    echo "最新版本: $version"

    # 构造下载 URL（Sing-box 文件名格式: sing-box-{version}-linux-{arch}.tar.gz）
    local archive_name="sing-box-${version}-linux-${cpu_arch}.tar.gz"
    local download_url="https://github.com/$repo/releases/download/v${version}/$archive_name"
    local temp_dir="$HOME/agsbx/temp_$$"
    local archive_file="$temp_dir/archive.tar.gz"

    mkdir -p "$temp_dir" || {
        log_error "无法创建临时目录"
        return 1
    }

    # 下载压缩包
    log_info "下载URL: $download_url"
    if ! download_file "$download_url" "$archive_file" "下载 sing-box 压缩包"; then
        log_error "下载失败: $download_url"
        echo "错误：下载 Sing-box 失败"
        rm -rf "$temp_dir"
        return 1
    fi

    # 检查下载的文件大小
    if [ ! -s "$archive_file" ]; then
        log_error "下载的文件为空"
        echo "错误：下载的文件为空"
        rm -rf "$temp_dir"
        return 1
    fi

    # 解压缩
    log_info "解压缩 sing-box..."
    echo "正在解压缩..."
    if ! tar -xzf "$archive_file" -C "$temp_dir" 2>&1 | tee -a "$LOG_FILE" > /dev/null; then
        log_error "解压 tar.gz 文件失败"
        echo "错误：解压失败"
        rm -rf "$temp_dir"
        return 1
    fi

    # 查找并移动可执行文件
    local found_binary=$(find "$temp_dir" -type f -name "sing-box" | head -1)

    if [ -z "$found_binary" ]; then
        log_error "在压缩包中未找到 sing-box 可执行文件"
        echo "错误：压缩包中未找到可执行文件"
        log_info "临时目录内容:"
        ls -la "$temp_dir" | tee -a "$LOG_FILE"
        rm -rf "$temp_dir"
        return 1
    fi

    log_info "找到可执行文件: $found_binary"

    # 移动到目标位置
    mv "$found_binary" "$output_path" || {
        log_error "无法移动文件到 $output_path"
        echo "错误：无法移动文件"
        rm -rf "$temp_dir"
        return 1
    }

    # 清理临时文件
    rm -rf "$temp_dir"

    # 设置执行权限
    if ! chmod +x "$output_path"; then
        log_error "无法设置执行权限: $output_path"
        return 1
    fi

    if [ ! -x "$output_path" ]; then
        log_error "文件不可执行: $output_path"
        return 1
    fi

    log_info "sing-box 下载并配置成功"
    echo "Sing-box 安装成功"
    return 0
}

# ============================================================================
# UUID 生成函数
# ============================================================================

insuuid(){
    log_info "处理 UUID..."

    if [ -z "$uuid" ] && [ ! -e "$HOME/agsbx/uuid" ]; then
        if [ -e "$HOME/agsbx/sing-box" ]; then
            uuid=$("$HOME/agsbx/sing-box" generate uuid)
        else
            uuid=$("$HOME/agsbx/xray" uuid)
        fi

        if [ -z "$uuid" ]; then
            log_error "UUID 生成失败"
            return 1
        fi

        echo "$uuid" > "$HOME/agsbx/uuid"
    elif [ -n "$uuid" ]; then
        echo "$uuid" > "$HOME/agsbx/uuid"
    fi

    uuid=$(cat "$HOME/agsbx/uuid")

    if ! validate_uuid "$uuid"; then
        log_warn "UUID 格式可能不标准，但继续使用"
    fi

    log_info "UUID密码：$uuid"
    echo "UUID密码：$uuid"
    return 0
}
installxray(){
echo
echo "=========启用xray内核========="
mkdir -p "$HOME/agsbx/xrk"
if [ ! -e "$HOME/agsbx/xray" ]; then
upxray
fi
cat > "$HOME/agsbx/xr.json" <<EOF
{
  "log": {
  "loglevel": "none"
  },
  "inbounds": [
EOF
insuuid
if [ -n "$xhp" ] || [ -n "$vlp" ]; then
if [ -z "$ym_vl_re" ]; then
ym_vl_re=apple.com
fi
echo "$ym_vl_re" > "$HOME/agsbx/ym_vl_re"
echo "Reality域名：$ym_vl_re"
if [ ! -e "$HOME/agsbx/xrk/private_key" ]; then
key_pair=$("$HOME/agsbx/xray" x25519)
private_key=$(echo "$key_pair" | grep "PrivateKey" | awk '{print $2}')
public_key=$(echo "$key_pair" | grep "Password" | awk '{print $2}')
short_id=$(date +%s%N | sha256sum | cut -c 1-8)
echo "$private_key" > "$HOME/agsbx/xrk/private_key"
echo "$public_key" > "$HOME/agsbx/xrk/public_key"
echo "$short_id" > "$HOME/agsbx/xrk/short_id"
fi
private_key_x=$(cat "$HOME/agsbx/xrk/private_key")
public_key_x=$(cat "$HOME/agsbx/xrk/public_key")
short_id_x=$(cat "$HOME/agsbx/xrk/short_id")
fi
if [ -n "$xhp" ] || [ -n "$vxp" ] || [ -n "$vwp" ]; then
if [ ! -e "$HOME/agsbx/xrk/dekey" ]; then
vlkey=$("$HOME/agsbx/xray" vlessenc)
dekey=$(echo "$vlkey" | grep '"decryption":' | sed -n '2p' | cut -d' ' -f2- | tr -d '"')
enkey=$(echo "$vlkey" | grep '"encryption":' | sed -n '2p' | cut -d' ' -f2- | tr -d '"')
echo "$dekey" > "$HOME/agsbx/xrk/dekey"
echo "$enkey" > "$HOME/agsbx/xrk/enkey"
fi
dekey=$(cat "$HOME/agsbx/xrk/dekey")
enkey=$(cat "$HOME/agsbx/xrk/enkey")
fi

if [ -n "$xhp" ]; then
xhp=xhpt
if [ -z "$port_xh" ] && [ ! -e "$HOME/agsbx/port_xh" ]; then
port_xh=$(shuf -i 10000-65535 -n 1)
echo "$port_xh" > "$HOME/agsbx/port_xh"
elif [ -n "$port_xh" ]; then
echo "$port_xh" > "$HOME/agsbx/port_xh"
fi
port_xh=$(cat "$HOME/agsbx/port_xh")
echo "Vless-xhttp-reality-enc端口：$port_xh"
cat >> "$HOME/agsbx/xr.json" <<EOF
    {
      "tag":"xhttp-reality",
      "listen": "::",
      "port": ${port_xh},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "${dekey}"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "chrome",
          "target": "${ym_vl_re}:443",
          "serverNames": [
            "${ym_vl_re}"
          ],
          "privateKey": "$private_key_x",
          "shortIds": ["$short_id_x"]
        },
        "xhttpSettings": {
          "host": "",
          "path": "${uuid}-xh",
          "mode": "auto"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
EOF
else
xhp=xhptargo
fi
if [ -n "$vxp" ]; then
vxp=vxpt
if [ -z "$port_vx" ] && [ ! -e "$HOME/agsbx/port_vx" ]; then
port_vx=$(shuf -i 10000-65535 -n 1)
echo "$port_vx" > "$HOME/agsbx/port_vx"
elif [ -n "$port_vx" ]; then
echo "$port_vx" > "$HOME/agsbx/port_vx"
fi
port_vx=$(cat "$HOME/agsbx/port_vx")
echo "Vless-xhttp-enc端口：$port_vx"
if [ -n "$cdnym" ]; then
echo "$cdnym" > "$HOME/agsbx/cdnym"
echo "80系CDN或者回源CDN的host域名 (确保IP已解析在CF域名)：$cdnym"
fi
cat >> "$HOME/agsbx/xr.json" <<EOF
    {
      "tag":"vless-xhttp",
      "listen": "::",
      "port": ${port_vx},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "${dekey}"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "host": "",
          "path": "${uuid}-vx",
          "mode": "auto"
        }
      },
        "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
EOF
else
vxp=vxptargo
fi
if [ -n "$vwp" ]; then
vwp=vwpt
if [ -z "$port_vw" ] && [ ! -e "$HOME/agsbx/port_vw" ]; then
port_vw=$(shuf -i 10000-65535 -n 1)
echo "$port_vw" > "$HOME/agsbx/port_vw"
elif [ -n "$port_vw" ]; then
echo "$port_vw" > "$HOME/agsbx/port_vw"
fi
port_vw=$(cat "$HOME/agsbx/port_vw")
echo "Vless-ws-enc端口：$port_vw"
if [ -n "$cdnym" ]; then
echo "$cdnym" > "$HOME/agsbx/cdnym"
echo "80系CDN或者回源CDN的host域名 (确保IP已解析在CF域名)：$cdnym"
fi
cat >> "$HOME/agsbx/xr.json" <<EOF
    {
      "tag":"vless-xhttp-cdn",
      "listen": "::",
      "port": ${port_vw},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}"
          }
        ],
        "decryption": "${dekey}"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "${uuid}-vw",
          "mode": "packet-up"
        }
      },
        "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "metadataOnly": false
      }
    },
EOF
else
vwp=vwptargo
fi
if [ -n "$vlp" ]; then
vlp=vlpt
if [ -z "$port_vl_re" ] && [ ! -e "$HOME/agsbx/port_vl_re" ]; then
port_vl_re=$(shuf -i 10000-65535 -n 1)
echo "$port_vl_re" > "$HOME/agsbx/port_vl_re"
elif [ -n "$port_vl_re" ]; then
echo "$port_vl_re" > "$HOME/agsbx/port_vl_re"
fi
port_vl_re=$(cat "$HOME/agsbx/port_vl_re")
echo "Vless-tcp-reality-v端口：$port_vl_re"
cat >> "$HOME/agsbx/xr.json" <<EOF
        {
            "tag":"reality-vision",
            "listen": "::",
            "port": $port_vl_re,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "fingerprint": "chrome",
                    "dest": "${ym_vl_re}:443",
                    "serverNames": [
                      "${ym_vl_re}"
                    ],
                    "privateKey": "$private_key_x",
                    "shortIds": ["$short_id_x"]
                }
            },
          "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls", "quic"],
          "metadataOnly": false
      }
    },  
EOF
else
vlp=vlptargo
fi
}

installsb(){
echo
echo "=========启用Sing-box内核========="
if [ ! -e "$HOME/agsbx/sing-box" ]; then
upsingbox
fi
cat > "$HOME/agsbx/sb.json" <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
EOF
insuuid
if [ ! -f "$HOME/agsbx/private.key" ] || [ ! -f "$HOME/agsbx/cert.pem" ]; then
    if command -v openssl >/dev/null 2>&1; then
        openssl ecparam -genkey -name prime256v1 -out "$HOME/agsbx/private.key" >/dev/null 2>&1
        openssl req -new -x509 -days 36500 -key "$HOME/agsbx/private.key" -out "$HOME/agsbx/cert.pem" -subj "/CN=www.bing.com" >/dev/null 2>&1
    fi
fi
if [ ! -f "$HOME/agsbx/private.key" ] || [ ! -f "$HOME/agsbx/cert.pem" ]; then
    log_error "TLS 证书生成失败，请安装 openssl 后重试"
    echo "错误：TLS 证书生成失败，请安装 openssl 后重试"
    exit 1
fi
if [ -n "$hyp" ]; then
hyp=hypt
if [ -z "$port_hy2" ] && [ ! -e "$HOME/agsbx/port_hy2" ]; then
port_hy2=$(shuf -i 10000-65535 -n 1)
echo "$port_hy2" > "$HOME/agsbx/port_hy2"
elif [ -n "$port_hy2" ]; then
echo "$port_hy2" > "$HOME/agsbx/port_hy2"
fi
port_hy2=$(cat "$HOME/agsbx/port_hy2")
echo "Hysteria2端口：$port_hy2"
cat >> "$HOME/agsbx/sb.json" <<EOF
    {
        "type": "hysteria2",
        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ],
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$HOME/agsbx/cert.pem",
            "key_path": "$HOME/agsbx/private.key"
        }
    },
EOF
else
hyp=hyptargo
fi
if [ -n "$tup" ]; then
tup=tupt
if [ -z "$port_tu" ] && [ ! -e "$HOME/agsbx/port_tu" ]; then
port_tu=$(shuf -i 10000-65535 -n 1)
echo "$port_tu" > "$HOME/agsbx/port_tu"
elif [ -n "$port_tu" ]; then
echo "$port_tu" > "$HOME/agsbx/port_tu"
fi
port_tu=$(cat "$HOME/agsbx/port_tu")
echo "Tuic端口：$port_tu"
cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type":"tuic",
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$HOME/agsbx/cert.pem",
                "key_path": "$HOME/agsbx/private.key"
            }
        },
EOF
else
tup=tuptargo
fi
if [ -n "$anp" ]; then
anp=anpt
if [ -z "$port_an" ] && [ ! -e "$HOME/agsbx/port_an" ]; then
port_an=$(shuf -i 10000-65535 -n 1)
echo "$port_an" > "$HOME/agsbx/port_an"
elif [ -n "$port_an" ]; then
echo "$port_an" > "$HOME/agsbx/port_an"
fi
port_an=$(cat "$HOME/agsbx/port_an")
echo "Anytls端口：$port_an"
cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type":"anytls",
            "tag":"anytls-sb",
            "listen":"::",
            "listen_port":${port_an},
            "users":[
                {
                  "password":"${uuid}"
                }
            ],
            "padding_scheme":[],
            "tls":{
                "enabled": true,
                "certificate_path": "$HOME/agsbx/cert.pem",
                "key_path": "$HOME/agsbx/private.key"
            }
        },
EOF
else
anp=anptargo
fi
if [ -n "$arp" ]; then
arp=arpt
if [ -z "$ym_vl_re" ]; then
ym_vl_re=apple.com
fi
echo "$ym_vl_re" > "$HOME/agsbx/ym_vl_re"
echo "Reality域名：$ym_vl_re"
mkdir -p "$HOME/agsbx/sbk"
if [ ! -e "$HOME/agsbx/sbk/private_key" ]; then
key_pair=$("$HOME/agsbx/sing-box" generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
short_id=$("$HOME/agsbx/sing-box" generate rand --hex 4)
echo "$private_key" > "$HOME/agsbx/sbk/private_key"
echo "$public_key" > "$HOME/agsbx/sbk/public_key"
echo "$short_id" > "$HOME/agsbx/sbk/short_id"
fi
private_key_s=$(cat "$HOME/agsbx/sbk/private_key")
public_key_s=$(cat "$HOME/agsbx/sbk/public_key")
short_id_s=$(cat "$HOME/agsbx/sbk/short_id")
if [ -z "$port_ar" ] && [ ! -e "$HOME/agsbx/port_ar" ]; then
port_ar=$(shuf -i 10000-65535 -n 1)
echo "$port_ar" > "$HOME/agsbx/port_ar"
elif [ -n "$port_ar" ]; then
echo "$port_ar" > "$HOME/agsbx/port_ar"
fi
port_ar=$(cat "$HOME/agsbx/port_ar")
echo "Any-Reality端口：$port_ar"
cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type":"anytls",
            "tag":"anyreality-sb",
            "listen":"::",
            "listen_port":${port_ar},
            "users":[
                {
                  "password":"${uuid}"
                }
            ],
            "padding_scheme":[],
            "tls": {
            "enabled": true,
            "server_name": "${ym_vl_re}",
             "reality": {
              "enabled": true,
              "handshake": {
              "server": "${ym_vl_re}",
              "server_port": 443
             },
             "private_key": "$private_key_s",
             "short_id": ["$short_id_s"]
            }
          }
        },
EOF
else
arp=arptargo
fi
if [ -n "$ssp" ]; then
ssp=sspt
if [ ! -e "$HOME/agsbx/sskey" ]; then
sskey=$("$HOME/agsbx/sing-box" generate rand 16 --base64)
echo "$sskey" > "$HOME/agsbx/sskey"
fi
if [ -z "$port_ss" ] && [ ! -e "$HOME/agsbx/port_ss" ]; then
port_ss=$(shuf -i 10000-65535 -n 1)
echo "$port_ss" > "$HOME/agsbx/port_ss"
elif [ -n "$port_ss" ]; then
echo "$port_ss" > "$HOME/agsbx/port_ss"
fi
sskey=$(cat "$HOME/agsbx/sskey")
port_ss=$(cat "$HOME/agsbx/port_ss")
echo "Shadowsocks-2022端口：$port_ss"
cat >> "$HOME/agsbx/sb.json" <<EOF
        {
            "type": "shadowsocks",
            "tag":"ss-2022",
            "listen": "::",
            "listen_port": $port_ss,
            "method": "2022-blake3-aes-128-gcm",
            "password": "$sskey"
    },  
EOF
else
ssp=ssptargo
fi
}

xrsbvm(){
if [ -n "$vmp" ]; then
vmp=vmpt
if [ -z "$port_vm_ws" ] && [ ! -e "$HOME/agsbx/port_vm_ws" ]; then
port_vm_ws=$(shuf -i 10000-65535 -n 1)
echo "$port_vm_ws" > "$HOME/agsbx/port_vm_ws"
elif [ -n "$port_vm_ws" ]; then
echo "$port_vm_ws" > "$HOME/agsbx/port_vm_ws"
fi
port_vm_ws=$(cat "$HOME/agsbx/port_vm_ws")
echo "Vmess-ws端口：$port_vm_ws"
if [ -n "$cdnym" ]; then
echo "$cdnym" > "$HOME/agsbx/cdnym"
echo "80系CDN或者回源CDN的host域名 (确保IP已解析在CF域名)：$cdnym"
fi
if [ -e "$HOME/agsbx/xr.json" ]; then
cat >> "$HOME/agsbx/xr.json" <<EOF
        {
            "tag": "vmess-xhttp-argo",
            "listen": "::",
            "port": ${port_vm_ws},
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "${uuid}"
                    }
                ]
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "none",
                "xhttpSettings": {
                  "path": "${uuid}-vm",
                  "mode": "packet-up"
            }
        },
            "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
            "metadataOnly": false
            }
         }, 
EOF
else
cat >> "$HOME/agsbx/sb.json" <<EOF
{
        "type": "vmess",
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "http",
            "path": "${uuid}-vm"
        }
    },
EOF
fi
else
vmp=vmptargo
fi
}

xrsbso(){
if [ -n "$sop" ]; then
sop=sopt
if [ -z "$port_so" ] && [ ! -e "$HOME/agsbx/port_so" ]; then
port_so=$(shuf -i 10000-65535 -n 1)
echo "$port_so" > "$HOME/agsbx/port_so"
elif [ -n "$port_so" ]; then
echo "$port_so" > "$HOME/agsbx/port_so"
fi
port_so=$(cat "$HOME/agsbx/port_so")
echo "Socks5端口：$port_so"
if [ -e "$HOME/agsbx/xr.json" ]; then
cat >> "$HOME/agsbx/xr.json" <<EOF
        {
         "tag": "socks5-xr",
         "port": ${port_so},
         "listen": "::",
         "protocol": "socks",
         "settings": {
            "auth": "password",
             "accounts": [
               {
               "user": "${uuid}",
               "pass": "${uuid}"
               }
            ],
            "udp": true
          },
            "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"],
            "metadataOnly": false
            }
         }, 
EOF
else
cat >> "$HOME/agsbx/sb.json" <<EOF
    {
      "tag": "socks5-sb",
      "type": "socks",
      "listen": "::",
      "listen_port": ${port_so},
      "users": [
      {
      "username": "${uuid}",
      "password": "${uuid}"
      }
     ]
    },
EOF
fi
else
sop=soptargo
fi
}

xrsbout(){
if [ -e "$HOME/agsbx/xr.json" ]; then
sed -i '${s/,\s*$//}' "$HOME/agsbx/xr.json"
cat >> "$HOME/agsbx/xr.json" <<EOF
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {
      "domainStrategy":"${xryx}"
     }
    },
    {
      "tag": "x-warp-out",
      "protocol": "wireguard",
      "settings": {
        "secretKey": "${pvk}",
        "address": [
          "172.16.0.2/32",
          "${wpv6}/128"
        ],
        "peers": [
          {
            "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
            "allowedIPs": [
              "0.0.0.0/0",
              "::/0"
            ],
            "endpoint": "${xendip}:2408"
          }
        ],
        "reserved": ${res}
        }
    },
    {
      "tag":"warp-out",
      "protocol":"freedom",
        "settings":{
        "domainStrategy":"${wxryx}"
       },
       "proxySettings":{
       "tag":"x-warp-out"
     }
}
  ],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [
      {
        "type": "field",
        "ip": [ ${xip} ],
        "network": "tcp,udp",
        "outboundTag": "${x1outtag}"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "${x2outtag}"
      }
    ]
  }
}
EOF
if pidof systemd >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
cat > /etc/systemd/system/xr.service <<EOF
[Unit]
Description=xr service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=/root/agsbx/xray run -c /root/agsbx/xr.json
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload >/dev/null 2>&1
systemctl enable xr >/dev/null 2>&1
systemctl start xr >/dev/null 2>&1
elif command -v rc-service >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
cat > /etc/init.d/xray <<EOF
#!/sbin/openrc-run
description="xr service"
command="/root/agsbx/xray"
command_args="run -c /root/agsbx/xr.json"
command_background=yes
pidfile="/run/xray.pid"
command_background="yes"
depend() {
need net
}
EOF
chmod +x /etc/init.d/xray >/dev/null 2>&1
rc-update add xray default >/dev/null 2>&1
rc-service xray start >/dev/null 2>&1
else
nohup "$HOME/agsbx/xray" run -c "$HOME/agsbx/xr.json" >/dev/null 2>&1 &
fi
fi
if [ -e "$HOME/agsbx/sb.json" ]; then
sed -i '${s/,\s*$//}' "$HOME/agsbx/sb.json"
cat >> "$HOME/agsbx/sb.json" <<EOF
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-out",
      "address": [
        "172.16.0.2/32",
        "${wpv6}/128"
      ],
      "private_key": "${pvk}",
      "peers": [
        {
          "address": "${sendip}",
          "port": 2408,
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0",
            "::/0"
          ],
          "reserved": $res
        }
      ]
    }
  ],
  "route": {
    "rules": [
       {
          "action": "sniff"
        },
       {
        "action": "resolve",
         "strategy": "${sbyx}"
       },
      {
        "ip_cidr": [ ${sip} ],         
        "outbound": "${s1outtag}"
      }
    ],
    "final": "${s2outtag}"
  }
}
EOF
if pidof systemd >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
cat > /etc/systemd/system/sb.service <<EOF
[Unit]
Description=sb service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=/root/agsbx/sing-box run -c /root/agsbx/sb.json
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload >/dev/null 2>&1
systemctl enable sb >/dev/null 2>&1
systemctl start sb >/dev/null 2>&1
elif command -v rc-service >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
description="sb service"
command="/root/agsbx/sing-box"
command_args="run -c /root/agsbx/sb.json"
command_background=yes
pidfile="/run/sing-box.pid"
command_background="yes"
depend() {
need net
}
EOF
chmod +x /etc/init.d/sing-box >/dev/null 2>&1
rc-update add sing-box default >/dev/null 2>&1
rc-service sing-box start >/dev/null 2>&1
else
nohup "$HOME/agsbx/sing-box" run -c "$HOME/agsbx/sb.json" >/dev/null 2>&1 &
fi
fi
}

# WARP 相关函数（占位符，避免未定义错误）
warpsx(){
    # 如果需要 WARP 功能，请在此处添加相关代码
    log_info "warpsx 函数被调用（当前为占位符）"
    return 0
}

ins(){
if [ "$hyp" != yes ] && [ "$tup" != yes ] && [ "$anp" != yes ] && [ "$arp" != yes ] && [ "$ssp" != yes ]; then
installxray
xrsbvm
xrsbso
warpsx
xrsbout
hyp="hyptargo"; tup="tuptargo"; anp="anptargo"; arp="arptargo"; ssp="ssptargo"
elif [ "$xhp" != yes ] && [ "$vlp" != yes ] && [ "$vxp" != yes ] && [ "$vwp" != yes ]; then
installsb
xrsbvm
xrsbso
warpsx
xrsbout
xhp="xhptargo"; vlp="vlptargo"; vxp="vxptargo"; vwp="vwptargo"
else
installsb
installxray
xrsbvm
xrsbso
warpsx
xrsbout
fi
if [ -n "$argo" ] && [ -n "$vmag" ]; then
echo
echo "=========启用Cloudflared-argo内核========="
if [ ! -e "$HOME/agsbx/cloudflared" ]; then
argocore=$({ command -v curl >/dev/null 2>&1 && curl -Ls https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared || wget -qO- https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared; } | grep -Eo '"[0-9.]+"' | sed -n 1p | tr -d '",')
echo "下载Cloudflared-argo最新正式版内核：$argocore"
url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cpu"; out="$HOME/agsbx/cloudflared"; (command -v curl>/dev/null 2>&1 && curl -Lo "$out" -# --retry 2 "$url") || (command -v wget>/dev/null 2>&1 && timeout 3 wget -O "$out" --tries=2 "$url")
chmod +x "$HOME/agsbx/cloudflared"
fi
if [ "$argo" = "vmpt" ]; then argoport=$(cat "$HOME/agsbx/port_vm_ws" 2>/dev/null); echo "Vmess" > "$HOME/agsbx/vlvm"; elif [ "$argo" = "vwpt" ]; then argoport=$(cat "$HOME/agsbx/port_vw" 2>/dev/null); echo "Vless" > "$HOME/agsbx/vlvm"; fi; echo "$argoport" > "$HOME/agsbx/argoport.log"
if [ -n "${ARGO_DOMAIN}" ] && [ -n "${ARGO_AUTH}" ]; then
argoname='固定'
if pidof systemd >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=argo service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=/root/agsbx/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "${ARGO_AUTH}"
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload >/dev/null 2>&1
systemctl enable argo >/dev/null 2>&1
systemctl start argo >/dev/null 2>&1
elif command -v rc-service >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
cat > /etc/init.d/argo <<EOF
#!/sbin/openrc-run
description="argo service"
command="/root/agsbx/cloudflared tunnel"
command_args="--no-autoupdate --edge-ip-version auto --protocol http2 run --token ${ARGO_AUTH}"
pidfile="/run/argo.pid"
command_background="yes"
depend() {
need net
}
EOF
chmod +x /etc/init.d/argo >/dev/null 2>&1
rc-update add argo default >/dev/null 2>&1
rc-service argo start >/dev/null 2>&1
else
nohup "$HOME/agsbx/cloudflared" tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "${ARGO_AUTH}" >/dev/null 2>&1 &
fi
echo "${ARGO_DOMAIN}" > "$HOME/agsbx/sbargoym.log"
echo "${ARGO_AUTH}" > "$HOME/agsbx/sbargotoken.log"
else
argoname='临时'
nohup "$HOME/agsbx/cloudflared" tunnel --url http://localhost:$(cat $HOME/agsbx/argoport.log) --edge-ip-version auto --no-autoupdate --protocol http2 > $HOME/agsbx/argo.log 2>&1 &
fi
echo "申请Argo$argoname隧道中……请稍等"
sleep 8
if [ -n "${ARGO_DOMAIN}" ] && [ -n "${ARGO_AUTH}" ]; then
argodomain=$(cat "$HOME/agsbx/sbargoym.log" 2>/dev/null)
else
argodomain=$(grep -a trycloudflare.com "$HOME/agsbx/argo.log" 2>/dev/null | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
fi
if [ -n "${argodomain}" ]; then
echo "Argo$argoname隧道申请成功"
else
echo "Argo$argoname隧道申请失败，请稍后再试"
fi
fi
sleep 5
echo
if find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -Eq 'agsbx/(s|x)' || pgrep -f 'agsbx/(s|x)' >/dev/null 2>&1 ; then
[ -f ~/.bashrc ] || touch ~/.bashrc
sed -i '/agsbx/d' ~/.bashrc
SCRIPT_PATH="$HOME/bin/agsbx"
mkdir -p "$HOME/bin"
(command -v curl >/dev/null 2>&1 && curl -sL "$agsbxurl" -o "$SCRIPT_PATH") || (command -v wget >/dev/null 2>&1 && wget -qO "$SCRIPT_PATH" "$agsbxurl")
chmod +x "$SCRIPT_PATH"
if ! pidof systemd >/dev/null 2>&1 && ! command -v rc-service >/dev/null 2>&1; then
echo "if ! find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -Eq 'agsbx/(s|x)' && ! pgrep -f 'agsbx/(s|x)' >/dev/null 2>&1; then echo '检测到系统可能中断过，或者变量格式错误？建议在SSH对话框输入 reboot 重启下服务器。现在自动执行Argosbx脚本的节点恢复操作，请稍等……'; sleep 6; export cdnym=\"${cdnym}\" name=\"${name}\" ippz=\"${ippz}\" argo=\"${argo}\" uuid=\"${uuid}\" $wap=\"${warp}\" $xhp=\"${port_xh}\" $vxp=\"${port_vx}\" $ssp=\"${port_ss}\" $sop=\"${port_so}\" $anp=\"${port_an}\" $arp=\"${port_ar}\" $vlp=\"${port_vl_re}\" $vwp=\"${port_vw}\" $vmp=\"${port_vm_ws}\" $hyp=\"${port_hy2}\" $tup=\"${port_tu}\" reym=\"${ym_vl_re}\" agn=\"${ARGO_DOMAIN}\" agk=\"${ARGO_AUTH}\"; bash "$HOME/bin/agsbx"; fi" >> ~/.bashrc
fi
sed -i '/export PATH="\$HOME\/bin:\$PATH"/d' ~/.bashrc
echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
grep -qxF 'source ~/.bashrc' ~/.bash_profile 2>/dev/null || echo 'source ~/.bashrc' >> ~/.bash_profile
. ~/.bashrc 2>/dev/null
crontab -l > /tmp/crontab.tmp 2>/dev/null
if ! pidof systemd >/dev/null 2>&1 && ! command -v rc-service >/dev/null 2>&1; then
sed -i '/agsbx\/sing-box/d' /tmp/crontab.tmp
sed -i '/agsbx\/xray/d' /tmp/crontab.tmp
if find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -q 'agsbx/s' || pgrep -f 'agsbx/s' >/dev/null 2>&1 ; then
echo '@reboot sleep 10 && /bin/sh -c "nohup $HOME/agsbx/sing-box run -c $HOME/agsbx/sb.json >/dev/null 2>&1 &"' >> /tmp/crontab.tmp
fi
if find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -q 'agsbx/x' || pgrep -f 'agsbx/x' >/dev/null 2>&1 ; then
echo '@reboot sleep 10 && /bin/sh -c "nohup $HOME/agsbx/xray run -c $HOME/agsbx/xr.json >/dev/null 2>&1 &"' >> /tmp/crontab.tmp
fi
fi
sed -i '/agsbx\/cloudflared/d' /tmp/crontab.tmp
if [ -n "$argo" ] && [ -n "$vmag" ]; then
if [ -n "${ARGO_DOMAIN}" ] && [ -n "${ARGO_AUTH}" ]; then
if ! pidof systemd >/dev/null 2>&1 && ! command -v rc-service >/dev/null 2>&1; then
echo '@reboot sleep 10 && /bin/sh -c "nohup $HOME/agsbx/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token $(cat $HOME/agsbx/sbargotoken.log 2>/dev/null) >/dev/null 2>&1 &"' >> /tmp/crontab.tmp
fi
else
echo '@reboot sleep 10 && /bin/sh -c "nohup $HOME/agsbx/cloudflared tunnel --url http://localhost:$(cat $HOME/agsbx/argoport.log) --edge-ip-version auto --no-autoupdate --protocol http2 > $HOME/agsbx/argo.log 2>&1 &"' >> /tmp/crontab.tmp
fi
fi
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
echo "Argosbx脚本进程启动成功，安装完毕" && sleep 2
else
echo "Argosbx脚本进程未启动，安装失败" && exit
fi
}
argosbxstatus(){
echo "=========当前三大内核运行状态========="
procs=$(find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null)
if echo "$procs" | grep -Eq 'agsbx/s' || pgrep -f 'agsbx/s' >/dev/null 2>&1; then
echo "Sing-box (版本V$("$HOME/agsbx/sing-box" version 2>/dev/null | awk '/version/{print $NF}'))：运行中"
else
echo "Sing-box：未启用"
fi
if echo "$procs" | grep -Eq 'agsbx/x' || pgrep -f 'agsbx/x' >/dev/null 2>&1; then
echo "Xray (版本V$("$HOME/agsbx/xray" version 2>/dev/null | awk '/^Xray/{print $2}'))：运行中"
else
echo "Xray：未启用"
fi
if echo "$procs" | grep -Eq 'agsbx/c' || pgrep -f 'agsbx/c' >/dev/null 2>&1; then
echo "Argo (版本V$("$HOME/agsbx/cloudflared" version 2>/dev/null | awk '{print $3}'))：运行中"
else
echo "Argo：未启用"
fi
}
cip(){
ipbest(){
serip=$( (command -v curl >/dev/null 2>&1 && (curl -s4m5 -k "$v46url" 2>/dev/null || curl -s6m5 -k "$v46url" 2>/dev/null) ) || (command -v wget >/dev/null 2>&1 && (timeout 3 wget -4 -qO- --tries=2 "$v46url" 2>/dev/null || timeout 3 wget -6 -qO- --tries=2 "$v46url" 2>/dev/null) ) )
if echo "$serip" | grep -q ':'; then
server_ip="[$serip]"
echo "$server_ip" > "$HOME/agsbx/server_ip.log"
else
server_ip="$serip"
echo "$server_ip" > "$HOME/agsbx/server_ip.log"
fi
}
ipchange(){
v4v6
if [ -z "$v4" ]; then
vps_ipv4='无IPV4'
vps_ipv6="$v6"
location="$v6dq"
elif [ -n "$v4" ] && [ -n "$v6" ]; then
vps_ipv4="$v4"
vps_ipv6="$v6"
location="$v4dq"
else
vps_ipv4="$v4"
vps_ipv6='无IPV6'
location="$v4dq"
fi
if echo "$v6" | grep -q '^2a09'; then
w6="【WARP】"
fi
if echo "$v4" | grep -q '^104.28'; then
w4="【WARP】"
fi
echo
argosbxstatus
echo
echo "=========当前服务器本地IP情况========="
echo "本地IPV4地址：$vps_ipv4 $w4"
echo "本地IPV6地址：$vps_ipv6 $w6"
echo "服务器地区：$location"
echo
sleep 2
if [ "$ippz" = "4" ]; then
if [ -z "$v4" ]; then
ipbest
else
server_ip="$v4"
echo "$server_ip" > "$HOME/agsbx/server_ip.log"
fi
elif [ "$ippz" = "6" ]; then
if [ -z "$v6" ]; then
ipbest
else
server_ip="[$v6]"
echo "$server_ip" > "$HOME/agsbx/server_ip.log"
fi
else
ipbest
fi
}
ipchange
rm -rf "$HOME/agsbx/jh.txt"
uuid=$(cat "$HOME/agsbx/uuid")
server_ip=$(cat "$HOME/agsbx/server_ip.log")
sxname=$(cat "$HOME/agsbx/name" 2>/dev/null)
xvvmcdnym=$(cat "$HOME/agsbx/cdnym" 2>/dev/null)
echo "*********************************************************"
echo "*********************************************************"
echo "Argosbx脚本输出节点配置如下："
echo
case "$server_ip" in
104.28*|\[2a09*) echo "检测到有WARP的IP作为客户端地址 (104.28或者2a09开头的IP)，请把客户端地址上的WARP的IP手动更换为VPS本地IPV4或者IPV6地址" && sleep 3 ;;
esac
echo
ym_vl_re=$(cat "$HOME/agsbx/ym_vl_re" 2>/dev/null)
cfip() { echo $((RANDOM % 13 + 1)); }
if [ -e "$HOME/agsbx/xray" ]; then
private_key_x=$(cat "$HOME/agsbx/xrk/private_key" 2>/dev/null)
public_key_x=$(cat "$HOME/agsbx/xrk/public_key" 2>/dev/null)
short_id_x=$(cat "$HOME/agsbx/xrk/short_id" 2>/dev/null)
enkey=$(cat "$HOME/agsbx/xrk/enkey" 2>/dev/null)
fi
if [ -e "$HOME/agsbx/sing-box" ]; then
private_key_s=$(cat "$HOME/agsbx/sbk/private_key" 2>/dev/null)
public_key_s=$(cat "$HOME/agsbx/sbk/public_key" 2>/dev/null)
short_id_s=$(cat "$HOME/agsbx/sbk/short_id" 2>/dev/null)
sskey=$(cat "$HOME/agsbx/sskey" 2>/dev/null)
fi
if grep xhttp-reality "$HOME/agsbx/xr.json" >/dev/null 2>&1; then
echo "💣【 Vless-xhttp-reality-enc 】支持ENC加密，节点信息如下："
port_xh=$(cat "$HOME/agsbx/port_xh")
vl_xh_link="vless://$uuid@$server_ip:$port_xh?encryption=$enkey&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_x&sid=$short_id_x&type=xhttp&path=$uuid-xh&mode=auto#${sxname}vl-xhttp-reality-enc-$hostname"
echo "$vl_xh_link" >> "$HOME/agsbx/jh.txt"
echo "$vl_xh_link"
echo
fi
if grep vless-xhttp "$HOME/agsbx/xr.json" >/dev/null 2>&1; then
echo "💣【 Vless-xhttp-enc 】支持ENC加密，节点信息如下："
port_vx=$(cat "$HOME/agsbx/port_vx")
vl_vx_link="vless://$uuid@$server_ip:$port_vx?encryption=$enkey&type=xhttp&path=$uuid-vx&mode=auto#${sxname}vl-xhttp-enc-$hostname"
echo "$vl_vx_link" >> "$HOME/agsbx/jh.txt"
echo "$vl_vx_link"
echo
if [ -f "$HOME/agsbx/cdnym" ]; then
echo "💣【 Vless-xhttp-ecn-cdn 】支持ENC加密，节点信息如下："
echo "注：默认地址 yg数字.ygkkk.dpdns.org 可自行更换优选IP域名，如是回源端口需手动修改443或者80系端口"
vl_vx_cdn_link="vless://$uuid@yg$(cfip).ygkkk.dpdns.org:$port_vx?encryption=$enkey&type=xhttp&host=$xvvmcdnym&path=$uuid-vx&mode=auto#${sxname}vl-xhttp-enc-cdn-$hostname"
echo "$vl_vx_cdn_link" >> "$HOME/agsbx/jh.txt"
echo "$vl_vx_cdn_link"
echo
fi
fi
if grep vless-xhttp-cdn "$HOME/agsbx/xr.json" >/dev/null 2>&1; then
echo "💣【 Vless-xhttp-enc 】支持ENC加密，节点信息如下："
port_vw=$(cat "$HOME/agsbx/port_vw")
vl_vw_link="vless://$uuid@$server_ip:$port_vw?encryption=$enkey&type=xhttp&path=$uuid-vw&mode=packet-up#${sxname}vl-xhttp-enc-$hostname"
echo "$vl_vw_link" >> "$HOME/agsbx/jh.txt"
echo "$vl_vw_link"
echo
if [ -f "$HOME/agsbx/cdnym" ]; then
echo "💣【 Vless-xhttp-enc-cdn 】支持ENC加密，节点信息如下："
echo "注：默认地址 yg数字.ygkkk.dpdns.org 可自行更换优选IP域名，如是回源端口需手动修改443或者80系端口"
vl_vw_cdn_link="vless://$uuid@yg$(cfip).ygkkk.dpdns.org:$port_vw?encryption=$enkey&type=xhttp&host=$xvvmcdnym&path=$uuid-vw&mode=packet-up#${sxname}vl-xhttp-enc-cdn-$hostname"
echo "$vl_vw_cdn_link" >> "$HOME/agsbx/jh.txt"
echo "$vl_vw_cdn_link"
echo
fi
fi
if grep reality-vision "$HOME/agsbx/xr.json" >/dev/null 2>&1; then
echo "💣【 Vless-tcp-reality-vision 】节点信息如下："
port_vl_re=$(cat "$HOME/agsbx/port_vl_re")
vl_link="vless://$uuid@$server_ip:$port_vl_re?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_x&sid=$short_id_x&type=tcp&headerType=none#${sxname}vl-reality-vision-$hostname"
echo "$vl_link" >> "$HOME/agsbx/jh.txt"
echo "$vl_link"
echo
fi
if grep ss-2022 "$HOME/agsbx/sb.json" >/dev/null 2>&1; then
echo "💣【 Shadowsocks-2022 】节点信息如下："
port_ss=$(cat "$HOME/agsbx/port_ss")
ss_link="ss://$(echo -n "2022-blake3-aes-128-gcm:$sskey@$server_ip:$port_ss" | base64 -w0)#${sxname}Shadowsocks-2022-$hostname"
echo "$ss_link" >> "$HOME/agsbx/jh.txt"
echo "$ss_link"
echo
fi
if grep vmess-xr "$HOME/agsbx/xr.json" >/dev/null 2>&1 || grep vmess-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then
echo "💣【 Vmess-ws 】节点信息如下："
port_vm_ws=$(cat "$HOME/agsbx/port_vm_ws")
vm_link="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vm-ws-$hostname\", \"add\": \"$server_ip\", \"port\": \"$port_vm_ws\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"www.bing.com\", \"path\": \"/$uuid-vm\", \"tls\": \"\"}" | base64 -w0)"
echo "$vm_link" >> "$HOME/agsbx/jh.txt"
echo "$vm_link"
echo
if [ -f "$HOME/agsbx/cdnym" ]; then
echo "💣【 Vmess-ws-cdn 】节点信息如下："
echo "注：默认地址 yg数字.ygkkk.dpdns.org 可自行更换优选IP域名，如是回源端口需手动修改443或者80系端口"
vm_cdn_link="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vm-ws-cdn-$hostname\", \"add\": \"yg$(cfip).ygkkk.dpdns.org\", \"port\": \"$port_vm_ws\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"$xvvmcdnym\", \"path\": \"/$uuid-vm\", \"tls\": \"\"}" | base64 -w0)"
echo "$vm_cdn_link" >> "$HOME/agsbx/jh.txt"
echo "$vm_cdn_link"
echo
fi
fi
if grep anytls-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then
echo "💣【 AnyTLS 】节点信息如下："
port_an=$(cat "$HOME/agsbx/port_an")
an_link="anytls://$uuid@$server_ip:$port_an?insecure=1&allowInsecure=1#${sxname}anytls-$hostname"
echo "$an_link" >> "$HOME/agsbx/jh.txt"
echo "$an_link"
echo
fi
if grep anyreality-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then
echo "💣【 Any-Reality 】节点信息如下："
port_ar=$(cat "$HOME/agsbx/port_ar")
ar_link="anytls://$uuid@$server_ip:$port_ar?security=reality&sni=$ym_vl_re&fp=chrome&pbk=$public_key_s&sid=$short_id_s&type=tcp&headerType=none#${sxname}any-reality-$hostname"
echo "$ar_link" >> "$HOME/agsbx/jh.txt"
echo "$ar_link"
echo
fi
if grep hy2-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then
echo "💣【 Hysteria2 】节点信息如下："
port_hy2=$(cat "$HOME/agsbx/port_hy2")
hy2_link="hysteria2://$uuid@$server_ip:$port_hy2?security=tls&alpn=h3&insecure=1&sni=www.bing.com#${sxname}hy2-$hostname"
echo "$hy2_link" >> "$HOME/agsbx/jh.txt"
echo "$hy2_link"
echo
fi
if grep tuic5-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then
echo "💣【 Tuic 】节点信息如下："
port_tu=$(cat "$HOME/agsbx/port_tu")
tuic5_link="tuic://$uuid:$uuid@$server_ip:$port_tu?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=www.bing.com&allow_insecure=1&allowInsecure=1#${sxname}tuic-$hostname"
echo "$tuic5_link" >> "$HOME/agsbx/jh.txt"
echo "$tuic5_link"
echo
fi
if grep socks5-xr "$HOME/agsbx/xr.json" >/dev/null 2>&1 || grep socks5-sb "$HOME/agsbx/sb.json" >/dev/null 2>&1; then
echo "💣【 Socks5 】客户端信息如下："
port_so=$(cat "$HOME/agsbx/port_so")
echo "请配合其他应用内置代理使用，勿做节点直接使用"
echo "客户端地址：$server_ip"
echo "客户端端口：$port_so"
echo "客户端用户名：$uuid"
echo "客户端密码：$uuid"
echo
fi
argodomain=$(cat "$HOME/agsbx/sbargoym.log" 2>/dev/null)
[ -z "$argodomain" ] && argodomain=$(grep -a trycloudflare.com "$HOME/agsbx/argo.log" 2>/dev/null | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
if [ -n "$argodomain" ]; then
vlvm=$(cat $HOME/agsbx/vlvm 2>/dev/null)
if [ "$vlvm" = "Vmess" ]; then
vmatls_link1="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-tls-argo-$hostname-443\", \"add\": \"yg1.ygkkk.dpdns.org\", \"port\": \"443\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"chrome\"}" | base64 -w0)"
echo "$vmatls_link1" >> "$HOME/agsbx/jh.txt"
vmatls_link2="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-tls-argo-$hostname-8443\", \"add\": \"yg2.ygkkk.dpdns.org\", \"port\": \"8443\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"chrome\"}" | base64 -w0)"
echo "$vmatls_link2" >> "$HOME/agsbx/jh.txt"
vmatls_link3="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-tls-argo-$hostname-2053\", \"add\": \"yg3.ygkkk.dpdns.org\", \"port\": \"2053\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"chrome\"}" | base64 -w0)"
echo "$vmatls_link3" >> "$HOME/agsbx/jh.txt"
vmatls_link4="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-tls-argo-$hostname-2083\", \"add\": \"yg4.ygkkk.dpdns.org\", \"port\": \"2083\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"chrome\"}" | base64 -w0)"
echo "$vmatls_link4" >> "$HOME/agsbx/jh.txt"
vmatls_link5="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-tls-argo-$hostname-2087\", \"add\": \"yg5.ygkkk.dpdns.org\", \"port\": \"2087\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"chrome\"}" | base64 -w0)"
echo "$vmatls_link5" >> "$HOME/agsbx/jh.txt"
vmatls_link6="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-tls-argo-$hostname-2096\", \"add\": \"[2606:4700::0]\", \"port\": \"2096\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"tls\", \"sni\": \"$argodomain\", \"alpn\": \"\", \"fp\": \"chrome\"}" | base64 -w0)"
echo "$vmatls_link6" >> "$HOME/agsbx/jh.txt"
vma_link7="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-argo-$hostname-80\", \"add\": \"yg6.ygkkk.dpdns.org\", \"port\": \"80\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link7" >> "$HOME/agsbx/jh.txt"
vma_link8="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-argo-$hostname-8080\", \"add\": \"yg7.ygkkk.dpdns.org\", \"port\": \"8080\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link8" >> "$HOME/agsbx/jh.txt"
vma_link9="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-argo-$hostname-8880\", \"add\": \"yg8.ygkkk.dpdns.org\", \"port\": \"8880\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link9" >> "$HOME/agsbx/jh.txt"
vma_link10="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-argo-$hostname-2052\", \"add\": \"yg9.ygkkk.dpdns.org\", \"port\": \"2052\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link10" >> "$HOME/agsbx/jh.txt"
vma_link11="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-argo-$hostname-2082\", \"add\": \"yg10.ygkkk.dpdns.org\", \"port\": \"2082\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link11" >> "$HOME/agsbx/jh.txt"
vma_link12="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-argo-$hostname-2086\", \"add\": \"yg11.ygkkk.dpdns.org\", \"port\": \"2086\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link12" >> "$HOME/agsbx/jh.txt"
vma_link13="vmess://$(echo "{ \"v\": \"2\", \"ps\": \"${sxname}vmess-xhttp-argo-$hostname-2095\", \"add\": \"[2400:cb00:2049::0]\", \"port\": \"2095\", \"id\": \"$uuid\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"xhttp\", \"type\": \"none\", \"host\": \"$argodomain\", \"path\": \"/$uuid-vm\", \"tls\": \"\"}" | base64 -w0)"
echo "$vma_link13" >> "$HOME/agsbx/jh.txt"
elif [ "$vlvm" = "Vless" ]; then
vwatls_link1="vless://$uuid@yg$(cfip).ygkkk.dpdns.org:443?encryption=$enkey&type=xhttp&host=$argodomain&path=$uuid-vw&mode=packet-up&security=tls&sni=$argodomain&fp=chrome&insecure=0&allowInsecure=0#${sxname}vless-xhttp-tls-argo-enc-$hostname"
echo "$vwatls_link1" >> "$HOME/agsbx/jh.txt"
vwa_link2="vless://$uuid@yg$(cfip).ygkkk.dpdns.org:80?encryption=$enkey&type=xhttp&host=$argodomain&path=$uuid-vw&mode=packet-up&security=none#${sxname}vless-xhttp-argo-enc-$hostname"
echo "$vwa_link2" >> "$HOME/agsbx/jh.txt"
fi
sbtk=$(cat "$HOME/agsbx/sbargotoken.log" 2>/dev/null)
if [ -n "$sbtk" ]; then
nametn="Argo固定隧道token：$sbtk"
fi
argoshow=$(
echo "Argo隧道端口正在使用$vlvm-ws主协议端口：$(cat $HOME/agsbx/argoport.log 2>/dev/null)
Argo域名：$argodomain
$nametn

1、💣443端口的$vlvm-ws-tls-argo节点(优选IP与443系端口随便换)
${vmatls_link1}${vwatls_link1}

2、💣80端口的$vlvm-ws-argo节点(优选IP与80系端口随便换)
${vma_link7}${vwa_link2}
"
)
fi
echo "---------------------------------------------------------"
echo "$argoshow"
echo
echo "---------------------------------------------------------"
echo "聚合节点信息，请进入 $HOME/agsbx/jh.txt 文件目录查看或者运行 cat $HOME/agsbx/jh.txt 查看"
echo ""
echo "正在生成订阅文件..."
save_subscription_files "$HOME/agsbx/jh.txt" "$HOME/agsbx"
echo "========================================================="
echo "相关快捷方式如下：(首次安装成功后需重连SSH，agsbx快捷方式才可生效)"
showmode
}
cleandel(){
for P in /proc/[0-9]*; do if [ -L "$P/exe" ]; then TARGET=$(readlink -f "$P/exe" 2>/dev/null); if echo "$TARGET" | grep -qE '/agsbx/c|/agsbx/s|/agsbx/x'; then PID=$(basename "$P"); kill "$PID" 2>/dev/null; fi; fi; done
kill -15 $(pgrep -f 'agsbx/s' 2>/dev/null) $(pgrep -f 'agsbx/c' 2>/dev/null) $(pgrep -f 'agsbx/x' 2>/dev/null) >/dev/null 2>&1
sed -i '/agsbx/d' ~/.bashrc
sed -i '/export PATH="\$HOME\/bin:\$PATH"/d' ~/.bashrc
. ~/.bashrc 2>/dev/null
crontab -l > /tmp/crontab.tmp 2>/dev/null
sed -i '/agsbx\/sing-box/d' /tmp/crontab.tmp
sed -i '/agsbx\/xray/d' /tmp/crontab.tmp
sed -i '/agsbx\/cloudflared/d' /tmp/crontab.tmp
crontab /tmp/crontab.tmp >/dev/null 2>&1
rm /tmp/crontab.tmp
rm -rf  "$HOME/bin/agsbx"
if pidof systemd >/dev/null 2>&1; then
for svc in xr sb argo; do
systemctl stop "$svc" >/dev/null 2>&1
systemctl disable "$svc" >/dev/null 2>&1
done
rm -rf /etc/systemd/system/{xr.service,sb.service,argo.service}
elif command -v rc-service >/dev/null 2>&1; then
for svc in sing-box xray argo; do
rc-service "$svc" stop >/dev/null 2>&1
rc-update del "$svc" default >/dev/null 2>&1
done
rm -rf /etc/init.d/{sing-box,xray,argo}
fi
}
xrestart(){
kill -15 $(pgrep -f 'agsbx/x' 2>/dev/null) >/dev/null 2>&1
if pidof systemd >/dev/null 2>&1; then
systemctl restart xr >/dev/null 2>&1
elif command -v rc-service >/dev/null 2>&1; then
rc-service xray restart >/dev/null 2>&1
else
nohup $HOME/agsbx/xray run -c $HOME/agsbx/xr.json >/dev/null 2>&1 &
fi
}
sbrestart(){
kill -15 $(pgrep -f 'agsbx/s' 2>/dev/null) >/dev/null 2>&1
if pidof systemd >/dev/null 2>&1; then
systemctl restart sb >/dev/null 2>&1
elif command -v rc-service >/dev/null 2>&1; then
rc-service sing-box restart >/dev/null 2>&1
else
nohup $HOME/agsbx/sing-box run -c $HOME/agsbx/sb.json >/dev/null 2>&1 &
fi
}

# ============================================================================
# 订阅生成功能（集成版）
# ============================================================================

generate_v2ray_subscription() {
    local jh_file=$1
    [ ! -f "$jh_file" ] && return 1
    cat "$jh_file" | base64 -w0
}

decode_vmess_link() {
    local link=$1
    local b64_part="${link#vmess://}"
    local json=$(echo "$b64_part" | base64 -d 2>/dev/null)
    [ -z "$json" ] && return 1

    if command -v jq >/dev/null 2>&1; then
        vm_ps=$(echo "$json" | jq -r '.ps // ""')
        vm_add=$(echo "$json" | jq -r '.add // ""')
        vm_port=$(echo "$json" | jq -r '.port // ""')
        vm_id=$(echo "$json" | jq -r '.id // ""')
        vm_aid=$(echo "$json" | jq -r '.aid // "0"')
        vm_net=$(echo "$json" | jq -r '.net // "tcp"')
        vm_type=$(echo "$json" | jq -r '.type // "none"')
        vm_host=$(echo "$json" | jq -r '.host // ""')
        vm_path=$(echo "$json" | jq -r '.path // ""')
        vm_tls=$(echo "$json" | jq -r '.tls // ""')
        vm_sni=$(echo "$json" | jq -r '.sni // .host // ""')
    else
        vm_ps=$(echo "$json" | grep -oP '"ps"\s*:\s*"\K[^"]+' || echo "")
        vm_add=$(echo "$json" | grep -oP '"add"\s*:\s*"\K[^"]+' || echo "")
        vm_port=$(echo "$json" | grep -oP '"port"\s*:\s*"\K[^"]+' || echo "")
        vm_id=$(echo "$json" | grep -oP '"id"\s*:\s*"\K[^"]+' || echo "")
        vm_aid=$(echo "$json" | grep -oP '"aid"\s*:\s*"\K[^"]+' || echo "0")
        vm_net=$(echo "$json" | grep -oP '"net"\s*:\s*"\K[^"]+' || echo "tcp")
        vm_type=$(echo "$json" | grep -oP '"type"\s*:\s*"\K[^"]+' || echo "none")
        vm_host=$(echo "$json" | grep -oP '"host"\s*:\s*"\K[^"]+' || echo "")
        vm_path=$(echo "$json" | grep -oP '"path"\s*:\s*"\K[^"]+' || echo "")
        vm_tls=$(echo "$json" | grep -oP '"tls"\s*:\s*"\K[^"]+' || echo "")
        vm_sni=$(echo "$json" | grep -oP '"sni"\s*:\s*"\K[^"]+' || echo "$vm_host")
    fi
    export vm_ps vm_add vm_port vm_id vm_aid vm_net vm_type vm_host vm_path vm_tls vm_sni
}

decode_vless_link() {
    local link=$1
    local uuid_part="${link#vless://}"
    local name="${uuid_part##*#}"
    uuid_part="${uuid_part%%#*}"
    local uuid="${uuid_part%%@*}"
    local addr_part="${uuid_part#*@}"
    local host="${addr_part%%:*}"
    local port_part="${addr_part#*:}"
    local port="${port_part%%\?*}"
    local params="${link#*\?}"
    params="${params%%#*}"

    vl_encryption=$(echo "$params" | grep -oP 'encryption=\K[^&]+' || echo "none")
    vl_security=$(echo "$params" | grep -oP 'security=\K[^&]+' || echo "none")
    vl_type=$(echo "$params" | grep -oP 'type=\K[^&]+' || echo "tcp")
    vl_host=$(echo "$params" | grep -oP 'host=\K[^&]+' || echo "")
    vl_path=$(echo "$params" | grep -oP 'path=\K[^&]+' || echo "")
    vl_sni=$(echo "$params" | grep -oP 'sni=\K[^&]+' || echo "$vl_host")
    vl_flow=$(echo "$params" | grep -oP 'flow=\K[^&]+' || echo "")
    vl_fp=$(echo "$params" | grep -oP 'fp=\K[^&]+' || echo "")
    vl_pbk=$(echo "$params" | grep -oP 'pbk=\K[^&]+' || echo "")
    vl_sid=$(echo "$params" | grep -oP 'sid=\K[^&]+' || echo "")
    vl_mode=$(echo "$params" | grep -oP 'mode=\K[^&]+' || echo "")

    export vl_name="$name" vl_uuid="$uuid" vl_host_addr="$host" vl_port="$port"
    export vl_encryption vl_security vl_type vl_host vl_path vl_sni vl_flow vl_fp vl_pbk vl_sid vl_mode
}

generate_clash_vmess_proxy() {
    local link=$1
    decode_vmess_link "$link" || return 1
    local name="${vm_ps:-VMess}"

    cat <<EOF
  - name: "$name"
    type: vmess
    server: $vm_add
    port: $vm_port
    uuid: $vm_id
    alterId: $vm_aid
    cipher: auto
EOF

    if [ "$vm_tls" = "tls" ]; then
        cat <<EOF
    tls: true
    skip-cert-verify: true
EOF
        [ -n "$vm_sni" ] && echo "    servername: $vm_sni"
    fi

    case "$vm_net" in
        ws)
            cat <<EOF
    network: ws
EOF
            [ -n "$vm_path" ] && echo "    ws-opts:"
            [ -n "$vm_path" ] && echo "      path: $vm_path"
            [ -n "$vm_host" ] && echo "      headers:"
            [ -n "$vm_host" ] && echo "        Host: $vm_host"
            ;;
        xhttp|http)
            cat <<EOF
    network: http
EOF
            [ -n "$vm_path" ] && echo "    http-opts:"
            [ -n "$vm_path" ] && echo "      path:"
            [ -n "$vm_path" ] && echo "        - $vm_path"
            [ -n "$vm_host" ] && echo "      headers:"
            [ -n "$vm_host" ] && echo "        Host:"
            [ -n "$vm_host" ] && echo "          - $vm_host"
            ;;
        grpc)
            cat <<EOF
    network: grpc
EOF
            [ -n "$vm_path" ] && echo "    grpc-opts:"
            [ -n "$vm_path" ] && echo "      grpc-service-name: $vm_path"
            ;;
    esac
}

generate_clash_vless_proxy() {
    local link=$1
    decode_vless_link "$link" || return 1
    local name="${vl_name:-VLESS}"

    cat <<EOF
  - name: "$name"
    type: vless
    server: $vl_host_addr
    port: $vl_port
    uuid: $vl_uuid
EOF

    if [ "$vl_security" = "tls" ] || [ "$vl_security" = "reality" ]; then
        cat <<EOF
    tls: true
    skip-cert-verify: true
EOF
        [ -n "$vl_sni" ] && echo "    servername: $vl_sni"

        if [ "$vl_security" = "reality" ]; then
            [ -n "$vl_pbk" ] && echo "    reality-opts:"
            [ -n "$vl_pbk" ] && echo "      public-key: $vl_pbk"
            [ -n "$vl_sid" ] && echo "      short-id: $vl_sid"
        fi

        [ -n "$vl_fp" ] && echo "    client-fingerprint: $vl_fp"
    fi

    [ -n "$vl_flow" ] && echo "    flow: $vl_flow"

    case "$vl_type" in
        ws)
            cat <<EOF
    network: ws
EOF
            [ -n "$vl_path" ] && echo "    ws-opts:"
            [ -n "$vl_path" ] && echo "      path: $vl_path"
            [ -n "$vl_host" ] && echo "      headers:"
            [ -n "$vl_host" ] && echo "        Host: $vl_host"
            ;;
        xhttp|http)
            cat <<EOF
    network: http
EOF
            [ -n "$vl_path" ] && echo "    http-opts:"
            [ -n "$vl_path" ] && echo "      path:"
            [ -n "$vl_path" ] && echo "        - $vl_path"
            [ -n "$vl_host" ] && echo "      headers:"
            [ -n "$vl_host" ] && echo "        Host:"
            [ -n "$vl_host" ] && echo "          - $vl_host"
            ;;
        grpc)
            cat <<EOF
    network: grpc
EOF
            [ -n "$vl_path" ] && echo "    grpc-opts:"
            [ -n "$vl_path" ] && echo "      grpc-service-name: $vl_path"
            ;;
    esac
}

generate_clash_ss_proxy() {
    local link=$1
    local b64_part="${link#ss://}"
    local name="${b64_part##*#}"
    b64_part="${b64_part%%#*}"

    if [[ "$b64_part" == *"@"* ]]; then
        local method_pass="${b64_part%%@*}"
        local method="${method_pass%%:*}"
        local password="${method_pass#*:}"
        local addr="${b64_part#*@}"
        local server="${addr%%:*}"
        local port="${addr#*:}"
    else
        local decoded=$(echo "$b64_part" | base64 -d 2>/dev/null)
        local method_pass="${decoded%%@*}"
        local method="${method_pass%%:*}"
        local password="${method_pass#*:}"
        local addr="${decoded#*@}"
        local server="${addr%%:*}"
        local port="${addr#*:}"
    fi

    cat <<EOF
  - name: "$name"
    type: ss
    server: $server
    port: $port
    cipher: $method
    password: "$password"
EOF
}

generate_clash_hysteria2_proxy() {
    local link=$1
    local pwd_part="${link#hysteria2://}"
    local name="${pwd_part##*#}"
    pwd_part="${pwd_part%%#*}"
    local password="${pwd_part%%@*}"
    local addr_part="${pwd_part#*@}"
    local host="${addr_part%%:*}"
    local port_part="${addr_part#*:}"
    local port="${port_part%%\?*}"
    local params="${link#*\?}"
    params="${params%%#*}"
    local sni=$(echo "$params" | grep -oP 'sni=\K[^&]+' || echo "$host")

    cat <<EOF
  - name: "$name"
    type: hysteria2
    server: $host
    port: $port
    password: "$password"
    skip-cert-verify: true
EOF
    [ -n "$sni" ] && [ "$sni" != "$host" ] && echo "    sni: $sni"
}

generate_clash_tuic_proxy() {
    local link=$1
    local uuid_pwd_part="${link#tuic://}"
    local name="${uuid_pwd_part##*#}"
    uuid_pwd_part="${uuid_pwd_part%%#*}"
    local uuid="${uuid_pwd_part%%:*}"
    local pwd_addr="${uuid_pwd_part#*:}"
    local password="${pwd_addr%%@*}"
    local addr_part="${pwd_addr#*@}"
    local host="${addr_part%%:*}"
    local port_part="${addr_part#*:}"
    local port="${port_part%%\?*}"
    local params="${link#*\?}"
    params="${params%%#*}"
    local congestion=$(echo "$params" | grep -oP 'congestion_control=\K[^&]+' || echo "bbr")
    local alpn=$(echo "$params" | grep -oP 'alpn=\K[^&]+' || echo "h3")

    cat <<EOF
  - name: "$name"
    type: tuic
    server: $host
    port: $port
    uuid: $uuid
    password: "$password"
    alpn: [$alpn]
    disable-sni: false
    reduce-rtt: true
    congestion-controller: $congestion
    skip-cert-verify: true
EOF
}

generate_clash_config() {
    local jh_file=$1
    [ ! -f "$jh_file" ] && return 1

    cat <<'EOF'
# Clash 配置文件
# 由 argosbx.sh 自动生成

port: 7890
socks-port: 7891
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090

dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
  fallback:
    - 8.8.8.8
    - 1.1.1.1

proxies:
EOF

    local proxy_names=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in
            vmess://*)
                generate_clash_vmess_proxy "$line"
                decode_vmess_link "$line"
                proxy_names+=("${vm_ps:-VMess}")
                ;;
            vless://*)
                generate_clash_vless_proxy "$line"
                decode_vless_link "$line"
                proxy_names+=("${vl_name:-VLESS}")
                ;;
            ss://*)
                generate_clash_ss_proxy "$line"
                proxy_names+=("${line##*#}")
                ;;
            hysteria2://*)
                generate_clash_hysteria2_proxy "$line"
                proxy_names+=("${line##*#}")
                ;;
            tuic://*)
                generate_clash_tuic_proxy "$line"
                proxy_names+=("${line##*#}")
                ;;
        esac
    done < "$jh_file"

    cat <<EOF

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
EOF

    for name in "${proxy_names[@]}"; do
        echo "      - \"$name\""
    done

    cat <<EOF
      - DIRECT

  - name: "AUTO"
    type: url-test
    proxies:
EOF

    for name in "${proxy_names[@]}"; do
        echo "      - \"$name\""
    done

    cat <<'EOF'
    url: 'http://www.gstatic.com/generate_204'
    interval: 300

rules:
  - DOMAIN-SUFFIX,google.com,PROXY
  - DOMAIN-KEYWORD,google,PROXY
  - DOMAIN,google.com,PROXY
  - DOMAIN-SUFFIX,youtube.com,PROXY
  - DOMAIN-SUFFIX,github.com,PROXY
  - DOMAIN-SUFFIX,githubusercontent.com,PROXY
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
EOF
}

save_subscription_files() {
    local jh_file=$1
    local output_dir="${2:-$HOME/agsbx}"

    if [ ! -f "$jh_file" ]; then
        echo "错误: 节点文件 $jh_file 不存在"
        return 1
    fi

    mkdir -p "$output_dir"

    echo "正在生成 V2ray 订阅..."
    generate_v2ray_subscription "$jh_file" > "$output_dir/v2ray_sub.txt"
    if [ $? -eq 0 ]; then
        echo "✓ V2ray 订阅已保存: $output_dir/v2ray_sub.txt"
    else
        echo "✗ V2ray 订阅生成失败"
        return 1
    fi

    echo "正在生成 Clash 配置..."
    generate_clash_config "$jh_file" > "$output_dir/clash.yaml"
    if [ $? -eq 0 ]; then
        echo "✓ Clash 配置已保存: $output_dir/clash.yaml"
    else
        echo "✗ Clash 配置生成失败"
        return 1
    fi

    echo ""
    echo "订阅文件生成完成！"
    echo ""
    echo "V2ray 订阅内容（base64）:"
    echo "  文件: $output_dir/v2ray_sub.txt"
    echo "  使用: 复制文件内容到 V2ray 客户端订阅地址"
    echo ""
    echo "Clash 配置文件:"
    echo "  文件: $output_dir/clash.yaml"
    echo "  使用: 复制到 Clash 配置目录或导入客户端"
    echo ""

    return 0
}

if [ "$1" = "del" ]; then
cleandel
rm -rf "$HOME/agsbx" "$HOME/agsb"
echo "卸载完成"
echo "欢迎继续使用甬哥侃侃侃ygkkk的Argosbx一键无交互小钢炮脚本💣" && sleep 2
echo
showmode
exit
elif [ "$1" = "sub" ]; then
# 生成订阅文件
if [ ! -f "$HOME/agsbx/jh.txt" ]; then
    echo "错误: 节点文件不存在，请先运行脚本安装配置"
    exit 1
fi
save_subscription_files "$HOME/agsbx/jh.txt" "$HOME/agsbx"
exit
elif [ "$1" = "rep" ]; then
cleandel
rm -rf "$HOME/agsbx"/{sb.json,xr.json,sbargoym.log,sbargotoken.log,argo.log,argoport.log,cdnym,name}
echo "Argosbx重置协议完成，开始更新相关协议变量……" && sleep 2
echo
elif [ "$1" = "list" ]; then
cip
exit
elif [ "$1" = "upx" ]; then
check_system_compatibility || {
    log_error "系统兼容性检查失败"
    exit 1
}
for P in /proc/[0-9]*; do [ -L "$P/exe" ] || continue; TARGET=$(readlink -f "$P/exe" 2>/dev/null) || continue; case "$TARGET" in *"/agsbx/x"*) kill "$(basename "$P")" 2>/dev/null ;; esac; done
kill -15 $(pgrep -f 'agsbx/x' 2>/dev/null) >/dev/null 2>&1
upxray && xrestart && echo "Xray内核更新完成" && sleep 2 && cip
exit
elif [ "$1" = "ups" ]; then
check_system_compatibility || {
    log_error "系统兼容性检查失败"
    exit 1
}
for P in /proc/[0-9]*; do [ -L "$P/exe" ] || continue; TARGET=$(readlink -f "$P/exe" 2>/dev/null) || continue; case "$TARGET" in *"/agsbx/s"*) kill "$(basename "$P")" 2>/dev/null ;; esac; done
kill -15 $(pgrep -f 'agsbx/s' 2>/dev/null) >/dev/null 2>&1
upsingbox && sbrestart && echo "Sing-box内核更新完成" && sleep 2 && cip
exit
elif [ "$1" = "res" ]; then
for P in /proc/[0-9]*; do
[ -L "$P/exe" ] || continue
TARGET=$(readlink -f "$P/exe" 2>/dev/null) || continue
case "$TARGET" in
*"/agsbx/s"*)
kill "$(basename "$P")" 2>/dev/null
sbrestart
;;
*"/agsbx/x"*)
kill "$(basename "$P")" 2>/dev/null
xrestart
;;
*"/agsbx/c"*)
kill "$(basename "$P")" 2>/dev/null
kill -15 $(pgrep -f 'agsbx/c' 2>/dev/null) >/dev/null 2>&1
if pidof systemd >/dev/null 2>&1; then
systemctl restart argo >/dev/null 2>&1
elif command -v rc-service >/dev/null 2>&1; then
rc-service argo restart >/dev/null 2>&1
else
if [ -e "$HOME/agsbx/sbargotoken.log" ]; then
if ! pidof systemd >/dev/null 2>&1 && ! command -v rc-service >/dev/null 2>&1; then
nohup $HOME/agsbx/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token $(cat $HOME/agsbx/sbargotoken.log 2>/dev/null) >/dev/null 2>&1 &
fi
else
nohup $HOME/agsbx/cloudflared tunnel --url http://localhost:$(cat $HOME/agsbx/argoport.log 2>/dev/null) --edge-ip-version auto --no-autoupdate --protocol http2 > $HOME/agsbx/argo.log 2>&1 &
fi
fi
;;
esac
done
sleep 5 && echo "重启完成" && sleep 3 && cip
exit
fi
if ! find /proc/*/exe -type l 2>/dev/null | grep -E '/proc/[0-9]+/exe' | xargs -r readlink 2>/dev/null | grep -Eq 'agsbx/(s|x)' && ! pgrep -f 'agsbx/(s|x)' >/dev/null 2>&1; then
for P in /proc/[0-9]*; do if [ -L "$P/exe" ]; then TARGET=$(readlink -f "$P/exe" 2>/dev/null); if echo "$TARGET" | grep -qE '/agsbx/c|/agsbx/s|/agsbx/x'; then PID=$(basename "$P"); kill "$PID" 2>/dev/null && echo "Killed $PID ($TARGET)" || echo "Could not kill $PID ($TARGET)"; fi; fi; done
kill -15 $(pgrep -f 'agsbx/s' 2>/dev/null) $(pgrep -f 'agsbx/c' 2>/dev/null) $(pgrep -f 'agsbx/x' 2>/dev/null) >/dev/null 2>&1
if [ -z "$( (command -v curl >/dev/null 2>&1 && curl -s4m5 -k "$v46url" 2>/dev/null) || (command -v wget >/dev/null 2>&1 && timeout 3 wget -4 -qO- --tries=2 "$v46url" 2>/dev/null) )" ]; then
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1" > /etc/resolv.conf
fi
if [ -n "$( (command -v curl >/dev/null 2>&1 && curl -s6m5 -k "$v46url" 2>/dev/null) || (command -v wget >/dev/null 2>&1 && timeout 3 wget -6 -qO- --tries=2 "$v46url" 2>/dev/null) )" ]; then
sendip="2606:4700:d0::a29f:c001"
xendip="[2606:4700:d0::a29f:c001]"
else
sendip="162.159.192.1"
xendip="162.159.192.1"
fi

# 检查系统兼容性并设置 CPU 架构
check_system_compatibility || {
    log_error "系统兼容性检查失败"
    exit 1
}

echo "VPS系统：$op"
echo "CPU架构：$cpu"
echo "Argosbx脚本未安装，开始安装…………" && sleep 1
if [ -n "$oap" ]; then
setenforce 0 >/dev/null 2>&1
iptables -P INPUT ACCEPT >/dev/null 2>&1
iptables -P FORWARD ACCEPT >/dev/null 2>&1
iptables -P OUTPUT ACCEPT >/dev/null 2>&1
iptables -F >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
echo
echo "iptables执行开放所有端口"
fi
ins
cip
echo
else
echo "Argosbx脚本已安装"
echo
argosbxstatus
echo
echo "相关快捷方式如下："
showmode
exit
fi
