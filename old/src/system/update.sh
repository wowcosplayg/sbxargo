#!/bin/bash

################################################################################
# 文件名: update.sh
# 功能: 更新和卸载管理 - 核心/脚本/Caddy 的更新和卸载
# 依赖: download.sh, system/service.sh
################################################################################

################################################################################
# 函数名: update
# 功能: 更新 sing-box 核心、脚本或 Caddy
# 参数:
#   $1 - 更新目标 (1|core|sing-box, 2|sh, 3|caddy)
#   $2 - 版本号 (可选, 默认最新版)
# 返回: 无
# 说明:
#   - 自动检测最新版本
#   - 支持自定义版本
#   - 更新后自动重启服务
# 示例:
#   update core          # 更新核心到最新版
#   update sh            # 更新脚本到最新版
#   update caddy v2.7.6  # 更新 Caddy 到指定版本
################################################################################
update() {
    # 解析更新目标
    case $1 in
    1 | core | $is_core)
        is_update_name=core
        is_show_name=$is_core_name
        is_run_ver=v${is_core_ver##* }
        is_update_repo=$is_core_repo
        ;;
    2 | sh)
        is_update_name=sh
        is_show_name="$is_core_name 脚本"
        is_run_ver=$is_sh_ver
        is_update_repo=$is_sh_repo
        ;;
    3 | caddy)
        [[ ! $is_caddy ]] && err "不支持更新 Caddy."
        is_update_name=caddy
        is_show_name="Caddy"
        is_run_ver=$is_caddy_ver
        is_update_repo=$is_caddy_repo
        ;;
    *)
        err "无法识别 ($1), 请使用: $is_core update [core | sh | caddy] [ver]"
        ;;
    esac

    # 处理自定义版本
    [[ $2 ]] && is_new_ver=v${2#v}

    # 检查版本是否相同
    if [[ $is_run_ver == $is_new_ver ]]; then
        msg "\n自定义版本和当前 $is_show_name 版本一样, 无需更新.\n"
        exit
    fi

    # 加载下载模块
    load download.sh

    # 获取最新版本或使用自定义版本
    if [[ $is_new_ver ]]; then
        msg "\n使用自定义版本更新 $is_show_name: $(_green $is_new_ver)\n"
    else
        get_latest_version $is_update_name

        # 检查是否已是最新版
        if [[ $is_run_ver == $latest_ver ]]; then
            msg "\n$is_show_name 当前已经是最新版本了.\n"
            exit
        fi

        msg "\n发现 $is_show_name 新版本: $(_green $latest_ver)\n"
        is_new_ver=$latest_ver
    fi

    # 执行下载和安装
    download $is_update_name $is_new_ver

    msg "更新成功, 当前 $is_show_name 版本: $(_green $is_new_ver)\n"
    msg "$(_green 请查看更新说明: https://github.com/$is_update_repo/releases/tag/$is_new_ver)\n"

    # 非脚本更新需要重启服务
    if [[ $is_update_name != 'sh' ]]; then
        manage restart $is_update_name &
    fi
}

################################################################################
# 函数名: uninstall
# 功能: 卸载 sing-box 和/或 Caddy
# 参数: 无
# 返回: 无
# 说明:
#   - 如果安装了 Caddy, 提供选项:
#     1) 仅卸载 sing-box
#     2) 卸载 sing-box 和 Caddy
#   - 自动停止并禁用服务
#   - 删除所有相关文件
#   - 清理环境变量
################################################################################
uninstall() {
    # 询问卸载选项
    if [[ $is_caddy ]]; then
        is_tmp_list=("卸载 $is_core_name" "卸载 ${is_core_name} & Caddy")
        ask list is_do_uninstall
    else
        ask string y "是否卸载 ${is_core_name}? [y]:"
    fi

    # 停止并禁用服务
    manage stop &>/dev/null
    systemctl disable $is_core &>/dev/null

    # 删除文件
    msg "\n开始卸载 $is_core_name..."

    rm -rf \
        $is_core_dir \
        $is_log_dir \
        $is_sh_bin \
        ${is_sh_bin/$is_core/sb} \
        /lib/systemd/system/$is_core.service

    # 清理环境变量
    sed -i "/$is_core/d" /root/.bashrc

    msg "$is_core_name 卸载完成"

    # 卸载 Caddy (如果用户选择)
    if [[ $REPLY == '2' ]]; then
        msg "开始卸载 Caddy..."

        manage stop caddy &>/dev/null
        systemctl disable caddy &>/dev/null

        rm -rf \
            $is_caddy_dir \
            $is_caddy_bin \
            /lib/systemd/system/caddy.service

        msg "Caddy 卸载完成"
    fi

    # 如果是重装,直接返回
    [[ $is_install_sh ]] && return

    # 显示卸载完成信息
    _green "\n卸载完成!"
    msg "脚本哪里需要完善? 请反馈"
    msg "反馈问题) $(msg_ul https://github.com/${is_sh_repo}/issues)\n"
}

################################################################################
# 函数名: check_updates
# 功能: 检查所有组件的可用更新
# 参数: 无
# 返回: 输出更新信息
# 说明: 不执行更新,仅检查和显示
################################################################################
check_updates() {
    msg "\n------------- 检查更新 -------------"

    # 加载下载模块
    load download.sh

    # 检查核心更新
    get_latest_version core
    local core_current=v${is_core_ver##* }
    msg "$is_core_name:"
    msg "  当前版本: $core_current"
    msg "  最新版本: $latest_ver"

    if [[ $core_current == $latest_ver ]]; then
        msg "  状态: $(_green 已是最新版)"
    else
        msg "  状态: $(_yellow 有新版本可用)"
        msg "  更新命令: $(_green "$is_core update core")"
    fi

    # 检查脚本更新
    get_latest_version sh
    local sh_current=$is_sh_ver
    msg "\n$is_core_name 脚本:"
    msg "  当前版本: $sh_current"
    msg "  最新版本: $latest_ver"

    if [[ $sh_current == $latest_ver ]]; then
        msg "  状态: $(_green 已是最新版)"
    else
        msg "  状态: $(_yellow 有新版本可用)"
        msg "  更新命令: $(_green "$is_core update sh")"
    fi

    # 检查 Caddy 更新 (如果已安装)
    if [[ $is_caddy ]]; then
        get_latest_version caddy
        local caddy_current=$is_caddy_ver
        msg "\nCaddy:"
        msg "  当前版本: $caddy_current"
        msg "  最新版本: $latest_ver"

        if [[ $caddy_current == $latest_ver ]]; then
            msg "  状态: $(_green 已是最新版)"
        else
            msg "  状态: $(_yellow 有新版本可用)"
            msg "  更新命令: $(_green "$is_core update caddy")"
        fi
    fi

    msg "\n-------------------------------------"
}

################################################################################
# 函数名: auto_update
# 功能: 自动更新所有组件到最新版
# 参数: 无
# 返回: 无
# 说明: 依次检查并更新 core, sh, caddy (如果已安装)
################################################################################
auto_update() {
    msg "\n自动更新所有组件..."

    # 更新核心
    msg "\n[1/3] 检查 $is_core_name 更新..."
    update core

    # 更新脚本
    msg "\n[2/3] 检查脚本更新..."
    update sh

    # 更新 Caddy (如果已安装)
    if [[ $is_caddy ]]; then
        msg "\n[3/3] 检查 Caddy 更新..."
        update caddy
    fi

    msg "\n所有组件已更新到最新版本 ✓"
}

################################################################################
# 函数名: rollback_update
# 功能: 回滚到上一个版本
# 参数: $1 - 组件名称 (core|sh|caddy)
# 返回: 0 表示成功, 1 表示失败
# 说明: 从备份恢复上一个版本的二进制文件
################################################################################
rollback_update() {
    local component=$1

    case $component in
    core)
        local bin_path=$is_core_bin
        local backup_path="${is_core_bin}.backup"
        ;;
    caddy)
        local bin_path=$is_caddy_bin
        local backup_path="${is_caddy_bin}.backup"
        ;;
    *)
        err "不支持回滚: $component"
        return 1
        ;;
    esac

    if [[ ! -f "$backup_path" ]]; then
        err "未找到备份文件: $backup_path"
        return 1
    fi

    msg "回滚 $component 到上一个版本..."

    if mv "$backup_path" "$bin_path"; then
        chmod +x "$bin_path"
        msg "回滚成功"

        # 重启服务
        manage restart $component
        return 0
    else
        err "回滚失败"
        return 1
    fi
}
