# Argosbx Configuration Guide

## Protocol Variables
To enable specific protocols, set the corresponding variable to a port number or `yes` (for random port) before running the script.

| Variable | Protocol | Service | Description |
| :--- | :--- | :--- | :--- |
| `vlpt` | **VLESS** | Xray | VLESS-TCP-Reality-Vision |
| `vmpt` | **VMess** | Xray | VMess-WS (Requires `cdnym` for CDN) |
| `vwpt` | **VLESS-WS** | Xray | VLESS-WS (Requires `cdnym` for CDN) |
| `hypt` | **Hysteria2** | Sing-box | Hysteria2 (UDP) |
| `tupt` | **Tuic v5** | Sing-box | Tuic v5 (QUIC) |
| `sspt` | **Shadowsocks**| Sing-box | Shadowsocks-2022 |
| `xhpt` | **VLESS-XHTTP**| Xray | VLESS-XHTTP-Reality-Vision |
| `vxpt` | **VLESS-XHTTP**| Xray | VLESS-XHTTP (No Reality) |
| `anpt` | **AnyTLS** | Sing-box | AnyTLS |
| `arpt` | **Any-Reality**| Sing-box | Sing-box VLESS-Reality |
| `sopt` | **Socks5** | Both | Socks5 Proxy |

## Deployment Examples

### 1. Basic Deployment (VLESS + Hysteria2)
```bash
# Enable VLESS (vlpt) and Hysteria2 (hypt) on random ports
vlpt=yes hypt=yes bash sbxargo.sh
```

### 2. Custom Port Deployment
```bash
# Enable VMess on port 8080 and VLESS on port 8443
vmpt=8080 vlpt=8443 bash sbxargo.sh
```

### 3. Full Deployment (All Protocols)
```bash
# Enable almost everything
vlpt=yes vmpt=yes hypt=yes tupt=yes sspt=yes bash sbxargo.sh
```

### 4. Advanced: Using a Fixed UUID and Domain
```bash
# Set a custom UUID and Reality Domain
uuid="de442971-897c-4235-8650-459639535359" reym="www.apple.com" vlpt=yes bash sbxargo.sh
```

## Creating a Configuration Script (Easier Method)
Instead of typing long commands, create a file named [install.sh](file:///d:/project/a/install.sh):

```bash
#!/bin/bash

# --- Protocol Configuration ---
export vlpt=yes    # Enable VLESS Reality
export hypt=yes    # Enable Hysteria2
export vmpt=8080   # Enable VMess on port 8080

# --- Advanced Config (Optional) ---
export uuid=""     # Custom UUID (leave empty to auto-generate)
export reym="www.apple.com" # Reality Fallback Domain

# --- Run the Script ---
bash sbxargo.sh
```

Run it with: `bash install.sh`

## 推荐配置组合 (Best Practices)

经过大量实践验证，以下协议组合能够完美兼顾**隐匿性**与**速度**，建议作为首选配置：

**组合方案**：`VLESS-Reality` + `Hysteria2` + `Tuic v5`

*   **VLESS-Reality (`vlpt`)**: 作为主力协议。伪装成正常网站流量 (Apple/Bing)，抗封锁能力极强，适合日常网页浏览。
*   **Hysteria2 (`hypt`)**: 作为备用/加速协议。基于 UDP 暴力加速，在晚高峰或丢包严重环境下能跑满带宽，适合看 4K/8K 视频。
*   **Tuic v5 (`tupt`)**: 作为低延迟协议。基于 QUIC 0-RTT，适合对延迟敏感的手游或即时通讯。

**如何配置此组合？**

**方法 A：智能部署脚本 (推荐)**
无需记忆任何命令，直接运行部署脚本，它会引导您完成所有配置（包括 Docker 安装）：
```bash
bash deploy.sh
```
此脚本能够：
1.  自动检测并安装 Docker (如果选择 Docker 部署)。
2.  提供全中文交互向导，选择推荐协议。
3.  自动构建镜像并启动容器 (Docker 模式) 或 直接配置系统 (直装模式)。

**方法 B：手动 Docker 部署**
```bash
docker run -d --name argosbx \
```bash
docker run -d --name argosbx \
  -v /opt/agsbx:/root/agsbx \
  -e vlpt=443 \
  -e hypt=yes \
  -e tupt=yes \
  -e hypt=yes \
  -e tupt=yes \
  argosbx-image
```

## 智能化部署场景 (Smart Scenarios)

脚本已内置针对特殊场景的优化逻辑，您可以在交互向导中选择，或通过变量启用：

### 场景 A：服务器 IP 被墙 / 想要隐藏真实 IP
**推荐方案**：启用 **Argo 隧道**
*   **效果**：所有流量通过 Cloudflare 隧道进入，防火墙只看到 Cloudflare 的流量，根本不知道您的服务器 IP。
*   **配置**：
    *   交互向导：选择启用 Argo -> 临时隧道 (无门槛) 或 固定隧道 (更稳定)。
    *   Docker/变量：`argo=vmpt` (临时) 或 `argo=vmpt agk=TOKEN agn=DOMAIN` (固定)。

### 场景 B：解锁 Netflix/Disney+ 流媒体 或 Google 验证码频繁
**推荐方案**：启用 **WARP 接管**
*   **效果**：服务器出口流量会被 WARP (Cloudflare WireGuard) 接管，获得干净的原生 IP。
*   **配置**：
    *   交互向导：选择启用 WARP -> 全局接管。
    *   Docker/变量：`warp=sx` (推荐)。

## 爪云 / PaaS 容器平台部署 (Claw Cloud)

对于**只提供容器运行环境**（如爪云 Claw Cloud Run、Google Cloud Run 等无公网 IP 或端口受限环境），本脚本完美支持。

**核心原理**：利用 **Argo 隧道** 穿透内网，无需公网 IP，无需开放端口。

**推荐配置 (Stateless)**：
PaaS 平台通常重置容器文件系统，因此强烈建议使用**环境变量**传入 Argo Token，实现无状态部署：

1.  **准备工作**：先在本地或 Cloudflare 后台申请好 Argo Tunnel Token。
2.  **部署命令 (Docker)**：
```bash
docker run -d --name argosbx \
  -e argo=vmpt \
  -e agk="eyJhIjoi..." \   # 您的 Argo Token (必填)
  -e agn="您的域名" \       # 您的域名 (选填)
  -e uuid="自定义UUID" \    # 建议固定 UUID 以便客户端长期有效
  argosbx-image
```
这样即使容器重启或重新部署，节点信息依然保持不变，无需重新订阅。
