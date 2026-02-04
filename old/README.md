# Argosbx 统一版 - 一键部署脚本

> 网络代理工具(Xray + Sing-box)自动化部署系统 - 单文件交付版

[![Version](https://img.shields.io/badge/version-V25.11.20--Unified-blue.svg)](https://github.com/yonggekkk/argosbx)
[![Shell](https://img.shields.io/badge/shell-POSIX%20sh-green.svg)]()
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)]()

---

## 📦 项目结构

```
D:\project\a\
├── argosbx.sh              # ⭐ 统一脚本(1838行, 64KB)
├── README.md               # 📖 本文档
├── README_UNIFIED.md       # 📖 详细使用文档
├── DELIVERY.md             # 📖 交付说明
├── SUMMARY.md              # 📊 交付摘要
├── src/                    # 📁 源代码模块(参考)
├── sing-box-main/          # 📁 Sing-box 主程序(参考)
└── archive/                # 📁 历史文件归档
    ├── scripts/            #    - 历史脚本
    └── docs/               #    - 历史文档
```

---

## 🚀 快速开始

### 一键安装

```bash
# 1. 使用统一脚本(推荐)
vlpt=yes bash argosbx.sh

# 2. 查看节点信息
bash argosbx.sh list

# 3. 启用调试日志
export LOG_LEVEL=DEBUG
vlpt=yes bash argosbx.sh
```

### 常用命令

```bash
bash argosbx.sh list        # 显示节点信息
bash argosbx.sh upx         # 更新 Xray 内核
bash argosbx.sh ups         # 更新 Sing-box 内核
bash argosbx.sh res         # 重启服务
bash argosbx.sh del         # 卸载
```

---

## ✨ 核心特性

### 🎯 单文件交付
- **统一脚本**: `argosbx.sh` 包含所有功能
- **无需依赖**: 无需额外脚本文件
- **开箱即用**: 下载即可运行

### 🔧 企业级特性
- ✅ **四级日志系统**: DEBUG/INFO/WARN/ERROR
- ✅ **自动备份回滚**: 操作前备份，失败自动恢复
- ✅ **全面依赖检查**: 启动时检查系统环境
- ✅ **配置验证**: JSON/端口/UUID/域名验证

### 📊 支持的协议
- Vless-Reality-Vision (`vlpt`)
- Vless-xhttp-Reality (`xhpt`)
- Vless-xhttp (`vxpt`)
- Vless-ws (`vwpt`)
- Vmess-ws (`vmpt`)
- Hysteria2 (`hypt`)
- Tuic (`tupt`)
- Shadowsocks-2022 (`sspt`)
- AnyTLS (`anpt`)
- Any-Reality (`arpt`)
- Socks5 (`sopt`)

---

## 📖 文档导航

| 文档 | 说明 |
|------|------|
| **README.md** | 本文档 - 快速开始 |
| **README_UNIFIED.md** | 详细使用文档 - 完整功能说明 |
| **DELIVERY.md** | 交付说明 - 部署指南 |
| **SUMMARY.md** | 交付摘要 - 项目概览 |

---

## 🎓 使用示例

### 示例 1: 单协议安装
```bash
vlpt=yes bash argosbx.sh
```

### 示例 2: 多协议组合
```bash
vlpt=yes vwpt=yes hyp=yes bash argosbx.sh
```

### 示例 3: 自定义配置
```bash
uuid=your-uuid vlpt=12345 name=MyNode bash argosbx.sh
```

### 示例 4: 启用详细日志
```bash
export LOG_LEVEL=DEBUG
vlpt=yes bash argosbx.sh
cat $HOME/agsbx/argosbx.log
```

---

## 🔧 系统要求

- **操作系统**: Linux (systemd/OpenRC/nohup)
- **架构**: amd64/x86_64, arm64/aarch64
- **必需依赖**: grep, awk, sed, curl 或 wget
- **可选依赖**: jq, openssl, base64

---

## 📊 优化对比

| 项目 | 原版 | 统一版 | 改进 |
|------|------|--------|------|
| **脚本文件** | 5个 | 1个 | ↓ 80% |
| **文档文件** | 8个 | 4个 | ↓ 50% |
| **日志系统** | echo | 四级日志 | ✅ 100% |
| **错误处理** | 无 | 备份+回滚 | ✅ 100% |
| **交付方式** | 多文件 | 单文件 | ✅ 简化 |

---

## 🗂️ 目录说明

### 核心文件
- **argosbx.sh** - 统一脚本，包含所有功能

### 文档文件
- **README.md** - 快速开始(本文档)
- **README_UNIFIED.md** - 详细文档
- **DELIVERY.md** - 交付说明
- **SUMMARY.md** - 项目摘要

### 参考目录
- **src/** - 源代码模块(仅供参考)
- **sing-box-main/** - Sing-box 程序(仅供参考)

### 归档目录
- **archive/scripts/** - 历史脚本文件
- **archive/docs/** - 历史文档文件

---

## 💡 故障排查

### 查看日志
```bash
cat $HOME/agsbx/argosbx.log          # 查看全部
grep ERROR $HOME/agsbx/argosbx.log   # 仅错误
tail -f $HOME/agsbx/argosbx.log      # 实时查看
```

### 依赖检查
```bash
# Debian/Ubuntu
apt-get install -y grep gawk sed curl wget jq

# CentOS/RHEL
yum install -y grep gawk sed curl wget jq
```

### 备份恢复
```bash
# 查看备份
ls -la $HOME/agsbx/backup_*

# 手动恢复
cp -r $HOME/agsbx/backup_YYYYMMDD_HHMMSS/* $HOME/agsbx/
```

---

## 🙏 致谢

- **原作者**: [yonggekkk](https://github.com/yonggekkk/argosbx)
- **博客**: ygkkk.blogspot.com
- **YouTube**: www.youtube.com/@ygkkk

---

## 📜 版本信息

- **版本**: V25.11.20-Unified
- **更新**: 2025-12-31
- **特点**: 单文件交付，企业级质量

---

## 📞 获取帮助

1. 查看详细文档: `README_UNIFIED.md`
2. 查看交付说明: `DELIVERY.md`
3. 查看日志文件: `$HOME/agsbx/argosbx.log`
4. 访问原项目: https://github.com/yonggekkk/argosbx

---

<div align="center">

**🎉 单文件部署，开箱即用！**

</div>
