#!/bin/bash

################################################################################
# 文件名: service.sh
# 功能: 系统服务管理 - systemd 服务控制
# 依赖: systemctl, utils/display.sh
################################################################################

################################################################################
# 函数名: manage
# 功能: 管理服务运行状态 (启动/停止/重启)
# 参数:
#   $1 - 操作类型 (1|start, 2|stop, 3|r|restart)
#   $2 - 服务名称 (可选, 默认 $is_core, 支持 caddy)
# 返回: 无
# 说明:
#   - 支持 sing-box 和 Caddy 服务管理
#   - 启动和重启后自动检测服务状态
#   - 失败时自动执行测试运行
# 示例:
#   manage start          # 启动 sing-box
#   manage restart caddy  # 重启 Caddy
################################################################################
manage() {
    [[ $is_dont_auto_exit ]] && return

    # 解析操作类型
    case $1 in
    1 | start)
        is_do=start
        is_do_msg=启动
        is_test_run=1
        ;;
    2 | stop)
        is_do=stop
        is_do_msg=停止
        ;;
    3 | r | restart)
        is_do=restart
        is_do_msg=重启
        is_test_run=1
        ;;
    *)
        is_do=$1
        is_do_msg=$1
        ;;
    esac

    # 解析服务名称
    case $2 in
    caddy)
        is_do_name=$2
        is_run_bin=$is_caddy_bin
        is_do_name_msg=Caddy
        ;;
    *)
        is_do_name=$is_core
        is_run_bin=$is_core_bin
        is_do_name_msg=$is_core_name
        ;;
    esac

    # 执行 systemctl 操作
    systemctl $is_do $is_do_name

    # 启动和重启后检测服务状态
    if [[ $is_test_run && ! $is_new_install ]]; then
        sleep 2

        # 检查进程是否存在
        if [[ ! $(pgrep -f $is_run_bin) ]]; then
            is_run_fail=${is_do_name_msg,,}

            if [[ ! $is_no_manage_msg ]]; then
                msg
                warn "($is_do_msg) $is_do_name_msg 失败"
                _yellow "检测到运行失败, 自动执行测试运行."
                get test-run
                _yellow "测试结束, 请按 Enter 退出."
            fi
        fi
    fi
}

################################################################################
# 函数名: get_service_status
# 功能: 获取服务状态信息
# 参数: $1 - 服务名称 (可选, 默认 $is_core)
# 返回: 输出服务状态
# 示例:
#   get_service_status
#   get_service_status caddy
################################################################################
get_service_status() {
    local service_name=${1:-$is_core}

    if systemctl is-active "$service_name" &>/dev/null; then
        echo "运行中"
    elif systemctl is-enabled "$service_name" &>/dev/null; then
        echo "已启用但未运行"
    else
        echo "未运行"
    fi
}

################################################################################
# 函数名: show_service_info
# 功能: 显示服务详细信息
# 参数: $1 - 服务名称 (可选, 默认 $is_core)
# 返回: 无
# 说明: 显示状态、PID、内存使用、启动时间等
################################################################################
show_service_info() {
    local service_name=${1:-$is_core}

    msg "\n------------- $service_name 服务信息 -------------"

    # 服务状态
    local status=$(get_service_status "$service_name")
    msg "服务状态: $status"

    # 如果服务运行中,显示详细信息
    if systemctl is-active "$service_name" &>/dev/null; then
        # PID
        local pid=$(systemctl show -p MainPID --value "$service_name")
        msg "进程 PID: $pid"

        # 内存使用
        local memory=$(systemctl show -p MemoryCurrent --value "$service_name")
        if [[ $memory && $memory != "[not set]" ]]; then
            local memory_mb=$((memory / 1024 / 1024))
            msg "内存使用: ${memory_mb}MB"
        fi

        # 启动时间
        local start_time=$(systemctl show -p ActiveEnterTimestamp --value "$service_name")
        msg "启动时间: $start_time"

        # 运行时长
        local uptime=$(systemctl show -p ActiveEnterTimestampMonotonic --value "$service_name")
        if [[ $uptime && $uptime != "0" ]]; then
            local current=$(cat /proc/uptime | cut -d' ' -f1 | cut -d. -f1)
            local running_sec=$((current - uptime / 1000000))
            local days=$((running_sec / 86400))
            local hours=$(((running_sec % 86400) / 3600))
            local mins=$(((running_sec % 3600) / 60))
            msg "运行时长: ${days}天 ${hours}时 ${mins}分"
        fi
    fi

    # 是否开机自启
    if systemctl is-enabled "$service_name" &>/dev/null; then
        msg "开机自启: 已启用"
    else
        msg "开机自启: 未启用"
    fi

    msg "---------------------------------------------"
}

################################################################################
# 函数名: enable_service
# 功能: 启用服务开机自启
# 参数: $1 - 服务名称
# 返回: 0 表示成功, 1 表示失败
################################################################################
enable_service() {
    local service_name=$1

    if systemctl enable "$service_name"; then
        log_info "$service_name 开机自启已启用"
        return 0
    else
        log_error "$service_name 开机自启启用失败"
        return 1
    fi
}

################################################################################
# 函数名: disable_service
# 功能: 禁用服务开机自启
# 参数: $1 - 服务名称
# 返回: 0 表示成功, 1 表示失败
################################################################################
disable_service() {
    local service_name=$1

    if systemctl disable "$service_name"; then
        log_info "$service_name 开机自启已禁用"
        return 0
    else
        log_error "$service_name 开机自启禁用失败"
        return 1
    fi
}

################################################################################
# 函数名: reload_service
# 功能: 重新加载服务配置 (不中断连接)
# 参数: $1 - 服务名称
# 返回: 0 表示成功, 1 表示失败
# 说明: 适用于支持 reload 的服务如 Caddy
################################################################################
reload_service() {
    local service_name=$1

    if systemctl reload "$service_name" 2>/dev/null; then
        log_info "$service_name 配置已重新加载"
        return 0
    else
        log_warn "$service_name 不支持 reload, 使用 restart 代替"
        systemctl restart "$service_name"
    fi
}

################################################################################
# 函数名: watch_service_logs
# 功能: 实时查看服务日志
# 参数:
#   $1 - 服务名称
#   $2 - 行数 (可选, 默认 50)
# 返回: 无
# 说明: 使用 journalctl -f 实时跟踪日志
################################################################################
watch_service_logs() {
    local service_name=$1
    local lines=${2:-50}

    msg "实时查看 $service_name 日志 (Ctrl+C 退出):"
    msg "----------------------------------------"
    journalctl -u "$service_name" -n "$lines" -f
}

################################################################################
# 函数名: check_service_health
# 功能: 健康检查 - 检测服务是否正常运行
# 参数: $1 - 服务名称
# 返回: 0 表示健康, 1 表示异常
# 说明:
#   - 检查服务状态
#   - 检查进程是否存在
#   - 检查端口是否监听 (如果适用)
################################################################################
check_service_health() {
    local service_name=$1
    local errors=0

    # 检查服务状态
    if ! systemctl is-active "$service_name" &>/dev/null; then
        log_error "服务未运行: $service_name"
        ((errors++))
    fi

    # 检查进程
    local bin_path=""
    case $service_name in
    "$is_core")
        bin_path=$is_core_bin
        ;;
    caddy)
        bin_path=$is_caddy_bin
        ;;
    esac

    if [[ $bin_path && ! $(pgrep -f "$bin_path") ]]; then
        log_error "进程不存在: $bin_path"
        ((errors++))
    fi

    # 返回结果
    if [[ $errors -eq 0 ]]; then
        log_info "服务健康检查通过 ✓"
        return 0
    else
        log_error "服务健康检查失败 ($errors 个问题)"
        return 1
    fi
}
