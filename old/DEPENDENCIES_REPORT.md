# argosbx.sh 运行依赖分析报告

## 执行摘要

本文档详细列出 `argosbx.sh` 主脚本运行时需要下载的资源、访问的外部链接以及依赖的系统工具。

---

## 1. 下载的资源

### 1.1 代理内核二进制文件

#### Xray 内核（Line 436-448）

**下载位置**：
```bash
https://github.com/yonggekkk/argosbx/releases/download/argosbx/xray-{arch}
```

**支持的架构**：
- `amd64` (x86_64)
- `arm64` (aarch64)
- `armv7` (armv7l)
- `s390x`

**文件大小**：约 12-18 MB（依架构而异）

**保存路径**：`$HOME/agsbx/xray`

**功能**：Xray 代理内核，支持 VLESS、VMess 协议

**下载函数**：`upxray()` → `download_binary()`

---

#### Sing-box 内核（Line 451-463）

**下载位置**：
```bash
https://github.com/yonggekkk/argosbx/releases/download/argosbx/sing-box-{arch}
```

**支持的架构**：
- `amd64` (x86_64)
- `arm64` (aarch64)
- `armv7` (armv7l)
- `s390x`

**文件大小**：约 8-15 MB（依架构而异）

**保存路径**：`$HOME/agsbx/sing-box`

**功能**：Sing-box 代理内核，支持 Hysteria2、TUIC、Shadowsocks-2022 等协议

**下载函数**：`upsingbox()` → `download_binary()`

---

### 1.2 Cloudflare Argo 隧道客户端

#### Cloudflared 二进制文件（Line 1305-1307）

**版本获取**：
```bash
https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared
```

**下载位置**（动态最新版本）：
```bash
https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-{arch}
```

**支持的架构**：
- `amd64` (x86_64)
- `arm64` (aarch64)
- `arm` (armv7l)
- `386` (i386)

**文件大小**：约 20-35 MB（依架构而异）

**保存路径**：`$HOME/agsbx/cloudflared`

**功能**：Cloudflare Argo 隧道客户端，用于 CDN 代理

**版本检测**：自动获取最新版本号

---

### 1.3 脚本自更新

#### argosbx.sh 主脚本（Line 394, 2231）

**下载位置**：
```bash
https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh
```

**文件大小**：约 66 KB

**功能**：脚本自我更新（`bash argosbx.sh rep` 命令）

**触发条件**：用户执行更新命令

---

## 2. 访问的外部链接

### 2.1 GitHub API 和资源

| 域名 | 用途 | 访问频率 |
|------|------|---------|
| `github.com` | 下载内核二进制文件 | 安装/更新时 |
| `raw.githubusercontent.com` | 下载脚本更新 | 更新时 |
| `data.jsdelivr.com` | 查询 Cloudflared 最新版本 | 安装 Argo 时 |

---

### 2.2 IP 检测服务

#### icanhazip.com（Line 393）

**用途**：检测服务器公网 IPv4/IPv6 地址

**访问时机**：脚本运行时，用于生成客户端连接链接

**协议**：HTTPS

**返回内容**：纯文本 IP 地址

```bash
v46url="https://icanhazip.com"
ip46=$(curl -s6m6 "$v46url" || curl -s4m6 "$v46url")
```

---

### 2.3 连通性测试

#### gstatic.com（Line 2108）

**用途**：Clash 配置中的连通性测试端点

**使用位置**：生成的 `clash.yaml` 配置文件

**URL**：`http://www.gstatic.com/generate_204`

**功能**：用于代理可用性检测（返回 HTTP 204）

---

### 2.4 Cloudflare 隧道服务

#### trycloudflare.com

**用途**：免费 Argo 临时隧道域名

**访问方式**：通过 `cloudflared` 客户端连接

**功能**：自动分配临时域名（如 `xxx.trycloudflare.com`）

**协议**：HTTP/2

---

## 3. 运行环境依赖的工具

### 3.1 必需依赖（REQUIRED_DEPS）

以下工具**必须安装**，否则脚本无法运行：

| 工具 | 最低版本 | 用途 | 检查位置 |
|------|---------|------|---------|
| `grep` | 任意 | 文本搜索和过滤 | Line 123 |
| `awk` | 任意 | 文本处理和数据提取 | Line 123 |
| `sed` | 任意 | 文本替换和编辑 | Line 123 |

**缺失时行为**：脚本退出并提示安装（Line 156-158）

---

### 3.2 下载工具（二选一必需）

| 工具 | 优先级 | 用途 | 检查位置 |
|------|--------|------|---------|
| `curl` | 优先 | HTTP 下载工具 | Line 165-167 |
| `wget` | 备选 | HTTP 下载工具 | Line 165-167 |

**要求**：至少安装一个

**下载函数优先级**（Line 283-306）：
1. 优先使用 `curl`（支持进度显示 `-#`、重试 `--retry 3`）
2. 备选使用 `wget`（超时控制 `timeout 30`、重试 `--tries=3`）

---

### 3.3 可选依赖（OPTIONAL_DEPS）

以下工具**可选安装**，缺失时部分功能受限但不影响核心功能：

| 工具 | 用途 | 缺失时影响 | 检查位置 |
|------|------|-----------|---------|
| `openssl` | 生成 TLS 证书和 Reality 密钥 | 无法生成自签证书，脚本退出 | Line 124, 753-763 |
| `jq` | JSON 解析（订阅生成） | 订阅功能使用 `grep`/`sed` 备选解析 | Line 124, 1777 |
| `base64` | Base64 编码（V2ray 订阅） | 无法生成 V2ray 订阅 | Line 124, 1753 |

**缺失时行为**：输出警告，部分功能降级（Line 161-163）

---

### 3.4 系统工具和命令

#### 3.4.1 进程管理

| 工具 | 用途 | 缺失时影响 |
|------|------|-----------|
| `pgrep` | 查找进程 PID | 服务状态检测失败 |
| `pkill` | 终止进程 | 无法停止服务 |
| `nohup` | 后台运行 | 无法启动 Argo 隧道 |

#### 3.4.2 服务管理（二选一）

| 工具 | 优先级 | 用途 | 检查方式 |
|------|--------|------|---------|
| `systemctl` | 优先 | Systemd 服务管理 | `[ -x /bin/systemctl ]` |
| `rc-service` | 备选 | OpenRC 服务管理 | `[ -x /sbin/rc-service ]` |

**服务创建**：
- Systemd：创建 `.service` 文件到 `/etc/systemd/system/`
- OpenRC：创建脚本到 `/etc/init.d/`

#### 3.4.3 任务调度

| 工具 | 用途 | 缺失时影响 |
|------|------|-----------|
| `crontab` | 定时任务管理 | Argo 隧道无法定时检查重启 |

**Cron 任务示例**（Line 1402）：
```bash
@reboot sleep 10 && nohup $HOME/agsbx/cloudflared tunnel --url ...
```

#### 3.4.4 网络工具

| 工具 | 用途 | 缺失时影响 |
|------|------|-----------|
| `timeout` | 命令超时控制 | 下载可能无限等待 |
| `readlink` | 读取符号链接 | 进程检测功能受限 |

---

### 3.5 架构检测依赖

**CPU 架构识别**（Line 398-404）：
```bash
cpu=$(uname -m)
case $cpu in
    x86_64|amd64) cpu="amd64" ;;
    aarch64|arm64) cpu="arm64" ;;
    armv7*) cpu="armv7" ;;
    s390x) cpu="s390x" ;;
    *) echo "不支持的架构: $cpu"; exit 1 ;;
esac
```

**依赖命令**：
- `uname -m`：获取机器架构

---

## 4. 网络要求

### 4.1 必需的网络访问

| 目标 | 协议 | 端口 | 用途 |
|------|------|------|------|
| `github.com` | HTTPS | 443 | 下载内核和 Cloudflared |
| `raw.githubusercontent.com` | HTTPS | 443 | 脚本更新 |
| `icanhazip.com` | HTTPS | 443 | IP 检测 |
| `data.jsdelivr.com` | HTTPS | 443 | 版本查询 |

### 4.2 入站端口

**随机分配端口**（如未手动指定）：
- VLESS Reality: 随机 10000-65535
- VMess WS: 随机 10000-65535
- Hysteria2: 随机 10000-65535
- TUIC: 随机 10000-65535
- Shadowsocks: 随机 10000-65535
- Argo 本地端口: 随机 10000-65535

**端口验证**（Line 181-198）：
- 检查端口范围 1-65535
- 避免系统保留端口（1-1024，除非 root）

### 4.3 防火墙要求

**必需开放**：
- 用户配置的代理协议端口（出站 TCP/UDP）
- Cloudflare CDN 访问（Argo 模式，出站 TCP 443）

---

## 5. 文件系统要求

### 5.1 工作目录

**主目录**：`$HOME/agsbx/`

**创建的文件/目录**：
```
$HOME/agsbx/
├── xray                  # Xray 内核（12-18 MB）
├── sing-box              # Sing-box 内核（8-15 MB）
├── cloudflared           # Cloudflared（20-35 MB）
├── xr.json               # Xray 配置文件
├── sb.json               # Sing-box 配置文件
├── uuid                  # UUID 密码
├── private.key           # TLS 私钥
├── cert.pem              # TLS 证书
├── jh.txt                # 节点聚合文件
├── v2ray_sub.txt         # V2ray 订阅（base64）
├── clash.yaml            # Clash 配置
├── argo.log              # Argo 隧道日志
├── argoport.log          # Argo 本地端口记录
└── xrk/                  # Xray Reality 密钥目录
    ├── privatekey
    ├── publickey
    └── shortid
```

### 5.2 磁盘空间要求

**最小空间**：约 100 MB

**详细分配**：
- 内核文件：~50 MB (Xray + Sing-box + Cloudflared)
- 配置文件：~100 KB
- 日志文件：~10 MB（长期运行后）
- 证书文件：~5 KB

---

## 6. 权限要求

### 6.1 文件系统权限

| 操作 | 需要权限 | 说明 |
|------|---------|------|
| 创建 `$HOME/agsbx/` | 用户 HOME 写权限 | 必需 |
| 设置二进制可执行 `chmod +x` | 文件所有者 | 必需 |

### 6.2 系统服务权限

| 操作 | 需要权限 | 说明 |
|------|---------|------|
| 创建 Systemd 服务 | root 或 sudo | 写入 `/etc/systemd/system/` |
| 启动系统服务 | root 或 sudo | `systemctl start/enable` |
| 修改 Crontab | 当前用户 | 个人 cron 任务 |

**非 root 运行**：
- ✅ 可以安装和配置（在 `$HOME` 目录下）
- ✅ 可以手动启动服务（使用 `nohup`）
- ❌ 无法创建系统服务（需 sudo）
- ❌ 无法绑定 1-1024 特权端口

---

## 7. 运行时行为总结

### 7.1 首次安装（`bash argosbx.sh`）

**网络访问顺序**：
1. 检测服务器 IP：`https://icanhazip.com`
2. 下载 Xray：`https://github.com/yonggekkk/argosbx/releases/download/argosbx/xray-{arch}`
3. 下载 Sing-box：`https://github.com/yonggekkk/argosbx/releases/download/argosbx/sing-box-{arch}`
4. 查询 Cloudflared 版本：`https://data.jsdelivr.com/v1/package/gh/cloudflare/cloudflared`
5. 下载 Cloudflared：`https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-{arch}`
6. 启动 Argo 隧道：连接 Cloudflare 边缘服务器

**本地操作**：
- 生成 UUID（使用 `sing-box generate uuid` 或 `xray uuid`）
- 生成 TLS 证书（`openssl req -newkey ec ...`）
- 生成 Reality 密钥对（`xray x25519`）
- 写入配置文件（`xr.json`, `sb.json`）
- 创建系统服务（Systemd/OpenRC）
- 生成客户端链接（VMess, VLESS, SS, Hysteria2, TUIC）
- 生成订阅文件（`v2ray_sub.txt`, `clash.yaml`）

---

### 7.2 脚本更新（`bash argosbx.sh rep`）

**网络访问**：
1. 下载最新脚本：`https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh`
2. 替换当前脚本
3. 重新安装内核和配置

---

### 7.3 内核更新（`agsbx upx` / `agsbx ups`）

**网络访问**：
1. 下载最新 Xray 或 Sing-box
2. 替换旧版本
3. 重启服务

---

### 7.4 订阅生成（`agsbx sub`）

**无网络访问**：
- 读取 `$HOME/agsbx/jh.txt`（节点链接列表）
- 解析每个协议链接（VMess, VLESS, SS, Hysteria2, TUIC）
- 生成 V2ray 订阅（base64 编码）
- 生成 Clash YAML 配置（代理列表 + 分组 + 规则）
- 写入 `v2ray_sub.txt` 和 `clash.yaml`

---

## 8. 依赖项安装建议

### 8.1 Debian/Ubuntu

```bash
# 必需依赖
apt update
apt install -y grep gawk sed curl openssl

# 可选依赖
apt install -y jq
```

### 8.2 CentOS/RHEL/Rocky Linux

```bash
# 必需依赖
yum install -y grep gawk sed curl openssl

# 可选依赖
yum install -y jq
```

### 8.3 Alpine Linux

```bash
# 必需依赖
apk add grep gawk sed curl openssl

# 可选依赖
apk add jq
```

### 8.4 Arch Linux

```bash
# 必需依赖（通常已预装）
pacman -S grep gawk sed curl openssl

# 可选依赖
pacman -S jq
```

---

## 9. 离线部署支持

### 9.1 可行性分析

**理论上可行**，需要提前准备：

1. **预下载所有二进制文件**：
   - `xray-{arch}`
   - `sing-box-{arch}`
   - `cloudflared-linux-{arch}`

2. **修改脚本下载源**：
   - 替换 `https://github.com/...` 为本地 HTTP 服务器
   - 替换 IP 检测为手动输入

3. **预装系统依赖**：
   - 确保 `grep`, `awk`, `sed`, `openssl` 已安装

### 9.2 限制

- ❌ 无法使用 Argo 隧道（需连接 Cloudflare）
- ❌ 无法自动检测公网 IP（需手动指定）
- ✅ 可以使用 Reality、Hysteria2、TUIC 等协议

---

## 10. 安全考虑

### 10.1 下载源信任

**当前下载源**：
- `github.com/yonggekkk/argosbx/releases/download/argosbx/`（项目维护者）
- `github.com/cloudflare/cloudflared/releases/`（Cloudflare 官方）

**风险**：
- ⚠️ 非官方编译的 Xray/Sing-box 二进制文件
- ✅ Cloudflared 来自官方 GitHub

**建议**：
- 验证下载文件的 SHA256 哈希值（当前脚本未实现）
- 考虑从官方源编译 Xray/Sing-box

### 10.2 证书生成

**当前方式**（Line 753-763）：
- ✅ 使用本地 OpenSSL 生成自签证书
- ✅ 已移除从 GitHub 下载公共证书的代码（安全修复）

### 10.3 敏感信息

**存储在明文文件中的敏感数据**：
- `$HOME/agsbx/uuid`：用户密码
- `$HOME/agsbx/private.key`：TLS 私钥
- `$HOME/agsbx/xrk/privatekey`：Reality 私钥
- `$HOME/agsbx/jh.txt`：完整节点链接（含密码）

**建议**：
- 限制文件权限：`chmod 600 $HOME/agsbx/*.key`
- 避免在公开环境暴露 `jh.txt`

---

## 11. 故障排查

### 11.1 下载失败

**症状**：`下载失败` 错误

**可能原因**：
1. 网络无法访问 GitHub（被墙/DNS 污染）
2. curl/wget 未安装
3. 磁盘空间不足

**解决方案**：
```bash
# 测试 GitHub 连通性
curl -I https://github.com

# 使用代理下载
export https_proxy=http://your-proxy:port
bash argosbx.sh

# 检查磁盘空间
df -h $HOME
```

### 11.2 依赖缺失

**症状**：`缺少必需依赖项: xxx`

**解决方案**：
```bash
# 根据系统类型安装
apt install -y grep gawk sed curl openssl  # Debian/Ubuntu
yum install -y grep gawk sed curl openssl  # CentOS/RHEL
```

### 11.3 证书生成失败

**症状**：`TLS 证书生成失败，请安装 openssl 后重试`

**解决方案**：
```bash
# 安装 OpenSSL
apt install -y openssl  # Debian/Ubuntu
yum install -y openssl  # CentOS/RHEL

# 验证安装
openssl version
```

---

## 12. 总结

### 12.1 必需资源下载

| 资源 | 大小 | 来源 |
|------|------|------|
| Xray 内核 | 12-18 MB | GitHub Releases |
| Sing-box 内核 | 8-15 MB | GitHub Releases |
| Cloudflared | 20-35 MB | GitHub Releases |
| **总计** | **40-68 MB** | |

### 12.2 必需系统工具

**核心依赖**（脚本无法运行）：
- `grep`, `awk`, `sed`
- `curl` 或 `wget`

**关键依赖**（核心功能需要）：
- `openssl`（证书生成）
- `base64`（订阅生成）

**可选依赖**（增强功能）：
- `jq`（JSON 解析，有备选方案）
- `systemctl` 或 `rc-service`（系统服务管理）

### 12.3 网络依赖

**必需外部访问**：
- ✅ `github.com`（内核下载）
- ✅ `raw.githubusercontent.com`（脚本更新）
- ✅ `icanhazip.com`（IP 检测）
- ✅ `data.jsdelivr.com`（版本查询）
- ⚠️ Cloudflare 边缘服务器（Argo 隧道）

### 12.4 部署建议

**推荐配置**：
- ✅ 全新 VPS 或云服务器
- ✅ 公网 IP（IPv4 或 IPv6）
- ✅ 至少 512 MB RAM
- ✅ 至少 1 GB 磁盘空间
- ✅ 不限流量网络
- ✅ 开放防火墙端口

**最小配置**：
- ⚠️ 256 MB RAM（可能不稳定）
- ⚠️ 500 MB 磁盘（刚好够用）
- ❌ NAT 网络（Argo 隧道可解决）

---

**文档版本**：1.0
**脚本版本**：argosbx.sh v2273（订阅集成版）
**更新日期**：2025-01-20
