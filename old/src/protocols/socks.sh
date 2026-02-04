#!/bin/bash

################################################################################
# 文件名: socks.sh
# 功能: Socks5 协议配置生成和管理
# 依赖: protocols/common.sh
################################################################################

################################################################################
# 函数名: generate_socks_inbound
# 功能: 生成 Socks5 入站配置 JSON
# 参数:
#   $1 - 用户名
#   $2 - 密码
#   $3 - 端口
# 返回: 输出 JSON 配置
################################################################################
generate_socks_inbound() {
    local username=$1
    local password=$2
    local port=$3

    cat <<EOF
{
  "type": "socks",
  "tag": "socks-in",
  "listen": "::",
  "listen_port": $port,
  "users": [
    {
      "username": "$username",
      "password": "$password"
    }
  ]
}
EOF
}

################################################################################
# 函数名: generate_socks_url
# 功能: 生成 Socks5 分享链接
# 参数:
#   $1 - 用户名
#   $2 - 密码
#   $3 - 地址
#   $4 - 端口
# 返回: 输出 socks:// URL
################################################################################
generate_socks_url() {
    local username=$1
    local password=$2
    local addr=$3
    local port=$4

    local userinfo=$(echo -n "${username}:${password}" | base64 -w 0)
    echo "socks://${userinfo}@${addr}:${port}#233boy-socks-${addr}"
}

################################################################################
# 函数名: get_socks_change_options
# 功能: 获取可修改的配置项
# 返回: 0=协议 1=端口 12=用户名 4=密码
################################################################################
get_socks_change_options() {
    echo "0 1 12 4"
}
