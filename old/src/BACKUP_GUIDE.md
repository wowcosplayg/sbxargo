# 配置备份与回滚使用指南

## 概述

backup.sh 模块提供了完整的配置备份和回滚功能，确保配置修改的安全性和可恢复性。

## 主要功能

### 1. 自动备份

配置修改前会自动创建备份，无需手动操作。

- 在 `change` 命令执行前自动备份
- 在 `create config.json` 执行前自动备份
- 备份包含完整的配置文件和元数据

### 2. 手动备份

```bash
# 创建手动备份
backup_config "my_backup_description"

# 示例
backup_config "测试新配置前的备份"
```

### 3. 列出备份

```bash
# 查看所有可用备份
list_backups
```

输出示例：
```
可用的配置备份 (共 3 个):

  1) 20251231_143022_auto_before_change
     时间: 2025-12-31 14:30:22
     描述: auto_before_change

  2) 20251231_120000_manual
     时间: 2025-12-31 12:00:00
     描述: manual

  3) 20251230_180000_before_rollback
     时间: 2025-12-30 18:00:00
     描述: before_rollback
```

### 4. 回滚操作

#### 回滚到最后一次备份
```bash
rollback_to_last
```

#### 交互式选择备份回滚
```bash
interactive_rollback
```

#### 回滚到指定备份
```bash
rollback_to_backup "/etc/sing-box/backups/20251231_143022_auto_before_change"
```

### 5. 备份管理

#### 查看备份统计
```bash
show_backup_stats
```

#### 删除指定备份
```bash
delete_backup "/etc/sing-box/backups/20251231_143022_auto_before_change"
```

#### 清空所有备份
```bash
clear_all_backups
```

#### 导出备份
```bash
export_backup "/etc/sing-box/backups/20251231_143022_auto_before_change" "backup.tar.gz"
```

#### 导入备份
```bash
import_backup "backup.tar.gz"
```

## 备份策略

### 自动备份触发时机

1. **配置更改时**: 使用 `change` 命令修改配置
2. **配置创建时**: 使用 `create config.json` 创建新配置
3. **回滚前**: 在回滚之前会先备份当前配置

### 备份保留策略

- 默认最多保留 **10 个备份**
- 超过限制时自动删除最旧的备份
- 可通过修改 `BACKUP_MAX_COUNT` 变量调整保留数量

### 备份内容

每个备份包含：
- `config.json` - 主配置文件
- `Caddyfile` - Caddy 配置（如果存在）
- 其他 `.json` 配置文件
- `backup.info` - 备份元数据

### 备份目录结构

```
/etc/sing-box/
├── config.json
├── backups/
│   ├── 20251231_143022_auto_before_change/
│   │   ├── config.json
│   │   ├── Caddyfile
│   │   └── backup.info
│   ├── 20251231_120000_manual/
│   │   ├── config.json
│   │   └── backup.info
│   └── ...
└── .last_backup
```

## 回滚流程

当执行回滚操作时：

1. **创建当前配置备份** - 在回滚前备份当前配置
2. **停止服务** - 停止 sing-box 服务
3. **恢复配置文件** - 从备份中恢复所有配置文件
4. **验证配置** - 使用 `sing-box check` 验证配置有效性
5. **重启服务** - 重新加载并重启服务

## 使用示例

### 场景 1: 安全修改配置

```bash
# 1. 修改配置（会自动备份）
./sing-box.sh change 1

# 2. 如果修改后出现问题，立即回滚
rollback_to_last

# 3. 或者交互式选择备份回滚
interactive_rollback
```

### 场景 2: 测试新配置

```bash
# 1. 手动创建备份点
backup_config "测试新配置前"

# 2. 修改配置进行测试
./sing-box.sh change 1

# 3. 测试失败，回滚到备份点
interactive_rollback  # 选择 "测试新配置前" 备份
```

### 场景 3: 定期备份

```bash
# 创建定期备份（可添加到 cron）
backup_config "daily_$(date +%Y%m%d)"
```

### 场景 4: 迁移配置

```bash
# 在源服务器上导出备份
export_backup "/etc/sing-box/backups/20251231_143022" "config_backup.tar.gz"

# 在目标服务器上导入备份
import_backup "config_backup.tar.gz"

# 回滚到导入的配置
interactive_rollback
```

## 集成到主脚本

在 `init.sh` 或主脚本中加载 backup.sh：

```bash
# 加载备份模块
. /usr/local/lib/sing-box/backup.sh
```

## 安全注意事项

1. **备份包含敏感信息** - 备份文件包含配置中的密钥、密码等敏感信息
2. **权限设置** - 确保备份目录只有 root 或服务用户可以访问
3. **定期清理** - 虽然有自动清理机制，但仍建议定期检查备份
4. **异地备份** - 重要配置应导出并保存到其他位置

## 配置变量

可在脚本顶部修改的配置：

```bash
BACKUP_ROOT_DIR="${is_conf_dir}/backups"  # 备份根目录
BACKUP_MAX_COUNT=10                        # 最多保留备份数量
LAST_BACKUP_FILE="${is_conf_dir}/.last_backup"  # 最后备份记录文件
```

## 故障排查

### 备份失败

**问题**: 创建备份时提示 "无法创建备份目录"
**解决**: 检查目录权限，确保有写入权限

```bash
ls -la /etc/sing-box/
chmod 755 /etc/sing-box/
```

### 回滚失败

**问题**: 回滚后服务无法启动
**解决**:
1. 检查配置文件语法
2. 查看服务日志
3. 手动验证配置

```bash
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
journalctl -u sing-box -n 50
```

### 备份占用空间过大

**问题**: 备份占用大量磁盘空间
**解决**: 减少保留数量或手动清理

```bash
# 修改保留数量为 5
BACKUP_MAX_COUNT=5

# 手动清理旧备份
cleanup_old_backups
```

## 高级用法

### 自定义备份钩子

在备份前后执行自定义操作：

```bash
# 备份前钩子
pre_backup_hook() {
    echo "准备备份..."
    # 自定义操作
}

# 备份后钩子
post_backup_hook() {
    echo "备份完成"
    # 发送通知、上传到云端等
}
```

### 与监控系统集成

```bash
# 备份失败时发送告警
backup_config "scheduled" || {
    send_alert "配置备份失败"
}
```

## 最佳实践

1. **修改前备份** - 重要配置修改前手动创建命名备份
2. **测试验证** - 回滚后验证服务正常运行
3. **定期导出** - 定期导出备份到安全位置
4. **文档记录** - 在备份描述中记录修改原因
5. **权限管理** - 严格控制备份目录访问权限

## 版本历史

- **v1.0** (2025-12-31) - 初始版本
  - 自动备份功能
  - 手动备份与回滚
  - 备份管理和清理
  - 导入导出功能

## 相关文档

- [src/CRITICAL_ANALYSIS.md](CRITICAL_ANALYSIS.md) - 批判性分析报告
- [src/OPTIMIZATION_PLAN.md](OPTIMIZATION_PLAN.md) - 优化实施计划
