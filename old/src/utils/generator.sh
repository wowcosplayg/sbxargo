#!/bin/bash

################################################################################
# 文件名: generator.sh
# 功能: 数据生成工具 - UUID、密钥对生成
# 依赖: /proc/sys/kernel/random/uuid, $is_core_bin
################################################################################

################################################################################
# 函数名: get_uuid
# 功能: 生成一个随机 UUID
# 参数: 无
# 返回: 设置全局变量 $tmp_uuid
# 说明: 从 Linux 内核随机数生成器获取 UUID
# 示例:
#   get_uuid
#   echo "生成的 UUID: $tmp_uuid"
################################################################################
get_uuid() {
    tmp_uuid=$(cat /proc/sys/kernel/random/uuid)
}

################################################################################
# 函数名: get_pbk
# 功能: 生成 VLESS Reality 密钥对 (公钥和私钥)
# 参数: 无
# 返回:
#   设置全局变量 $is_public_key - 公钥
#   设置全局变量 $is_private_key - 私钥
# 依赖: $is_core_bin (sing-box 可执行文件路径)
# 说明:
#   - 使用 sing-box generate reality-keypair 命令
#   - 输出格式: PrivateKey: xxx\nPublicKey: yyy
# 示例:
#   get_pbk
#   echo "公钥: $is_public_key"
#   echo "私钥: $is_private_key"
################################################################################
get_pbk() {
    # 生成密钥对,提取冒号后的值
    is_tmp_pbk=($($is_core_bin generate reality-keypair | sed 's/.*://'))
    # 第一个是私钥,第二个是公钥
    is_private_key=${is_tmp_pbk[0]}
    is_public_key=${is_tmp_pbk[1]}
}

################################################################################
# 函数名: generate_random_string
# 功能: 生成指定长度的随机字符串
# 参数:
#   $1 - 字符串长度 (默认 16)
# 返回: 输出随机字符串
# 说明: 使用 /dev/urandom 和 base64 生成
# 示例:
#   random_str=$(generate_random_string 32)
#   echo "随机字符串: $random_str"
################################################################################
generate_random_string() {
    local length=${1:-16}
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $length | head -n 1
}

################################################################################
# 函数名: generate_password
# 功能: 生成随机密码 (用于 Shadowsocks 2022)
# 参数:
#   $1 - 加密方法 (用于确定密钥长度)
# 返回: 输出 base64 编码的密码
# 说明:
#   - aes-128-gcm: 16 字节
#   - aes-256-gcm: 32 字节
# 示例:
#   password=$(generate_password "2022-blake3-aes-256-gcm")
################################################################################
generate_password() {
    local method=$1
    local key_length=32

    # 根据加密方法确定密钥长度
    if [[ $method =~ 128 ]]; then
        key_length=16
    elif [[ $method =~ 256 ]]; then
        key_length=32
    fi

    # 生成随机字节并 base64 编码
    openssl rand -base64 $key_length
}
