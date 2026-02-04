#!/bin/bash

################################################################################
# 文件名: loader.sh
# 功能: 模块加载器 - 按需加载所有子模块
# 依赖: 所有模块文件
# 说明: 在 init.sh 或 core.sh 中调用此文件,完成所有模块的加载
################################################################################

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

################################################################################
# 函数名: load_module
# 功能: 加载单个模块文件
# 参数: $1 - 模块相对路径 (相对于 src 目录)
# 返回: 0 表示成功, 1 表示失败
# 说明:
#   - 检查文件是否存在
#   - 使用 source 加载模块
#   - 记录加载日志 (如果启用调试模式)
################################################################################
load_module() {
    local module_path="$SCRIPT_DIR/$1"

    if [[ ! -f "$module_path" ]]; then
        # 如果模块文件不存在,记录警告但不中止
        [[ $DEBUG ]] && echo "[WARN] 模块文件不存在: $module_path"
        return 1
    fi

    # 加载模块
    source "$module_path"

    # 调试日志
    [[ $VERBOSE ]] && echo "[LOAD] $1"

    return 0
}

################################################################################
# 函数名: load_all_modules
# 功能: 按顺序加载所有模块
# 参数: 无
# 返回: 无
# 说明: 严格按照依赖层级加载,避免循环依赖
################################################################################
load_all_modules() {
    # Layer 0: 常量定义 (最基础,无依赖)
    load_module "config/constants.sh"

    # Layer 1: 工具层 (无相互依赖)
    load_module "utils/display.sh"
    load_module "utils/validator.sh"
    load_module "utils/generator.sh"
    load_module "utils/network.sh"

    # Layer 2: UI 层 (依赖 utils)
    load_module "ui/menu.sh"
    load_module "ui/display.sh"

    # Layer 3: 协议层基础
    load_module "protocols/common.sh"

    # Layer 4: 配置层
    load_module "config/validator.sh"

    # Layer 5: 系统层
    load_module "system/service.sh"
    load_module "system/update.sh"
}

################################################################################
# 函数名: load_protocol
# 功能: 按需加载指定协议模块
# 参数: $1 - 协议名称 (vmess/vless/trojan/ss/hy2/tuic/socks)
# 返回: 0 表示成功, 1 表示失败
# 说明: 延迟加载,仅在需要时加载协议模块
################################################################################
load_protocol() {
    local protocol=${1,,}  # 转小写

    case $protocol in
    vmess*)
        load_module "protocols/vmess.sh"
        ;;
    vless*)
        load_module "protocols/vless.sh"
        ;;
    trojan*)
        load_module "protocols/trojan.sh"
        ;;
    shadowsocks | ss*)
        load_module "protocols/shadowsocks.sh"
        ;;
    hysteria2 | hy2 | hy*)
        load_module "protocols/hysteria2.sh"
        ;;
    tuic*)
        load_module "protocols/tuic.sh"
        ;;
    socks*)
        load_module "protocols/socks.sh"
        ;;
    *)
        [[ $DEBUG ]] && echo "[WARN] 未知协议: $protocol"
        return 1
        ;;
    esac

    return 0
}

################################################################################
# 函数名: load_all_protocols
# 功能: 加载所有协议模块
# 参数: 无
# 返回: 无
# 说明: 一次性加载所有协议 (适用于需要完整功能的场景)
################################################################################
load_all_protocols() {
    load_module "protocols/vmess.sh"
    load_module "protocols/vless.sh"
    load_module "protocols/trojan.sh"
    load_module "protocols/shadowsocks.sh"
    load_module "protocols/hysteria2.sh"
    load_module "protocols/tuic.sh"
    load_module "protocols/socks.sh"
}

################################################################################
# 自动执行: 加载核心模块
# 说明: 当 loader.sh 被 source 时,自动加载核心模块
################################################################################
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # 被 source 调用,执行加载
    load_all_modules

    # 如果设置了 LOAD_ALL_PROTOCOLS,加载所有协议
    if [[ $LOAD_ALL_PROTOCOLS ]]; then
        load_all_protocols
    fi
fi

################################################################################
# 使用示例:
#
# 1. 在 init.sh 或 core.sh 中加载所有核心模块:
#    source "$is_sh_dir/src/loader.sh"
#
# 2. 按需加载协议模块:
#    load_protocol "vless"
#    load_protocol "vmess"
#
# 3. 加载所有协议 (一次性):
#    LOAD_ALL_PROTOCOLS=1 source "$is_sh_dir/src/loader.sh"
#    # 或
#    source "$is_sh_dir/src/loader.sh"
#    load_all_protocols
#
# 4. 启用调试模式:
#    DEBUG=1 VERBOSE=1 source "$is_sh_dir/src/loader.sh"
################################################################################
