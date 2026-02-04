# 订阅功能使用说明

argosbx.sh 脚本现已支持自动生成 V2ray 订阅和 Clash 配置文件。

## 功能特性

### V2ray 订阅
- 自动读取所有节点链接
- 生成 base64 编码的订阅内容
- 兼容所有标准 V2ray 客户端

### Clash 配置
- 支持协议：VMess、VLESS、Shadowsocks-2022、Hysteria2、TUIC
- 自动生成代理组（手动选择 + 自动测速）
- 包含基础分流规则（Google、YouTube、GitHub 等）
- 完整的 DNS 配置

## 使用方法

### 1. 自动生成（安装完成后）

脚本安装完成后，会自动生成订阅文件：

```bash
bash argosbx.sh
```

生成的文件位置：
- V2ray 订阅：`$HOME/agsbx/v2ray_sub.txt`
- Clash 配置：`$HOME/agsbx/clash.yaml`

### 2. 手动生成订阅

如果需要重新生成订阅文件，使用以下命令：

```bash
bash argosbx.sh sub
```

或使用快捷方式（首次安装后需重连 SSH）：

```bash
agsbx sub
```

### 3. 查看订阅内容

**V2ray 订阅（base64 编码）：**
```bash
cat $HOME/agsbx/v2ray_sub.txt
```

**解码查看原始链接：**
```bash
cat $HOME/agsbx/v2ray_sub.txt | base64 -d
```

**Clash 配置：**
```bash
cat $HOME/agsbx/clash.yaml
```

## 客户端配置

### V2ray 客户端

1. **复制订阅内容：**
   ```bash
   cat $HOME/agsbx/v2ray_sub.txt
   ```

2. **导入方式：**
   - **方式一（推荐）**：如果有 Web 服务器，将 `v2ray_sub.txt` 上传并通过 HTTPS 提供订阅 URL
   - **方式二**：直接复制 base64 内容，粘贴到支持 "从剪贴板导入" 的客户端

3. **支持的客户端：**
   - V2rayN（Windows）
   - V2rayNG（Android）
   - Shadowrocket（iOS）
   - Qv2ray（跨平台）

### Clash 客户端

1. **下载配置文件：**
   ```bash
   # 方法 1: 使用 scp 下载
   scp user@server:~/agsbx/clash.yaml ./clash.yaml

   # 方法 2: 直接复制内容
   cat $HOME/agsbx/clash.yaml
   ```

2. **导入客户端：**
   - **Clash for Windows**：配置 → 导入 → 选择 `clash.yaml`
   - **ClashX（macOS）**：配置 → 编辑配置 → 粘贴内容
   - **Clash for Android**：配置 → 新建配置 → 从文件导入

3. **验证配置：**
   - 检查代理列表是否显示所有节点
   - 测试连接延迟
   - 选择 "AUTO" 代理组自动测速

## 配置文件说明

### V2ray 订阅内容

每行一个节点链接，支持的格式：
- `vmess://` - VMess 协议
- `vless://` - VLESS 协议
- `ss://` - Shadowsocks
- `hysteria2://` - Hysteria2 协议
- `tuic://` - TUIC 协议

### Clash 配置结构

```yaml
# 基础配置
port: 7890              # HTTP 代理端口
socks-port: 7891        # SOCKS5 代理端口

# DNS 配置
dns:
  nameserver:           # 国内 DNS
    - 223.5.5.5
    - 119.29.29.29
  fallback:             # 国外 DNS
    - 8.8.8.8
    - 1.1.1.1

# 代理节点
proxies:
  - name: "节点名称"
    type: vmess/vless/ss/hysteria2/tuic
    # ... 节点配置

# 代理组
proxy-groups:
  - name: "PROXY"       # 手动选择
    type: select
  - name: "AUTO"        # 自动测速
    type: url-test

# 分流规则
rules:
  - DOMAIN-SUFFIX,google.com,PROXY
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
```

## 自定义 Clash 配置

如需修改 Clash 配置，编辑 `$HOME/agsbx/clash.yaml`：

### 修改代理端口
```yaml
port: 7890              # 改为你的端口
socks-port: 7891
```

### 添加分流规则
```yaml
rules:
  # 添加自定义规则
  - DOMAIN-SUFFIX,example.com,DIRECT
  - DOMAIN-KEYWORD,ads,REJECT
  # 保留原有规则
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
```

### 调整自动测速
```yaml
proxy-groups:
  - name: "AUTO"
    type: url-test
    url: 'http://www.gstatic.com/generate_204'
    interval: 300       # 测速间隔（秒）
```

## 故障排查

### 1. 订阅文件未生成

**检查模块是否存在：**
```bash
ls -la $HOME/agsbx/subscription.sh
```

**重新安装：**
```bash
bash argosbx.sh rep
```

### 2. Clash 节点无法连接

**检查节点链接格式：**
```bash
cat $HOME/agsbx/jh.txt
```

**验证 YAML 语法：**
- 在线工具：https://www.yamllint.com/
- 命令行：`yamllint $HOME/agsbx/clash.yaml`（需安装 yamllint）

### 3. V2ray 客户端无法识别

**验证 base64 编码：**
```bash
# 解码检查
cat $HOME/agsbx/v2ray_sub.txt | base64 -d

# 应显示完整的节点链接
```

### 4. Shadowsocks 节点格式错误

当前 SS 链接解析支持两种格式：
- 未编码：`ss://method:password@host:port#name`
- Base64 编码：`ss://base64(method:password)@host:port#name`

如果解析失败，检查 `jh.txt` 中的 SS 链接格式。

## 更新订阅

每次修改配置或添加新节点后，重新生成订阅：

```bash
agsbx sub
# 或
bash argosbx.sh sub
```

## 技术细节

### 支持的协议转换

| 协议 | V2ray 订阅 | Clash 支持 | 备注 |
|------|-----------|-----------|------|
| VMess | ✅ | ✅ | 支持 ws/xhttp/grpc |
| VLESS | ✅ | ✅ | 支持 Reality |
| Shadowsocks | ✅ | ✅ | SS-2022 |
| Hysteria2 | ✅ | ✅ | - |
| TUIC | ✅ | ✅ | TUIC v5 |

### 传输协议映射

| Xray | Clash | 说明 |
|------|-------|------|
| xhttp | http | Clash Meta 支持 HTTP/2 |
| ws | ws | WebSocket |
| grpc | grpc | gRPC |
| tcp+reality | tcp+tls | Reality 映射为 TLS |

## 相关命令

```bash
# 显示所有节点信息
agsbx list

# 生成订阅文件
agsbx sub

# 重新安装（保留配置）
agsbx rep

# 卸载脚本
agsbx del
```

## 注意事项

1. **订阅安全性**：
   - 不要公开分享订阅文件（包含节点信息）
   - 建议通过 HTTPS 提供订阅 URL
   - 定期更换节点密码/UUID

2. **Clash 兼容性**：
   - 推荐使用 Clash Premium 或 Clash Meta
   - 旧版 Clash 可能不支持某些协议（如 VLESS Reality）

3. **定期更新**：
   - 节点变更后记得重新生成订阅
   - 客户端需手动更新订阅或重新导入配置

## 问题反馈

如遇到问题，请提供以下信息：
- 订阅生成错误信息
- `jh.txt` 文件内容（隐藏敏感信息）
- 客户端类型和版本
