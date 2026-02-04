#!/bin/bash

################################################################################
# 文件名: vmess.sh
# 功能: VMess 协议配置生成和管理
# 依赖: protocols/common.sh, utils/generator.sh
# 支持:
#   - VMess-TCP
#   - VMess-WS
#   - VMess-WS-TLS
#   - VMess-H2-TLS
#   - VMess-HTTP
#   - VMess-QUIC
#   - VMess-HTTPUpgrade-TLS
################################################################################

################################################################################
# 函数名: generate_vmess_inbound
# 功能: 生成 VMess 入站配置 JSON
# 参数:
#   $1 - UUID
#   $2 - 端口
#   $3 - 传输类型 (ws/h2/tcp/quic/http/httpupgrade)
#   $4 - TLS 类型 (tls/none)
#   $5 - 域名 (可选, TLS 模式使用)
#   $6 - 路径 (可选, ws/h2/httpupgrade 使用)
# 返回: 输出 JSON 配置
# 说明:
#   - VMess 使用 auto 加密方式
#   - alterId 固定为 0 (AEAD 加密)
#   - QUIC 模式自动启用 TLS
################################################################################
generate_vmess_inbound() {
    local uuid=$1
    local port=$2
    local net_type=$3
    local tls_type=$4
    local server_name=$5
    local path=$6

    # 用户配置
    local user_config="uuid:\"$uuid\",alterId:0"

    # 传输层配置
    local transport_config=""
    case $net_type in
    ws)
        # WebSocket 传输
        if [[ $path ]]; then
            transport_config=",transport:{type:\"ws\",path:\"$path\",headers:{Host:\"$server_name\"}}"
        else
            transport_config=",transport:{type:\"ws\"}"
        fi
        ;;
    h2)
        # HTTP/2 传输
        if [[ $path ]]; then
            transport_config=",transport:{type:\"http\",path:\"$path\",host:[\"$server_name\"]}"
        else
            transport_config=",transport:{type:\"http\"}"
        fi
        ;;
    quic)
        # QUIC 传输 (自动启用 TLS)
        transport_config=",transport:{type:\"quic\"}"
        tls_type="tls"
        ;;
    http)
        # TCP with HTTP header
        transport_config=",transport:{type:\"tcp\",headers:{type:\"http\"}}"
        ;;
    httpupgrade)
        # HTTPUpgrade 传输
        if [[ $path ]]; then
            transport_config=",transport:{type:\"httpupgrade\",path:\"$path\",host:\"$server_name\"}"
        else
            transport_config=",transport:{type:\"httpupgrade\"}"
        fi
        ;;
    esac

    # TLS 配置
    local tls_config=""
    if [[ $tls_type == "tls" ]]; then
        tls_config=",tls:$(generate_tls_config "tls" "$server_name")"
    fi

    # 生成完整配置
    cat <<EOF
{
  "type": "vmess",
  "tag": "vmess-in",
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
# 函数名: generate_vmess_url
# 功能: 生成 VMess 分享链接 (V2RayN 格式)
# 参数:
#   $1 - UUID
#   $2 - 地址
#   $3 - 端口
#   $4 - 传输类型
#   $5 - TLS 类型
#   $6 - 服务器名称 (可选)
#   $7 - 路径 (可选)
# 返回: 输出 vmess:// URL
# 格式: vmess://base64(json)
# JSON 格式: V2RayN 标准
################################################################################
generate_vmess_url() {
    local uuid=$1
    local addr=$2
    local port=$3
    local net_type=$4
    local tls_type=$5
    local server_name=$6
    local path=$7

    # 构建 JSON 对象
    local vmess_json="{"
    vmess_json="${vmess_json}\"v\":\"2\","                    # 版本
    vmess_json="${vmess_json}\"ps\":\"233boy-$net_type-$addr\","  # 备注
    vmess_json="${vmess_json}\"add\":\"$addr\","             # 地址
    vmess_json="${vmess_json}\"port\":\"$port\","            # 端口
    vmess_json="${vmess_json}\"id\":\"$uuid\","              # UUID
    vmess_json="${vmess_json}\"aid\":\"0\","                 # alterId
    vmess_json="${vmess_json}\"net\":\"$net_type\""          # 网络类型

    # 伪装类型
    if [[ $net_type == "http" ]]; then
        vmess_json="${vmess_json},\"type\":\"http\""
    else
        vmess_json="${vmess_json},\"type\":\"none\""
    fi

    # TLS 设置
    if [[ $tls_type == "tls" ]]; then
        vmess_json="${vmess_json},\"tls\":\"tls\""
        [[ $server_name ]] && vmess_json="${vmess_json},\"sni\":\"$server_name\""
    fi

    # QUIC 特殊处理
    if [[ $net_type == "quic" ]]; then
        vmess_json="${vmess_json},\"tls\":\"tls\",\"alpn\":\"h3\""
    fi

    # WebSocket/HTTP2/HTTPUpgrade 路径和主机
    if [[ $net_type =~ ^(ws|h2|httpupgrade)$ && $server_name ]]; then
        vmess_json="${vmess_json},\"host\":\"$server_name\""
    fi
    if [[ $path ]]; then
        vmess_json="${vmess_json},\"path\":\"$path\""
    fi

    vmess_json="${vmess_json}}"

    # Base64 编码并生成 URL
    local encoded=$(echo -n "$vmess_json" | base64 -w 0)
    echo "vmess://$encoded"
}

################################################################################
# 函数名: get_vmess_change_options
# 功能: 获取 VMess 协议可修改的配置项索引
# 参数: $1 - 网络类型
# 返回: 输出可修改项索引 (空格分隔)
# 说明:
#   0=协议 1=端口 2=域名 3=路径 5=UUID
################################################################################
get_vmess_change_options() {
    local net_type=$1

    case $net_type in
    ws | h2 | httpupgrade)
        # 使用域名和路径的传输
        echo "0 1 2 3 5"
        ;;
    *)
        # 基础传输
        echo "0 1 5"
        ;;
    esac
}

################################################################################
# 函数名: get_vmess_info_fields
# 功能: 获取 VMess 协议信息展示字段索引
# 参数: $1 - 网络类型
# 返回: 输出信息字段索引 (空格分隔)
# 说明:
#   0=协议 1=地址 2=端口 3=UUID 4=网络 5=类型
#   6=域名 7=路径 8=TLS 9=ALPN 20=allowInsecure
################################################################################
get_vmess_info_fields() {
    local net_type=$1

    case $net_type in
    ws | h2 | httpupgrade)
        # TLS 传输
        echo "0 1 2 3 4 6 7 8"
        ;;
    http)
        # TCP with HTTP header
        echo "0 1 2 3 4 5"
        ;;
    quic)
        # QUIC 传输
        echo "0 1 2 3 4 8 9 20"
        ;;
    *)
        # 基础传输
        echo "0 1 2 3 4"
        ;;
    esac
}

################################################################################
# 函数名: validate_vmess_config
# 功能: 验证 VMess 配置参数
# 参数:
#   $1 - UUID
#   $2 - 端口
#   $3 - 传输类型
# 返回: 0 表示有效, 1 表示无效
################################################################################
validate_vmess_config() {
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
    tcp | ws | h2 | quic | http | httpupgrade)
        return 0
        ;;
    *)
        err "不支持的传输类型: $net_type"
        return 1
        ;;
    esac
}
