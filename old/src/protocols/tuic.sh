#!/bin/bash

################################################################################
# 文件名: tuic.sh
# 功能: TUIC 协议配置生成和管理
# 依赖: protocols/common.sh
################################################################################

################################################################################
# 函数名: generate_tuic_inbound
# 功能: 生成 TUIC 入站配置 JSON
# 参数:
#   $1 - UUID
#   $2 - 密码
#   $3 - 端口
# 返回: 输出 JSON 配置
################################################################################
generate_tuic_inbound() {
    local uuid=$1
    local password=$2
    local port=$3

    cat <<EOF
{
  "type": "tuic",
  "tag": "tuic-in",
  "listen": "::",
  "listen_port": $port,
  "users": [
    {
      "uuid": "$uuid",
      "password": "$password"
    }
  ],
  "congestion_control": "bbr",
  "tls": {
    "enabled": true,
    "alpn": ["h3"]
  }
}
EOF
}

################################################################################
# 函数名: generate_tuic_url
# 功能: 生成 TUIC 分享链接
# 参数:
#   $1 - UUID
#   $2 - 密码
#   $3 - 地址
#   $4 - 端口
# 返回: 输出 tuic:// URL
################################################################################
generate_tuic_url() {
    local uuid=$1
    local password=$2
    local addr=$3
    local port=$4

    echo "tuic://$uuid:$password@$addr:$port?alpn=h3&allow_insecure=1&congestion_control=bbr#233boy-tuic-$addr"
}

################################################################################
# 函数名: get_tuic_change_options
# 功能: 获取可修改的配置项
# 返回: 0=协议 1=端口 4=密码 5=UUID
################################################################################
get_tuic_change_options() {
    echo "0 1 4 5"
}
