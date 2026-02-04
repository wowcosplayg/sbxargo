#!/bin/bash

################################################################################
# 文件名: trojan.sh
# 功能: Trojan 协议配置生成和管理
# 依赖: protocols/common.sh
# 支持:
#   - Trojan (独立)
#   - Trojan-WS-TLS
#   - Trojan-H2-TLS
#   - Trojan-HTTPUpgrade-TLS
################################################################################

################################################################################
# 函数名: generate_trojan_inbound
# 功能: 生成 Trojan 入站配置 JSON
# 参数:
#   $1 - 密码
#   $2 - 端口
#   $3 - 传输类型 (tcp/ws/h2/httpupgrade)
#   $4 - TLS 类型 (tls/none)
#   $5 - 域名 (可选)
#   $6 - 路径 (可选)
# 返回: 输出 JSON 配置
################################################################################
generate_trojan_inbound() {
    local password=$1
    local port=$2
    local net_type=$3
    local tls_type=$4
    local server_name=$5
    local path=$6

    # 用户配置
    local user_config="password:\"$password\""

    # 传输层配置
    local transport_config=""
    if [[ $net_type != "tcp" ]]; then
        transport_config=",transport:$(generate_transport_config "$net_type" "$path" "$server_name")"
    fi

    # TLS 配置 (Trojan 通常需要 TLS)
    local tls_config=""
    if [[ $tls_type == "tls" ]]; then
        tls_config=",tls:$(generate_tls_config "tls" "$server_name")"
    fi

    cat <<EOF
{
  "type": "trojan",
  "tag": "trojan-in",
  "listen": "::",
  "listen_port": $port,
  "users": [
    {
      $user_config
    }
  ]$transport_config$tls_config
}
EOF
}

################################################################################
# 函数名: generate_trojan_url
# 功能: 生成 Trojan 分享链接
# 参数:
#   $1 - 密码
#   $2 - 地址
#   $3 - 端口
#   $4 - 传输类型
#   $5 - 服务器名称 (可选)
#   $6 - 路径 (可选)
# 返回: 输出 trojan:// URL
################################################################################
generate_trojan_url() {
    local password=$1
    local addr=$2
    local port=$3
    local net_type=$4
    local server_name=$5
    local path=$6

    local url="trojan://$password@$addr:$port?"
    url="${url}type=$net_type&security=tls"

    if [[ $server_name ]]; then
        url="${url}&sni=$server_name"
        [[ $path ]] && url="${url}&path=$path&host=$server_name"
    fi

    url="${url}&allowInsecure=1#233boy-$net_type-$addr"
    echo "$url"
}

################################################################################
# 函数名: get_trojan_change_options
# 功能: 获取可修改的配置项
# 返回: 0=协议 1=端口 2=域名 3=路径 4=密码
################################################################################
get_trojan_change_options() {
    local net_type=$1
    case $net_type in
    ws | h2 | httpupgrade)
        echo "0 1 2 3 4"
        ;;
    *)
        echo "0 1 4"
        ;;
    esac
}
