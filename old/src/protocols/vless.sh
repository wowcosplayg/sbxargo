#!/bin/bash

################################################################################
# 文件名: vless.sh
# 功能: VLESS 协议配置生成和管理
# 依赖: protocols/common.sh, utils/generator.sh
# 支持:
#   - VLESS-WS-TLS
#   - VLESS-H2-TLS
#   - VLESS-HTTPUpgrade-TLS
#   - VLESS-REALITY
#   - VLESS-HTTP2-REALITY
################################################################################

################################################################################
# 函数名: generate_vless_inbound
# 功能: 生成 VLESS 入站配置 JSON
# 参数:
#   $1 - UUID
#   $2 - 端口
#   $3 - 传输类型 (ws/h2/httpupgrade/tcp)
#   $4 - TLS 类型 (tls/reality/none)
#   $5 - 域名/SNI (可选)
#   $6 - 路径 (可选)
#   $7 - 流控 (可选, reality 使用)
#   $8 - Reality 公钥 (可选)
# 返回: 输出 JSON 配置
# 说明:
#   - VLESS 不使用加密 (encryption: none)
#   - Reality 模式支持 xtls-rprx-vision 流控
#   - TLS 模式需要域名和路径
################################################################################
generate_vless_inbound() {
    local uuid=$1
    local port=$2
    local net_type=$3
    local tls_type=$4
    local server_name=$5
    local path=$6
    local flow=$7
    local public_key=$8

    # 基础用户配置
    local user_config="uuid:\"$uuid\""
    [[ $flow ]] && user_config="$user_config,flow:\"$flow\""

    # 传输层配置
    local transport_config=""
    if [[ $net_type != "tcp" ]]; then
        transport_config=",transport:$(generate_transport_config "$net_type" "$path" "$server_name")"
    fi

    # TLS 配置
    local tls_config=""
    if [[ $tls_type == "tls" ]]; then
        tls_config=",tls:$(generate_tls_config "tls" "$server_name")"
    elif [[ $tls_type == "reality" ]]; then
        tls_config=",tls:$(generate_tls_config "reality" "$server_name" "$public_key")"
    fi

    # 生成完整配置
    cat <<EOF
{
  "type": "vless",
  "tag": "vless-in",
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
# 函数名: generate_vless_url
# 功能: 生成 VLESS 分享链接
# 参数:
#   $1 - UUID
#   $2 - 地址
#   $3 - 端口
#   $4 - 传输类型
#   $5 - TLS 类型
#   $6 - 服务器名称
#   $7 - 路径 (可选)
#   $8 - 流控 (可选)
#   $9 - Reality 公钥 (可选)
# 返回: 输出 vless:// URL
# 格式: vless://uuid@host:port?参数#备注
################################################################################
generate_vless_url() {
    local uuid=$1
    local addr=$2
    local port=$3
    local net_type=$4
    local tls_type=$5
    local server_name=$6
    local path=$7
    local flow=$8
    local public_key=$9

    local url="vless://$uuid@$addr:$port?"

    # 加密方式 (VLESS 固定为 none)
    url="${url}encryption=none"

    # 传输类型
    url="${url}&type=$net_type"

    # TLS 安全选项
    if [[ $tls_type == "tls" ]]; then
        url="${url}&security=tls&sni=$server_name"
    elif [[ $tls_type == "reality" ]]; then
        url="${url}&security=reality&sni=$server_name"
        [[ $public_key ]] && url="${url}&pbk=$public_key"
        [[ $flow ]] && url="${url}&flow=$flow"
        url="${url}&fp=chrome"
    fi

    # 路径和主机
    if [[ $path ]]; then
        url="${url}&path=$path"
        [[ $server_name ]] && url="${url}&host=$server_name"
    fi

    # 备注
    url="${url}#233boy-${net_type}-${addr}"

    echo "$url"
}

################################################################################
# 函数名: get_vless_change_options
# 功能: 获取 VLESS 协议可修改的配置项索引
# 参数: $1 - 网络类型
# 返回: 输出可修改项索引 (空格分隔)
# 说明:
#   索引对应 change_list:
#   0=协议 1=端口 2=域名 3=路径 5=UUID 9=SNI 10=伪装网站
################################################################################
get_vless_change_options() {
    local net_type=$1

    case $net_type in
    ws | h2 | httpupgrade)
        # WebSocket/HTTP2/HTTPUpgrade with TLS
        echo "0 1 2 3 5"
        ;;
    reality)
        # Reality 模式
        echo "0 1 5 9 10"
        ;;
    *)
        # 其他模式
        echo "0 1 5"
        ;;
    esac
}

################################################################################
# 函数名: get_vless_info_fields
# 功能: 获取 VLESS 协议信息展示字段索引
# 参数: $1 - 网络类型
# 返回: 输出信息字段索引 (空格分隔)
# 说明:
#   索引对应 info_list:
#   0=协议 1=地址 2=端口 3=UUID 4=网络 6=域名 7=路径 8=TLS
#   15=流控 16=SNI 17=指纹 18=公钥
################################################################################
get_vless_info_fields() {
    local net_type=$1

    case $net_type in
    ws | h2 | httpupgrade)
        # 使用 TLS 的传输
        echo "0 1 2 3 4 6 7 8"
        ;;
    reality)
        # Reality 模式
        echo "0 1 2 3 15 4 8 16 17 18"
        ;;
    *)
        # 基础模式
        echo "0 1 2 3 4"
        ;;
    esac
}

################################################################################
# 函数名: validate_vless_config
# 功能: 验证 VLESS 配置参数
# 参数:
#   $1 - UUID
#   $2 - 端口
#   $3 - 传输类型
# 返回: 0 表示有效, 1 表示无效
################################################################################
validate_vless_config() {
    local uuid=$1
    local port=$2
    local net_type=$3

    # 验证 UUID
    validate_uuid "$uuid" || {
        err "UUID 格式无效: $uuid"
        return 1
    }

    # 验证端口
    validate_port "$port" || {
        err "端口无效: $port"
        return 1
    }

    # 验证传输类型
    case $net_type in
    ws | h2 | tcp | quic | httpupgrade)
        return 0
        ;;
    *)
        err "不支持的传输类型: $net_type"
        return 1
        ;;
    esac
}
