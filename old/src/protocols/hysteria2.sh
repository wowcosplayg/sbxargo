#!/bin/bash

################################################################################
# 文件名: hysteria2.sh
# 功能: Hysteria2 协议配置生成和管理
# 依赖: protocols/common.sh
################################################################################

################################################################################
# 函数名: generate_hysteria2_inbound
# 功能: 生成 Hysteria2 入站配置 JSON
# 参数:
#   $1 - 密码
#   $2 - 端口
# 返回: 输出 JSON 配置
################################################################################
generate_hysteria2_inbound() {
    local password=$1
    local port=$2

    cat <<EOF
{
  "type": "hysteria2",
  "tag": "hy2-in",
  "listen": "::",
  "listen_port": $port,
  "users": [
    {
      "password": "$password"
    }
  ],
  "tls": {
    "enabled": true
  }
}
EOF
}

################################################################################
# 函数名: generate_hysteria2_url
# 功能: 生成 Hysteria2 分享链接
# 参数:
#   $1 - 密码
#   $2 - 地址
#   $3 - 端口
# 返回: 输出 hysteria2:// URL
################################################################################
generate_hysteria2_url() {
    local password=$1
    local addr=$2
    local port=$3

    echo "hysteria2://$password@$addr:$port?alpn=h3&insecure=1#233boy-hy2-$addr"
}

################################################################################
# 函数名: get_hysteria2_change_options
# 功能: 获取可修改的配置项
# 返回: 0=协议 1=端口 4=密码
################################################################################
get_hysteria2_change_options() {
    echo "0 1 4"
}
