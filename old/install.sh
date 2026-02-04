#!/bin/bash
# ==============================================================================
# Argosbx 全能配置安装脚本
# ==============================================================================
# 使用说明：
# 1. 修改下方变量为你想要的值（保留默认值也可以直接使用）
# 2. 注释掉（在行首加 #）你不需要的协议
# 3. 运行脚本：bash install.sh
# ==============================================================================

# --- 核心基础配置 ---
# 自定义 UUID (建议使用 uuidgen 生成)，留空则自动生成
export uuid=""
# 自定义节点名称前缀 (例如: MyNode)
export name="MyNode"

# --- 协议开关 (推荐组合) ---
# 设置为 'yes' 使用随机端口，或者直接填写 '端口号' (如 8443)

# [推荐] VLESS Reality (TCP + Vision 流控) - 抗封锁最强
export vlpt=yes
# [推荐] Hysteria2 (UDP 高速) - 适合网络环境差的情况
export hypt=yes

# --- 其他协议可选配置 (按需开启) ---

# [可选] VMess WS (通用性好，支持 CDN)
export vmpt=8080
# [可选] VLESS WS (通用性好，支持 CDN)
# export vwpt=8080

# [可选] Tuic v5 (QUIC 协议，类似 Hysteria)
# export tupt=yes

# [可选] Shadowsocks-2022 (经典协议)
# export sspt=yes

# [可选] Socks5 (仅用于配合其他工具，不做直接代理)
# export sopt=yes

# --- 高级配置 (Reality & CDN) ---
# Reality 目标网站 (偷取证书的目标，建议 apple.com, microsoft.com, amazon.com)
export reym="www.apple.com"

# Cloudflare 优选域名 (仅用于 VMess/VLESS WS + CDN 模式)
# 如果不填，默认不启用 CDN 优化
# export cdnym="cf.优选域名.com"

# --- Argo 隧道配置 (可选) ---
# 是否启用 Argo 隧道？(留空不启用，填 yes 启用)
# export argo=""
# Argo 固定隧道 Token (如果你有的话)
# export agk=""
# Argo 固定隧道域名
# export agn=""

# --- WARP 配置 (解锁流媒体/GPT) ---
# 留空=不安装
# warp=warp      -> 接管 IPv4 + IPv6 出站
# warp=s4        -> 仅 Sing-box 接管 IPv4
# warp=s6        -> 仅 Sing-box 接管 IPv6
export warp=""

# ==============================================================================
# 开始安装
# ==============================================================================
echo "正在启动 Argosbx 安装脚本..."
# 下载并运行主脚本 (这里假设 sbxargo.sh 在同一目录下，或者使用远程链接)
if [ -f "./sbxargo.sh" ]; then
    bash ./sbxargo.sh
else
    # 如果本地没有，尝试从远程下载 (这里使用示例 URL，请替换为你的真实 URL)
    bash <(curl -Ls https://raw.githubusercontent.com/wowcosplayg/sbxargo/main/sbxargo.sh)
fi
