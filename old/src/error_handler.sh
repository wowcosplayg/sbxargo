#!/bin/bash

# 统一错误处理模块
# 提供标准化的错误处理、日志记录和调试功能
# 版本: 1.0
# 日期: 2025-12-31

# 错误级别定义
readonly ERROR_LEVEL_DEBUG=0
readonly ERROR_LEVEL_INFO=1
readonly ERROR_LEVEL_WARN=2
readonly ERROR_LEVEL_ERROR=3
readonly ERROR_LEVEL_FATAL=4

# 当前错误级别（默认 INFO）
ERROR_LOG_LEVEL=${ERROR_LOG_LEVEL:-$ERROR_LEVEL_INFO}

# 错误日志文件
ERROR_LOG_FILE="${ERROR_LOG_FILE:-/var/log/sing-box/error.log}"

# 是否启用调试模式
DEBUG_MODE=${DEBUG_MODE:-false}

# 错误栈数组
declare -a ERROR_STACK=()

# 错误计数器
ERROR_COUNT=0
WARN_COUNT=0

# 启用错误追踪
enable_error_tracking() {
    set -eE
    trap 'error_trap_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR
    trap 'exit_trap_handler $?' EXIT
}

# 禁用错误追踪
disable_error_tracking() {
    set +eE
    trap - ERR EXIT
}

# ERR 陷阱处理器
error_trap_handler() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_cmd=$4
    local func_stack=$5

    # 记录到错误栈
    local error_msg="错误码=${exit_code} | 行号=${line_no} | 命令=${last_cmd} | 调用栈=${func_stack}"
    ERROR_STACK+=("$error_msg")
    ERROR_COUNT=$((ERROR_COUNT + 1))

    # 记录错误日志
    log_error "捕获到错误: $error_msg"

    # 如果是 debug 模式，打印详细信息
    if [ "$DEBUG_MODE" = true ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "错误调试信息:" >&2
        echo "  退出码: $exit_code" >&2
        echo "  行号: $line_no" >&2
        echo "  BASH 行号: $bash_lineno" >&2
        echo "  命令: $last_cmd" >&2
        echo "  函数调用栈: $func_stack" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    fi
}

# EXIT 陷阱处理器
exit_trap_handler() {
    local exit_code=$1

    if [ $exit_code -ne 0 ]; then
        log_error "脚本异常退出，退出码: $exit_code"

        # 如果有错误栈，打印最后几个错误
        if [ ${#ERROR_STACK[@]} -gt 0 ]; then
            log_error "最近的错误:"
            local start_idx=$((${#ERROR_STACK[@]} - 3))
            [ $start_idx -lt 0 ] && start_idx=0

            for ((i=start_idx; i<${#ERROR_STACK[@]}; i++)); do
                log_error "  [$((i+1))] ${ERROR_STACK[$i]}"
            done
        fi
    fi
}

# 日志记录函数
log_message() {
    local level=$1
    local level_name=$2
    local message="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 检查日志级别
    if [ $level -lt $ERROR_LOG_LEVEL ]; then
        return 0
    fi

    # 格式化日志消息
    local log_msg="[$timestamp] [$level_name] $message"

    # 输出到日志文件
    if [ -n "$ERROR_LOG_FILE" ]; then
        local log_dir=$(dirname "$ERROR_LOG_FILE")
        mkdir -p "$log_dir" 2>/dev/null
        echo "$log_msg" >> "$ERROR_LOG_FILE" 2>/dev/null
    fi

    # 根据级别输出到控制台
    case $level in
        $ERROR_LEVEL_DEBUG)
            [ "$DEBUG_MODE" = true ] && echo -e "\033[0;36m$log_msg\033[0m" >&2
            ;;
        $ERROR_LEVEL_INFO)
            echo "$log_msg"
            ;;
        $ERROR_LEVEL_WARN)
            echo -e "\033[1;33m$log_msg\033[0m" >&2
            WARN_COUNT=$((WARN_COUNT + 1))
            ;;
        $ERROR_LEVEL_ERROR)
            echo -e "\033[0;31m$log_msg\033[0m" >&2
            ERROR_COUNT=$((ERROR_COUNT + 1))
            ;;
        $ERROR_LEVEL_FATAL)
            echo -e "\033[1;31m$log_msg\033[0m" >&2
            ERROR_COUNT=$((ERROR_COUNT + 1))
            ;;
    esac
}

# 各级别日志函数
log_debug() {
    log_message $ERROR_LEVEL_DEBUG "DEBUG" "$*"
}

log_info() {
    log_message $ERROR_LEVEL_INFO "INFO" "$*"
}

log_warn() {
    log_message $ERROR_LEVEL_WARN "WARN" "$*"
}

log_error() {
    log_message $ERROR_LEVEL_ERROR "ERROR" "$*"
}

log_fatal() {
    log_message $ERROR_LEVEL_FATAL "FATAL" "$*"
}

# 标准化的错误退出函数
die() {
    local exit_code=${2:-1}
    log_fatal "$1"
    exit $exit_code
}

# 标准化的错误函数（不退出）
error() {
    log_error "$*"
    return 1
}

# 标准化的警告函数
warn() {
    log_warn "$*"
}

# 标准化的信息函数
info() {
    log_info "$*"
}

# 标准化的调试函数
debug() {
    log_debug "$*"
}

# 检查命令是否成功
check_success() {
    local cmd="$1"
    local error_msg="${2:-命令执行失败: $cmd}"

    if ! eval "$cmd" 2>/dev/null; then
        error "$error_msg"
        return 1
    fi
    return 0
}

# 安全执行命令（失败时记录但不退出）
safe_exec() {
    local cmd="$1"
    local error_msg="${2:-}"

    debug "执行命令: $cmd"

    if ! eval "$cmd" 2>&1; then
        if [ -n "$error_msg" ]; then
            warn "$error_msg"
        else
            warn "命令执行失败: $cmd"
        fi
        return 1
    fi
    return 0
}

# 必须成功的命令（失败时退出）
must_exec() {
    local cmd="$1"
    local error_msg="${2:-关键命令执行失败: $cmd}"

    debug "执行关键命令: $cmd"

    if ! eval "$cmd" 2>&1; then
        die "$error_msg" 1
    fi
}

# 打印错误栈
print_error_stack() {
    if [ ${#ERROR_STACK[@]} -eq 0 ]; then
        echo "错误栈为空"
        return 0
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "错误栈 (共 ${#ERROR_STACK[@]} 个错误):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local idx=1
    for error_entry in "${ERROR_STACK[@]}"; do
        echo "[$idx] $error_entry"
        idx=$((idx + 1))
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 清空错误栈
clear_error_stack() {
    ERROR_STACK=()
    ERROR_COUNT=0
    WARN_COUNT=0
    info "错误栈已清空"
}

# 获取错误统计
get_error_stats() {
    echo "错误统计:"
    echo "  错误数: $ERROR_COUNT"
    echo "  警告数: $WARN_COUNT"
    echo "  错误栈大小: ${#ERROR_STACK[@]}"
}

# 验证必需的环境
require_env() {
    local var_name="$1"
    local error_msg="${2:-缺少必需的环境变量: $var_name}"

    if [ -z "${!var_name}" ]; then
        die "$error_msg" 1
    fi
}

# 验证必需的命令
require_command() {
    local cmd="$1"
    local error_msg="${2:-缺少必需的命令: $cmd}"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        die "$error_msg" 1
    fi
}

# 验证必需的文件
require_file() {
    local file="$1"
    local error_msg="${2:-缺少必需的文件: $file}"

    if [ ! -f "$file" ]; then
        die "$error_msg" 1
    fi
}

# 验证必需的目录
require_dir() {
    local dir="$1"
    local error_msg="${2:-缺少必需的目录: $dir}"

    if [ ! -d "$dir" ]; then
        die "$error_msg" 1
    fi
}

# 尝试执行并捕获错误
try() {
    local cmd="$1"
    local on_error="${2:-}"

    if ! eval "$cmd" 2>&1; then
        if [ -n "$on_error" ]; then
            eval "$on_error"
        fi
        return 1
    fi
    return 0
}

# 重试执行命令
retry() {
    local max_attempts=${1:-3}
    local delay=${2:-5}
    local cmd="$3"
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        info "尝试执行 (第 $attempt/$max_attempts 次): $cmd"

        if eval "$cmd" 2>&1; then
            info "执行成功"
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            warn "执行失败，${delay}秒后重试..."
            sleep $delay
        fi

        attempt=$((attempt + 1))
    done

    error "执行失败，已达到最大重试次数 ($max_attempts)"
    return 1
}

# 设置调试模式
set_debug_mode() {
    DEBUG_MODE=true
    ERROR_LOG_LEVEL=$ERROR_LEVEL_DEBUG
    info "调试模式已启用"
}

# 设置日志级别
set_log_level() {
    local level="${1:-INFO}"

    case ${level^^} in
        DEBUG)
            ERROR_LOG_LEVEL=$ERROR_LEVEL_DEBUG
            ;;
        INFO)
            ERROR_LOG_LEVEL=$ERROR_LEVEL_INFO
            ;;
        WARN|WARNING)
            ERROR_LOG_LEVEL=$ERROR_LEVEL_WARN
            ;;
        ERROR)
            ERROR_LOG_LEVEL=$ERROR_LEVEL_ERROR
            ;;
        FATAL)
            ERROR_LOG_LEVEL=$ERROR_LEVEL_FATAL
            ;;
        *)
            warn "未知的日志级别: $level，使用默认级别 INFO"
            ERROR_LOG_LEVEL=$ERROR_LEVEL_INFO
            ;;
    esac

    info "日志级别设置为: $level"
}

# 检查错误并提供建议
check_and_suggest() {
    local condition="$1"
    local error_msg="$2"
    local suggestion="$3"

    if ! eval "$condition" 2>/dev/null; then
        error "$error_msg"
        if [ -n "$suggestion" ]; then
            info "建议: $suggestion"
        fi
        return 1
    fi
    return 0
}

# 断言函数
assert() {
    local condition="$1"
    local error_msg="${2:-断言失败: $condition}"

    if ! eval "$condition" 2>/dev/null; then
        die "$error_msg" 1
    fi
}

# 兼容旧的函数名（保持向后兼容）
err() {
    die "$*" 1
}

msg() {
    info "$*"
}

# 初始化错误处理（可选，在脚本开始时调用）
init_error_handling() {
    local log_file="${1:-}"
    local log_level="${2:-INFO}"

    # 设置日志文件
    if [ -n "$log_file" ]; then
        ERROR_LOG_FILE="$log_file"
    fi

    # 设置日志级别
    set_log_level "$log_level"

    # 启用错误追踪
    enable_error_tracking

    info "错误处理模块已初始化"
    info "日志文件: $ERROR_LOG_FILE"
    info "日志级别: $log_level"
}

# 导出函数供其他脚本使用
export -f log_debug log_info log_warn log_error log_fatal
export -f die error warn info debug
export -f check_success safe_exec must_exec
export -f print_error_stack clear_error_stack get_error_stats
export -f require_env require_command require_file require_dir
export -f try retry set_debug_mode set_log_level
export -f check_and_suggest assert
export -f err msg
export -f init_error_handling enable_error_tracking disable_error_tracking
