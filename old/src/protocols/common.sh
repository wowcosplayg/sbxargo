#!/bin/bash

################################################################################
# 文件名: common.sh
# 功能: 协议层通用函数 - 所有协议共享的辅助函数
# 依赖: 无
################################################################################

################################################################################
# 函数名: get_protocol_type
# 功能: 从协议名称中提取基础协议类型
# 参数: $1 - 协议全名 (如 "VMess-WS-TLS")
# 返回: 输出基础协议类型 (如 "vmess")
# 示例:
#   type=$(get_protocol_type "VMess-WS-TLS")  # 返回 "vmess"
#   type=$(get_protocol_type "VLESS-REALITY")  # 返回 "vless"
################################################################################
get_protocol_type() {
    local protocol_full=$1
    echo "${protocol_full%%-*}" | tr '[:upper:]' '[:lower:]'
}

################################################################################
# 函数名: get_network_type
# 功能: 从协议名称中提取传输协议类型
# 参数: $1 - 协议全名 (如 "VMess-WS-TLS")
# 返回: 输出传输类型 (如 "ws")
# 说明:
#   - VMess-WS-TLS → ws
#   - VLESS-H2-TLS → h2
#   - Trojan → trojan
# 示例:
#   net=$(get_network_type "VMess-WS-TLS")  # 返回 "ws"
################################################################################
get_network_type() {
    local protocol_full=$1

    # 提取中间部分作为网络类型
    if [[ $protocol_full =~ - ]]; then
        local parts=(${protocol_full//-/ })
        # 第二部分是网络类型
        echo "${parts[1]}" | tr '[:upper:]' '[:lower:]'
    else
        # 单一协议名,返回自身
        echo "${protocol_full}" | tr '[:upper:]' '[:lower:]'
    fi
}

################################################################################
# 函数名: has_tls
# 功能: 判断协议是否使用 TLS
# 参数: $1 - 协议全名
# 返回: 0 表示使用 TLS, 1 表示不使用
# 示例:
#   has_tls "VMess-WS-TLS" && echo "使用 TLS"
################################################################################
has_tls() {
    local protocol_full=$1
    [[ $protocol_full =~ -TLS$ || $protocol_full =~ REALITY$ ]]
}

################################################################################
# 函数名: generate_transport_config
# 功能: 生成传输层配置 JSON 片段
# 参数:
#   $1 - 传输类型 (ws, h2, tcp, quic, http, httpupgrade)
#   $2 - 路径 (可选,用于 ws/h2/httpupgrade)
#   $3 - 主机名 (可选,用于 TLS)
# 返回: 输出 JSON 配置
# 示例:
#   transport=$(generate_transport_config "ws" "/path" "example.com")
################################################################################
generate_transport_config() {
    local net_type=$1
    local path=$2
    local host=$3

    case $net_type in
    ws)
        # WebSocket 传输
        if [[ $path ]]; then
            echo "{type:\"ws\",path:\"$path\",headers:{Host:\"$host\"}}"
        else
            echo "{type:\"ws\"}"
        fi
        ;;
    h2)
        # HTTP/2 传输
        if [[ $path ]]; then
            echo "{type:\"http\",path:\"$path\",host:[\"$host\"]}"
        else
            echo "{type:\"http\"}"
        fi
        ;;
    quic)
        # QUIC 传输
        echo "{type:\"quic\"}"
        ;;
    httpupgrade)
        # HTTPUpgrade 传输
        if [[ $path ]]; then
            echo "{type:\"httpupgrade\",path:\"$path\",host:\"$host\"}"
        else
            echo "{type:\"httpupgrade\"}"
        fi
        ;;
    tcp | *)
        # TCP 传输 (默认)
        echo ""
        ;;
    esac
}

################################################################################
# 函数名: generate_tls_config
# 功能: 生成 TLS 配置 JSON 片段
# 参数:
#   $1 - TLS 类型 ("tls" 或 "reality")
#   $2 - 服务器名称/SNI (可选)
#   $3 - 公钥 (Reality 专用,可选)
# 返回: 输出 JSON 配置
# 示例:
#   tls=$(generate_tls_config "tls" "example.com")
#   reality=$(generate_tls_config "reality" "www.google.com" "$public_key")
################################################################################
generate_tls_config() {
    local tls_type=$1
    local server_name=$2
    local public_key=$3

    case $tls_type in
    tls)
        # 标准 TLS 配置
        if [[ $server_name ]]; then
            echo "{enabled:true,server_name:\"$server_name\"}"
        else
            echo "{enabled:true}"
        fi
        ;;
    reality)
        # Reality 配置
        if [[ $public_key ]]; then
            echo "{enabled:true,reality:{enabled:true,public_key:\"$public_key\",short_id:\"\"},server_name:\"$server_name\"}"
        else
            echo "{enabled:true}"
        fi
        ;;
    none | *)
        # 无 TLS
        echo ""
        ;;
    esac
}

################################################################################
# 函数名: is_protocol_match
# 功能: 判断协议是否匹配指定的类型
# 参数:
#   $1 - 协议全名
#   $2 - 要匹配的基础协议 (vmess/vless/trojan/ss/hy2/tuic/socks)
# 返回: 0 表示匹配, 1 表示不匹配
# 示例:
#   is_protocol_match "VMess-WS-TLS" "vmess" && echo "是 VMess 协议"
################################################################################
is_protocol_match() {
    local protocol_full=$1
    local protocol_base=$2

    local actual_base=$(get_protocol_type "$protocol_full")
    [[ ${actual_base,,} == ${protocol_base,,} ]]
}

################################################################################
# 函数名: get_protocol_default_port
# 功能: 获取协议的默认端口号
# 参数: $1 - 协议类型
# 返回: 输出默认端口号
# 示例:
#   port=$(get_protocol_default_port "https")  # 返回 443
################################################################################
get_protocol_default_port() {
    local protocol=$1

    case ${protocol,,} in
    https | tls | reality)
        echo 443
        ;;
    http)
        echo 80
        ;;
    socks | socks5)
        echo 1080
        ;;
    *)
        # 随机端口
        shuf -i 10000-65535 -n 1
        ;;
    esac
}
