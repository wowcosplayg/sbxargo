#!/bin/bash

################################################################################
# 文件名: menu.sh
# 功能: 用户交互菜单 - 输入处理、选项选择
# 依赖: utils/display.sh, utils/validator.sh, config/constants.sh
################################################################################

################################################################################
# 函数名: ask
# 功能: 通用输入处理函数 - 支持列表选择和字符串输入
# 参数:
#   $1 - 询问类型
#   $2 - 变量名 (用于 string/list 类型)
#   $3 - 附加参数 (根据类型不同)
# 返回: 设置指定的全局变量
# 支持的类型:
#   - set_ss_method: 选择 Shadowsocks 加密方式
#   - set_protocol: 选择代理协议
#   - set_change_list: 选择要修改的配置项
#   - string: 输入字符串
#   - list: 从列表中选择
#   - get_config_file: 选择配置文件
#   - mainmenu: 显示主菜单
# 示例:
#   ask set_protocol
#   ask string "port" "请输入端口:"
#   ask list "choice" "选项1 选项2" "提示信息" "输入提示"
################################################################################
ask() {
    case $1 in
    set_ss_method)
        # 选择 Shadowsocks 加密方式
        is_tmp_list=(${ss_method_list[@]})
        is_default_arg=$is_random_ss_method
        is_opt_msg="\n请选择加密方式:\n"
        is_opt_input_msg="(默认\e[92m $is_default_arg\e[0m):"
        is_ask_set=ss_method
        ;;
    set_protocol)
        # 选择代理协议
        is_tmp_list=(${protocol_list[@]})
        # 如果设置了 no_auto_tls,只显示 TLS 协议
        [[ $is_no_auto_tls ]] && {
            unset is_tmp_list
            for v in ${protocol_list[@]}; do
                [[ $(grep -i tls$ <<<$v) ]] && is_tmp_list=(${is_tmp_list[@]} $v)
            done
        }
        is_opt_msg="\n请选择协议:\n"
        is_ask_set=is_new_protocol
        ;;
    set_change_list)
        # 选择要修改的配置项
        is_tmp_list=()
        for v in ${is_can_change[@]}; do
            is_tmp_list+=("${change_list[$v]}")
        done
        is_opt_msg="\n请选择更改:\n"
        is_ask_set=is_change_str
        is_opt_input_msg=$3
        ;;
    string)
        # 输入字符串
        is_ask_set=$2
        is_opt_input_msg=$3
        ;;
    list)
        # 从列表中选择
        is_ask_set=$2
        [[ ! $is_tmp_list ]] && is_tmp_list=($3)
        is_opt_msg=$4
        is_opt_input_msg=$5
        ;;
    get_config_file)
        # 选择配置文件
        is_tmp_list=("${is_all_json[@]}")
        is_opt_msg="\n请选择配置:\n"
        is_ask_set=is_config_file
        ;;
    mainmenu)
        # 主菜单
        is_tmp_list=("${mainmenu[@]}")
        is_ask_set=is_main_pick
        is_emtpy_exit=1
        ;;
    esac

    # 显示提示信息
    msg $is_opt_msg
    [[ ! $is_opt_input_msg ]] && is_opt_input_msg="请选择 [\e[91m1-${#is_tmp_list[@]}\e[0m]:"
    [[ $is_tmp_list ]] && show_list "${is_tmp_list[@]}"

    # 循环读取用户输入,直到输入有效
    while :; do
        echo -ne $is_opt_input_msg
        read REPLY

        # 处理空输入
        [[ ! $REPLY && $is_emtpy_exit ]] && exit
        [[ ! $REPLY && $is_default_arg ]] && export $is_ask_set=$is_default_arg && break

        # 彩蛋: 特殊输入 "233" 显示隐藏信息
        [[ "$REPLY" == "${is_str}2${is_get}3${is_opt}3" && $is_ask_set == 'is_main_pick' ]] && {
            msg "\n${is_get}2${is_str}3${is_msg}3b${is_tmp}o${is_opt}y\n" && exit
        }

        # 如果是字符串输入 (无列表)
        if [[ ! $is_tmp_list ]]; then
            # 验证端口号
            [[ $(grep port <<<$is_ask_set) ]] && {
                [[ ! $(is_test port "$REPLY") ]] && {
                    msg "$is_err 请输入正确的端口, 可选(1-65535)"
                    continue
                }
                # 检查端口是否被占用 (door_port 除外)
                if [[ $(is_test port_used $REPLY) && $is_ask_set != 'door_port' ]]; then
                    msg "$is_err 无法使用 ($REPLY) 端口."
                    continue
                fi
            }

            # 验证路径格式
            [[ $(grep path <<<$is_ask_set) && ! $(is_test path "$REPLY") ]] && {
                [[ ! $tmp_uuid ]] && get_uuid
                msg "$is_err 请输入正确的路径, 例如: /$tmp_uuid"
                continue
            }

            # 验证 UUID 格式
            [[ $(grep uuid <<<$is_ask_set) && ! $(is_test uuid "$REPLY") ]] && {
                [[ ! $tmp_uuid ]] && get_uuid
                msg "$is_err 请输入正确的 UUID, 例如: $tmp_uuid"
                continue
            }

            # 确认输入 (y/n)
            [[ $(grep ^y$ <<<$is_ask_set) ]] && {
                [[ $(grep -i ^y$ <<<"$REPLY") ]] && break
                msg "请输入 (y)"
                continue
            }

            # 输入有效,设置变量并退出
            [[ $REPLY ]] && export $is_ask_set=$REPLY && msg "使用: ${!is_ask_set}" && break
        else
            # 列表选择: 验证数字并获取对应项
            [[ $(is_test number "$REPLY") ]] && is_ask_result=${is_tmp_list[$REPLY - 1]}
            [[ $is_ask_result ]] && export $is_ask_set="$is_ask_result" && msg "选择: ${!is_ask_set}" && break
        fi

        # 输入无效,提示错误
        msg "输入${is_err}"
    done

    # 清理临时变量
    unset is_opt_msg is_opt_input_msg is_tmp_list is_ask_result is_default_arg is_emtpy_exit
}

################################################################################
# 函数名: is_main_menu
# 功能: 显示主菜单并处理用户选择
# 参数: 无
# 返回: 无
# 说明:
#   - 显示脚本版本和核心状态
#   - 提供 10 个主要功能选项
#   - 根据用户选择调用相应功能
# 菜单选项:
#   1. 添加配置
#   2. 更改配置
#   3. 查看配置
#   4. 删除配置
#   5. 运行管理 (启动/停止/重启)
#   6. 更新 (核心/脚本/Caddy)
#   7. 卸载
#   8. 帮助
#   9. 其他 (BBR/日志/测试/DNS)
#   10. 关于
################################################################################
is_main_menu() {
    # 显示菜单头部
    msg "\n------------- $is_core_name script $is_sh_ver by $author -------------"
    msg "$is_core_name $is_core_ver: $is_core_status"
    msg "群组(Chat): $(msg_ul https://t.me/tg233boy)"

    is_main_start=1
    ask mainmenu

    # 根据用户选择执行相应功能
    case $REPLY in
    1)
        # 添加配置
        add
        ;;
    2)
        # 更改配置
        change
        ;;
    3)
        # 查看配置
        info
        ;;
    4)
        # 删除配置
        del
        ;;
    5)
        # 运行管理
        ask list is_do_manage "启动 停止 重启"
        manage $REPLY &
        msg "\n管理状态执行: $(_green $is_do_manage)\n"
        ;;
    6)
        # 更新选项
        is_tmp_list=("更新$is_core_name" "更新脚本")
        [[ $is_caddy ]] && is_tmp_list+=("更新Caddy")
        ask list is_do_update null "\n请选择更新:\n"
        update $REPLY
        ;;
    7)
        # 卸载
        uninstall
        ;;
    8)
        # 帮助
        msg
        load help.sh
        show_help
        ;;
    9)
        # 其他功能
        ask list is_do_other "启用BBR 查看日志 测试运行 重装脚本 设置DNS"
        case $REPLY in
        1)
            # 启用 BBR
            load bbr.sh
            _try_enable_bbr
            ;;
        2)
            # 查看日志
            load log.sh
            log_set
            ;;
        3)
            # 测试运行
            get test-run
            ;;
        4)
            # 重装脚本
            get reinstall
            ;;
        5)
            # 设置 DNS
            load dns.sh
            dns_set
            ;;
        esac
        ;;
    10)
        # 关于
        load help.sh
        about
        ;;
    esac
}
