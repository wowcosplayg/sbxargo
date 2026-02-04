#!/bin/bash

# 输入验证和过滤模块
# 提供全面的输入验证、过滤和安全检查功能
# 版本: 1.0
# 日期: 2025-12-31

# 验证端口号 (1-65535)
validate_port() {
    local port="$1"

    # 检查是否为数字
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # 检查范围
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi

    return 0
}

# 验证 IPv4 地址
validate_ipv4() {
    local ip="$1"

    # 检查格式
    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi

    # 验证每个八位组
    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ]; then
            return 1
        fi
    done

    return 0
}

# 验证 IPv6 地址
validate_ipv6() {
    local ip="$1"

    # 简单验证：包含冒号且格式合理
    if ! [[ "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
        return 1
    fi

    # 检查冒号数量（至少2个，最多7个）
    local colon_count=$(grep -o ":" <<< "$ip" | wc -l)
    if [ "$colon_count" -lt 2 ] || [ "$colon_count" -gt 7 ]; then
        return 1
    fi

    return 0
}

# 验证域名
validate_domain() {
    local domain="$1"

    # 域名长度检查
    if [ ${#domain} -gt 253 ]; then
        return 1
    fi

    # 域名格式检查
    # 允许字母、数字、连字符和点
    # 每个标签最多63字符
    # 不能以连字符开始或结束
    if ! [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        return 1
    fi

    return 0
}

# 验证 URL
validate_url() {
    local url="$1"

    # URL 格式检查（支持 http/https）
    if ! [[ "$url" =~ ^https?://[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*(/.*)?$ ]]; then
        return 1
    fi

    return 0
}

# 验证文件路径
validate_path() {
    local path="$1"
    local allow_relative="${2:-false}"

    # 不允许包含危险字符
    if [[ "$path" =~ [\'\"$\`\\] ]]; then
        return 1
    fi

    # 检查是否包含路径遍历
    if [[ "$path" =~ \.\./|\.\.\\ ]]; then
        return 1
    fi

    # 如果不允许相对路径，必须以 / 开头
    if [ "$allow_relative" != true ] && [[ ! "$path" =~ ^/ ]]; then
        return 1
    fi

    # 路径长度检查
    if [ ${#path} -gt 4096 ]; then
        return 1
    fi

    return 0
}

# 验证 UUID
validate_uuid() {
    local uuid="$1"

    # UUID 格式: 8-4-4-4-12
    if ! [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        return 1
    fi

    return 0
}

# 验证 email
validate_email() {
    local email="$1"

    # Email 基本格式检查
    if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi

    return 0
}

# 验证用户名（字母、数字、下划线、连字符）
validate_username() {
    local username="$1"
    local min_len="${2:-3}"
    local max_len="${3:-32}"

    # 长度检查
    if [ ${#username} -lt $min_len ] || [ ${#username} -gt $max_len ]; then
        return 1
    fi

    # 只允许字母、数字、下划线、连字符
    if ! [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        return 1
    fi

    # 不能以数字开头
    if [[ "$username" =~ ^[0-9] ]]; then
        return 1
    fi

    return 0
}

# 验证密码强度
validate_password() {
    local password="$1"
    local min_len="${2:-8}"

    # 长度检查
    if [ ${#password} -lt $min_len ]; then
        return 1
    fi

    # 至少包含一个数字
    if ! [[ "$password" =~ [0-9] ]]; then
        return 1
    fi

    # 至少包含一个字母
    if ! [[ "$password" =~ [a-zA-Z] ]]; then
        return 1
    fi

    return 0
}

# 验证整数
validate_integer() {
    local value="$1"
    local min="${2:-}"
    local max="${3:-}"

    # 检查是否为整数
    if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        return 1
    fi

    # 检查最小值
    if [ -n "$min" ] && [ "$value" -lt "$min" ]; then
        return 1
    fi

    # 检查最大值
    if [ -n "$max" ] && [ "$value" -gt "$max" ]; then
        return 1
    fi

    return 0
}

# 验证布尔值
validate_boolean() {
    local value="${1,,}"  # 转小写

    case "$value" in
        true|false|yes|no|1|0|on|off)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 验证 JSON 格式
validate_json() {
    local json_str="$1"

    if command -v jq >/dev/null 2>&1; then
        echo "$json_str" | jq empty 2>/dev/null
        return $?
    else
        # 简单验证：检查是否以 { 或 [ 开始和结束
        if [[ "$json_str" =~ ^\{.*\}$ ]] || [[ "$json_str" =~ ^\[.*\]$ ]]; then
            return 0
        fi
        return 1
    fi
}

# 过滤危险字符（防止命令注入）
sanitize_input() {
    local input="$1"
    local mode="${2:-strict}"

    case "$mode" in
        strict)
            # 严格模式：只保留字母、数字、下划线、连字符
            echo "$input" | tr -cd 'a-zA-Z0-9_-'
            ;;
        safe)
            # 安全模式：移除危险字符
            echo "$input" | sed 's/[;&|<>`$()\\]//g'
            ;;
        filename)
            # 文件名模式：只保留文件名安全字符
            echo "$input" | tr -cd 'a-zA-Z0-9._-'
            ;;
        path)
            # 路径模式：允许路径字符但移除遍历
            echo "$input" | sed 's/\.\.//g' | tr -cd 'a-zA-Z0-9/_.-'
            ;;
        *)
            echo "$input"
            ;;
    esac
}

# 验证并清理用户输入
validate_and_sanitize() {
    local input="$1"
    local type="$2"
    local extra_args="${3:-}"

    case "$type" in
        port)
            if validate_port "$input"; then
                echo "$input"
                return 0
            fi
            ;;
        ipv4)
            if validate_ipv4 "$input"; then
                echo "$input"
                return 0
            fi
            ;;
        ipv6)
            if validate_ipv6 "$input"; then
                echo "$input"
                return 0
            fi
            ;;
        domain)
            if validate_domain "$input"; then
                echo "$input"
                return 0
            fi
            ;;
        url)
            if validate_url "$input"; then
                echo "$input"
                return 0
            fi
            ;;
        path)
            if validate_path "$input" "$extra_args"; then
                echo "$input"
                return 0
            fi
            ;;
        uuid)
            if validate_uuid "$input"; then
                echo "$input"
                return 0
            fi
            ;;
        username)
            if validate_username "$input"; then
                echo "$input"
                return 0
            fi
            ;;
        password)
            if validate_password "$input" "$extra_args"; then
                echo "$input"
                return 0
            fi
            ;;
        integer)
            if validate_integer "$input" $extra_args; then
                echo "$input"
                return 0
            fi
            ;;
        sanitize)
            sanitize_input "$input" "$extra_args"
            return 0
            ;;
        *)
            echo "$input"
            return 1
            ;;
    esac

    return 1
}

# 安全读取用户输入
read_validated_input() {
    local prompt="$1"
    local type="$2"
    local varname="$3"
    local default="${4:-}"
    local max_attempts="${5:-3}"

    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo -n "$prompt"
        [ -n "$default" ] && echo -n " [默认: $default]"
        echo -n ": "

        local user_input
        read user_input

        # 使用默认值
        if [ -z "$user_input" ] && [ -n "$default" ]; then
            user_input="$default"
        fi

        # 验证输入
        if result=$(validate_and_sanitize "$user_input" "$type" 2>&1); then
            eval "$varname=\"$result\""
            return 0
        fi

        echo "输入无效，请重试 (尝试 $attempt/$max_attempts)"
        attempt=$((attempt + 1))
    done

    echo "错误: 达到最大尝试次数"
    return 1
}

# 检查字符串长度
check_string_length() {
    local str="$1"
    local min="${2:-0}"
    local max="${3:-999999}"

    local len=${#str}
    if [ $len -lt $min ] || [ $len -gt $max ]; then
        return 1
    fi
    return 0
}

# 检查是否在白名单中
check_whitelist() {
    local value="$1"
    shift
    local whitelist=("$@")

    for item in "${whitelist[@]}"; do
        if [ "$value" = "$item" ]; then
            return 0
        fi
    done

    return 1
}

# 检查是否在黑名单中
check_blacklist() {
    local value="$1"
    shift
    local blacklist=("$@")

    for item in "${blacklist[@]}"; do
        if [ "$value" = "$item" ]; then
            return 1
        fi
    done

    return 0
}

# 验证文件类型（通过扩展名）
validate_file_extension() {
    local filename="$1"
    shift
    local allowed_extensions=("$@")

    local ext="${filename##*.}"
    ext="${ext,,}"  # 转小写

    for allowed in "${allowed_extensions[@]}"; do
        if [ "$ext" = "${allowed,,}" ]; then
            return 0
        fi
    done

    return 1
}

# 编码特殊字符（URL 编码）
url_encode() {
    local string="$1"
    local length="${#string}"
    local encoded=""

    for (( i = 0; i < length; i++ )); do
        local c="${string:i:1}"
        case $c in
            [a-zA-Z0-9.~_-])
                encoded+="$c"
                ;;
            *)
                encoded+=$(printf '%%%02X' "'$c")
                ;;
        esac
    done

    echo "$encoded"
}

# HTML 转义
html_escape() {
    local string="$1"

    string="${string//&/&amp;}"
    string="${string//</&lt;}"
    string="${string//>/&gt;}"
    string="${string//\"/&quot;}"
    string="${string//\'/&#39;}"

    echo "$string"
}

# 导出函数供其他脚本使用
export -f validate_port validate_ipv4 validate_ipv6 validate_domain validate_url
export -f validate_path validate_uuid validate_email validate_username validate_password
export -f validate_integer validate_boolean validate_json
export -f sanitize_input validate_and_sanitize read_validated_input
export -f check_string_length check_whitelist check_blacklist validate_file_extension
export -f url_encode html_escape
