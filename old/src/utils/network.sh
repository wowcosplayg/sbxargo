#!/bin/bash

################################################################################
# 文件名: network.sh
# 功能: 网络工具函数 - IP获取、端口检测
# 依赖: init.sh 的 _wget, err 函数
################################################################################

# IP 获取源列表 - 多源容灾,优先级从高到低
readonly IP_SOURCES=(
    "https://one.one.one.one/cdn-cgi/trace|grep ip=|cut -d= -f2"
    "https://ifconfig.me"
    "https://api.ipify.org"
    "https://ip.sb"
    "https://ipinfo.io/ip"
    "https://icanhazip.com"
)

################################################################################
# 函数名: get_ip
# 功能: 从多个公共服务获取服务器的公网 IP 地址
# 参数: 无
# 返回: 设置全局变量 $ip
# 依赖: curl (_wget)
# 说明:
#   - 优先获取 IPv4,失败后尝试 IPv6
#   - 支持多源容灾,任一源成功即返回
#   - 验证 IP 格式有效性
# 示例: get_ip && echo "IP: $ip"
################################################################################
get_ip() {
    # 如果已有 IP 或不需要获取,直接返回
    [[ $ip || $is_no_auto_tls || $is_gen || $is_dont_get_ip ]] && return

    local timeout=5
    local max_retries=2

    # 先尝试获取 IPv4
    for source_cmd in "${IP_SOURCES[@]}"; do
        local url="${source_cmd%%|*}"
        local filter="${source_cmd#*|}"

        # 如果有过滤器,使用管道处理
        if [ "$filter" != "$source_cmd" ]; then
            export ip=$(_wget -4 -qO- --timeout=$timeout "$url" 2>/dev/null | eval "$filter" 2>/dev/null | head -1 | tr -d '[:space:]')
        else
            export ip=$(_wget -4 -qO- --timeout=$timeout "$url" 2>/dev/null | head -1 | tr -d '[:space:]')
        fi

        # 验证 IPv4 格式
        if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            # 验证是否是有效的 IPv4 (每个八位组 ≤ 255)
            local valid=true
            IFS='.' read -ra ADDR <<< "$ip"
            for octet in "${ADDR[@]}"; do
                if [ $octet -gt 255 ]; then
                    valid=false
                    break
                fi
            done

            if [ "$valid" = true ]; then
                return 0
            fi
        fi

        # 清空无效 IP
        export ip=
    done

    # 如果 IPv4 失败,尝试 IPv6
    [[ ! $ip ]] && {
        for source_cmd in "${IP_SOURCES[@]}"; do
            local url="${source_cmd%%|*}"
            local filter="${source_cmd#*|}"

            if [ "$filter" != "$source_cmd" ]; then
                export ip=$(_wget -6 -qO- --timeout=$timeout "$url" 2>/dev/null | eval "$filter" 2>/dev/null | head -1 | tr -d '[:space:]')
            else
                export ip=$(_wget -6 -qO- --timeout=$timeout "$url" 2>/dev/null | head -1 | tr -d '[:space:]')
            fi

            # 验证 IPv6 格式 (简单验证包含冒号)
            if [[ $ip =~ : ]]; then
                return 0
            fi

            export ip=
        done
    }

    # 所有源都失败
    [[ ! $ip ]] && {
        err "获取服务器 IP 失败,已尝试所有可用源"
    }
}

################################################################################
# 函数名: get_port
# 功能: 自动获取一个未被占用的可用端口
# 参数: 无
# 返回: 设置全局变量 $tmp_port
# 说明:
#   - 端口范围: 445-65535
#   - 最多尝试 233 次
#   - 避免与当前 $port 冲突
# 示例: get_port && echo "可用端口: $tmp_port"
################################################################################
get_port() {
    is_count=0
    while :; do
        ((is_count++))
        if [[ $is_count -ge 233 ]]; then
            err "自动获取可用端口失败次数达到 233 次, 请检查端口占用情况."
        fi
        # 随机生成端口号
        tmp_port=$(shuf -i 445-65535 -n 1)
        # 检查端口未被占用且不等于当前端口
        [[ ! $(is_test port_used $tmp_port) && $tmp_port != $port ]] && break
    done
}

################################################################################
# 函数名: is_port_used
# 功能: 检测指定端口是否已被占用
# 参数: $1 - 要检测的端口号
# 返回: 如果端口被占用输出端口号,否则无输出
# 依赖: netstat 或 ss 命令
# 说明:
#   - 优先使用 netstat,不可用时使用 ss
#   - 如果两者都不可用,设置 $is_cant_test_port 标志
# 示例: is_port_used 8080 && echo "端口已占用"
################################################################################
is_port_used() {
    # 优先使用 netstat
    if [[ $(type -P netstat) ]]; then
        [[ ! $is_used_port ]] && is_used_port="$(netstat -tunlp | sed -n 's/.*:\([0-9]\+\).*/\1/p' | sort -nu)"
        echo $is_used_port | sed 's/ /\n/g' | grep ^${1}$
        return
    fi

    # 使用 ss 作为备选
    if [[ $(type -P ss) ]]; then
        [[ ! $is_used_port ]] && is_used_port="$(ss -tunlp | sed -n 's/.*:\([0-9]\+\).*/\1/p' | sort -nu)"
        echo $is_used_port | sed 's/ /\n/g' | grep ^${1}$
        return
    fi

    # 两者都不可用
    is_cant_test_port=1
    msg "$is_warn 无法检测端口是否可用."
    msg "请执行: $(_yellow "${cmd} update -y; ${cmd} install net-tools -y") 来修复此问题."
}
