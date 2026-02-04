#!/bin/bash

################################################################################
# 文件名: display.sh
# 功能: 配置信息展示 - 显示配置详情、生成URL/二维码
# 依赖: utils/display.sh (msg, msg_ul, footer_msg)
################################################################################

################################################################################
# 函数名: info
# 功能: 显示配置信息并生成分享链接
# 参数: $1 - 配置文件名 (可选)
# 返回: 无
# 说明:
#   - 根据协议类型显示不同的配置信息
#   - 自动生成分享 URL (vmess://, vless://, trojan:// 等)
#   - 显示可修改的配置项
#   - 支持多种传输协议 (ws, tcp, h2, quic, reality 等)
# 全局变量:
#   输入: $is_protocol, $net, $host, $port, $uuid, $password
#   输出: $is_url, $is_can_change, $is_info_show, $is_info_str
################################################################################
info() {
    # 如果未设置协议,从配置文件读取
    if [[ ! $is_protocol ]]; then
        get info $1
    fi

    # 设置显示颜色
    is_color=44

    case $net in
    ws | tcp | h2 | quic | http*)
        # WebSocket, TCP, HTTP/2, QUIC 传输
        if [[ $host ]]; then
            # 使用 TLS 和域名的配置
            is_color=45
            is_can_change=(0 1 2 3 5)
            is_info_show=(0 1 2 3 4 6 7 8)

            if [[ $is_protocol == 'vmess' ]]; then
                # VMess 协议 URL 生成
                is_vmess_url=$(jq -c '{v:2,ps:'"\"233boy-$net-$host\""',add:'"\"$is_addr\""',port:'"\"$is_https_port\""',id:'"\"$uuid\""',aid:"0",net:'"\"$net\""',host:'"\"$host\""',path:'"\"$path\""',tls:'"\"tls\""'}' <<<{})
                is_url=vmess://$(echo -n $is_vmess_url | base64 -w 0)
            else
                if [[ $is_protocol == "trojan" ]]; then
                    # Trojan 使用 password 而不是 uuid
                    uuid=$password
                    is_can_change=(0 1 2 3 4)
                    is_info_show=(0 1 2 10 4 6 7 8)
                fi
                # VLESS/Trojan URL 生成
                is_url="$is_protocol://$uuid@$host:$is_https_port?encryption=none&security=tls&type=$net&host=$host&path=$path#233boy-$net-$host"
            fi

            [[ $is_caddy ]] && is_can_change+=(11)
            is_info_str=($is_protocol $is_addr $is_https_port $uuid $net $host $path 'tls')
        else
            # 不使用 TLS 的配置
            is_type=none
            is_can_change=(0 1 5)
            is_info_show=(0 1 2 3 4)
            is_info_str=($is_protocol $is_addr $port $uuid $net)

            # TCP with HTTP header
            if [[ $net == "http" ]]; then
                net=tcp
                is_type=http
                is_tcp_http=1
                is_info_show+=(5)
                is_info_str=(${is_info_str[@]/http/tcp http})
            fi

            # QUIC 特殊处理
            if [[ $net == "quic" ]]; then
                is_insecure=1
                is_info_show+=(8 9 20)
                is_info_str+=(tls h3 true)
                is_quic_add=",tls:\"tls\",alpn:\"h3\""
            fi

            # VMess URL 生成
            is_vmess_url=$(jq -c "{v:2,ps:\"233boy-${net}-$is_addr\",add:\"$is_addr\",port:\"$port\",id:\"$uuid\",aid:\"0\",net:\"$net\",type:\"$is_type\"$is_quic_add}" <<<{})
            is_url=vmess://$(echo -n $is_vmess_url | base64 -w 0)
        fi
        ;;
    ss)
        # Shadowsocks 配置
        is_can_change=(0 1 4 6)
        is_info_show=(0 1 2 10 11)
        is_url="ss://$(echo -n ${ss_method}:${ss_password} | base64 -w 0)@${is_addr}:${port}#233boy-$net-${is_addr}"
        is_info_str=($is_protocol $is_addr $port $ss_password $ss_method)
        ;;
    trojan)
        # Trojan 独立配置
        is_insecure=1
        is_can_change=(0 1 4)
        is_info_show=(0 1 2 10 4 8 20)
        is_url="$is_protocol://$password@$is_addr:$port?type=tcp&security=tls&allowInsecure=1#233boy-$net-$is_addr"
        is_info_str=($is_protocol $is_addr $port $password tcp tls true)
        ;;
    hy*)
        # Hysteria2 配置
        is_can_change=(0 1 4)
        is_info_show=(0 1 2 10 8 9 20)
        is_url="$is_protocol://$password@$is_addr:$port?alpn=h3&insecure=1#233boy-$net-$is_addr"
        is_info_str=($is_protocol $is_addr $port $password tls h3 true)
        ;;
    tuic)
        # TUIC 配置
        is_insecure=1
        is_can_change=(0 1 4 5)
        is_info_show=(0 1 2 3 10 8 9 20 21)
        is_url="$is_protocol://$uuid:$password@$is_addr:$port?alpn=h3&allow_insecure=1&congestion_control=bbr#233boy-$net-$is_addr"
        is_info_str=($is_protocol $is_addr $port $uuid $password tls h3 true bbr)
        ;;
    reality)
        # VLESS Reality 配置
        is_color=41
        is_can_change=(0 1 5 9 10)
        is_info_show=(0 1 2 3 15 4 8 16 17 18)
        is_flow=xtls-rprx-vision
        is_net_type=tcp

        # Reality HTTP/2 模式
        if [[ $net_type =~ "http" || ${is_new_protocol,,} =~ "http" ]]; then
            is_flow=
            is_net_type=h2
            is_info_show=(${is_info_show[@]/15/})
        fi

        is_info_str=($is_protocol $is_addr $port $uuid $is_flow $is_net_type reality $is_servername chrome $is_public_key)
        is_url="$is_protocol://$uuid@$is_addr:$port?encryption=none&security=reality&flow=$is_flow&type=$is_net_type&sni=$is_servername&pbk=$is_public_key&fp=chrome#233boy-$net-$is_addr"
        ;;
    direct)
        # Direct/门接入 配置
        is_can_change=(0 1 7 8)
        is_info_show=(0 1 2 13 14)
        is_info_str=($is_protocol $is_addr $port $door_addr $door_port)
        ;;
    socks)
        # Socks5 配置
        is_can_change=(0 1 12 4)
        is_info_show=(0 1 2 19 10)
        is_info_str=($is_protocol $is_addr $port $is_socks_user $is_socks_pass)
        is_url="socks://$(echo -n ${is_socks_user}:${is_socks_pass} | base64 -w 0)@${is_addr}:${port}#233boy-$net-${is_addr}"
        ;;
    esac

    # 如果设置了不显示信息标志,直接返回
    [[ $is_dont_show_info || $is_gen || $is_dont_auto_exit ]] && return

    # 显示配置信息
    msg "-------------- $is_config_name -------------"
    for ((i = 0; i < ${#is_info_show[@]}; i++)); do
        a=${info_list[${is_info_show[$i]}]}
        # 根据字段长度调整制表符
        if [[ ${#a} -eq 11 || ${#a} -ge 13 ]]; then
            tt='\t'
        else
            tt='\t\t'
        fi
        msg "$a $tt= \e[${is_color}m${is_info_str[$i]}\e[0m"
    done

    # 首次安装提示
    if [[ $is_new_install ]]; then
        warn "首次安装请查看脚本帮助文档: $(msg_ul https://233boy.com/$is_core/$is_core-script/)"
    fi

    # 显示分享 URL
    if [[ $is_url ]]; then
        msg "------------- ${info_list[12]} -------------"
        msg "\e[4;${is_color}m${is_url}\e[0m"
        # 安全提示
        if [[ $is_insecure ]]; then
            warn "某些客户端如(V2rayN 等)导入URL需手动将: 跳过证书验证(allowInsecure) 设置为 true, 或打开: 允许不安全的连接"
        fi
    fi

    # no-auto-tls 模式提示
    if [[ $is_no_auto_tls ]]; then
        msg "------------- no-auto-tls INFO -------------"
        msg "端口(port): $port"
        msg "路径(path): $path"
        msg "\e[41m帮助(help)\e[0m: $(msg_ul https://233boy.com/$is_core/no-auto-tls/)"
    fi

    footer_msg
}

################################################################################
# 函数名: url_qr
# 功能: 显示分享 URL 或生成二维码
# 参数:
#   $1 - 显示模式 ('url' 或 'qr')
#   $2 - 配置文件名 (可选)
# 返回: 无
# 说明:
#   - url 模式: 显示分享链接
#   - qr 模式: 生成二维码 (需要 qrencode)
#   - 自动调用 info() 获取配置信息
# 示例:
#   url_qr url config1.json     # 显示 URL
#   url_qr qr config1.json      # 显示二维码
################################################################################
url_qr() {
    is_dont_show_info=1
    info $2

    if [[ $is_url ]]; then
        if [[ $1 == 'url' ]]; then
            # 显示 URL 链接
            msg "\n------------- $is_config_name & URL 链接 -------------"
            msg "\n\e[${is_color}m${is_url}\e[0m\n"
            footer_msg
        else
            # 显示二维码
            link="https://233boy.github.io/tools/qr.html#${is_url}"
            msg "\n------------- $is_config_name & QR code 二维码 -------------"
            msg

            if [[ $(type -P qrencode) ]]; then
                # 使用 qrencode 生成终端二维码
                qrencode -t ANSI "${is_url}"
            else
                # qrencode 未安装,提示用户安装
                msg "请安装 qrencode: $(_green "$cmd update -y; $cmd install qrencode -y")"
            fi

            msg
            msg "如果无法正常显示或识别, 请使用下面的链接来生成二维码:"
            msg "\n\e[4;${is_color}m${link}\e[0m\n"
            footer_msg
        fi
    else
        # 配置不支持生成 URL
        if [[ $1 == 'url' ]]; then
            err "($is_config_name) 无法生成 URL 链接."
        else
            err "($is_config_name) 无法生成 QR code 二维码."
        fi
    fi
}
