#!/bin/bash

################################################################################
# 文件名: shadowsocks.sh
# 功能: Shadowsocks 协议配置生成和管理
# 依赖: protocols/common.sh, utils/generator.sh
# 支持:
#   - Shadowsocks (传统加密)
#   - Shadowsocks 2022 (新标准)
################################################################################

################################################################################
# 函数名: generate_shadowsocks_inbound
# 功能: 生成 Shadowsocks 入站配置 JSON
# 参数:
#   $1 - 密码
#   $2 - 端口
#   $3 - 加密方法
# 返回: 输出 JSON 配置
################################################################################
generate_shadowsocks_inbound() {
    local password=$1
    local port=$2
    local method=$3

    cat <<EOF
{
  "type": "shadowsocks",
  "tag": "ss-in",
  "listen": "::",
  "listen_port": $port,
  "method": "$method",
  "password": "$password"
}
EOF
}

################################################################################
# 函数名: generate_shadowsocks_url
# 功能: 生成 Shadowsocks 分享链接
# 参数:
#   $1 - 加密方法
#   $2 - 密码
#   $3 - 地址
#   $4 - 端口
# 返回: 输出 ss:// URL
# 格式: ss://base64(method:password)@host:port#remark
################################################################################
generate_shadowsocks_url() {
    local method=$1
    local password=$2
    local addr=$3
    local port=$4

    local userinfo=$(echo -n "${method}:${password}" | base64 -w 0)
    echo "ss://${userinfo}@${addr}:${port}#233boy-ss-${addr}"
}

################################################################################
# 函数名: generate_ss2022_password
# 功能: 生成 Shadowsocks 2022 密码
# 参数: $1 - 加密方法
# 返回: 输出 base64 编码的密码
################################################################################
generate_ss2022_password() {
    local method=$1
    generate_password "$method"
}

################################################################################
# 函数名: get_shadowsocks_change_options
# 功能: 获取可修改的配置项
# 返回: 0=协议 1=端口 4=密码 6=加密方式
################################################################################
get_shadowsocks_change_options() {
    echo "0 1 4 6"
}
