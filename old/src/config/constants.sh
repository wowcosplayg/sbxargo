#!/bin/bash

################################################################################
# 文件名: constants.sh
# 功能: 集中管理所有常量和列表定义
# 说明: 避免全局变量混乱,提供统一的常量访问
################################################################################

# 协议列表 - 支持的所有代理协议
readonly PROTOCOL_LIST=(
    TUIC
    Trojan
    Hysteria2
    VMess-WS
    VMess-TCP
    VMess-HTTP
    VMess-QUIC
    Shadowsocks
    VMess-H2-TLS
    VMess-WS-TLS
    VLESS-H2-TLS
    VLESS-WS-TLS
    Trojan-H2-TLS
    Trojan-WS-TLS
    VMess-HTTPUpgrade-TLS
    VLESS-HTTPUpgrade-TLS
    Trojan-HTTPUpgrade-TLS
    VLESS-REALITY
    VLESS-HTTP2-REALITY
    # Direct
    Socks
)

# Shadowsocks 加密方法列表
readonly SS_METHOD_LIST=(
    aes-128-gcm
    aes-256-gcm
    chacha20-ietf-poly1305
    xchacha20-ietf-poly1305
    2022-blake3-aes-128-gcm
    2022-blake3-aes-256-gcm
    2022-blake3-chacha20-poly1305
)

# 主菜单列表
readonly MAIN_MENU=(
    "添加配置"
    "更改配置"
    "查看配置"
    "删除配置"
    "运行管理"
    "更新"
    "卸载"
    "帮助"
    "其他"
    "关于"
)

# 配置信息字段列表
readonly INFO_LIST=(
    "协议 (protocol)"
    "地址 (address)"
    "端口 (port)"
    "用户ID (id)"
    "传输协议 (network)"
    "伪装类型 (type)"
    "伪装域名 (host)"
    "路径 (path)"
    "传输层安全 (TLS)"
    "应用层协议协商 (Alpn)"
    "密码 (password)"
    "加密方式 (encryption)"
    "链接 (URL)"
    "目标地址 (remote addr)"
    "目标端口 (remote port)"
    "流控 (flow)"
    "SNI (serverName)"
    "指纹 (Fingerprint)"
    "公钥 (Public key)"
    "用户名 (Username)"
    "跳过证书验证 (allowInsecure)"
    "拥塞控制算法 (congestion_control)"
)

# 可修改配置项列表
readonly CHANGE_LIST=(
    "更改协议"
    "更改端口"
    "更改域名"
    "更改路径"
    "更改密码"
    "更改 UUID"
    "更改加密方式"
    "更改目标地址"
    "更改目标端口"
    "更改密钥"
    "更改 SNI (serverName)"
    "更改伪装网站"
    "更改用户名 (Username)"
)

# 伪装域名列表 - 用于 TLS/Reality 伪装
readonly SERVERNAME_LIST=(
    www.amazon.com
    www.ebay.com
    www.paypal.com
    www.cloudflare.com
    dash.cloudflare.com
    aws.amazon.com
)

################################################################################
# 随机默认值生成
# 说明: 每次加载时生成随机默认值,用于快速配置
################################################################################

# 随机选择 Shadowsocks 2022 加密方法 (仅从索引 4-6,即 ss2022 系列)
is_random_ss_method=${SS_METHOD_LIST[$(shuf -i 4-6 -n1)]}

# 从预设列表中随机选择一个伪装域名
is_random_servername=${SERVERNAME_LIST[$(shuf -i 0-$((${#SERVERNAME_LIST[@]} - 1)) -n1)]}

################################################################################
# 向后兼容性支持
# 说明: 提供小写变量名,兼容旧代码
################################################################################

protocol_list=("${PROTOCOL_LIST[@]}")
ss_method_list=("${SS_METHOD_LIST[@]}")
mainmenu=("${MAIN_MENU[@]}")
info_list=("${INFO_LIST[@]}")
change_list=("${CHANGE_LIST[@]}")
servername_list=("${SERVERNAME_LIST[@]}")
