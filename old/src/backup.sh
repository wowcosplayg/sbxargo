#!/bin/bash

# 配置备份与回滚管理模块
# 提供自动备份、手动备份、回滚等功能

# 备份目录配置
BACKUP_ROOT_DIR="${is_conf_dir}/backups"
BACKUP_MAX_COUNT=10  # 最多保留备份数量
LAST_BACKUP_FILE="${is_conf_dir}/.last_backup"

# 创建备份
# 用法: backup_config [description]
backup_config() {
    local description="${1:-manual}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${BACKUP_ROOT_DIR}/${timestamp}_${description}"

    # 创建备份目录
    if ! mkdir -p "$backup_dir" 2>/dev/null; then
        warn "无法创建备份目录: $backup_dir"
        return 1
    fi

    msg "正在创建配置备份..."

    # 备份配置文件
    if [ -f "$is_config_json" ]; then
        cp "$is_config_json" "$backup_dir/" 2>/dev/null || {
            warn "备份配置文件失败: $is_config_json"
            return 1
        }
    fi

    # 备份 Caddy 配置（如果存在）
    if [ -f "$is_caddyfile" ]; then
        cp "$is_caddyfile" "$backup_dir/" 2>/dev/null
    fi

    # 备份配置目录中的其他文件
    if [ -d "$is_conf_dir" ]; then
        find "$is_conf_dir" -maxdepth 1 -type f -name "*.json" -exec cp {} "$backup_dir/" \; 2>/dev/null
    fi

    # 创建备份元数据
    cat > "$backup_dir/backup.info" <<EOF
时间: $(date '+%Y-%m-%d %H:%M:%S')
描述: $description
配置文件: $is_config_json
用户: $(whoami)
主机: $(hostname)
EOF

    # 记录最后一次备份
    echo "$backup_dir" > "$LAST_BACKUP_FILE"

    # 清理旧备份
    cleanup_old_backups

    _green "配置备份成功: $backup_dir"
    return 0
}

# 自动备份（在配置修改前调用）
# 用法: auto_backup_before_change
auto_backup_before_change() {
    backup_config "auto_before_change"
}

# 列出所有备份
# 用法: list_backups
list_backups() {
    if [ ! -d "$BACKUP_ROOT_DIR" ]; then
        msg "暂无备份"
        return 0
    fi

    local backups=($(ls -dt "$BACKUP_ROOT_DIR"/* 2>/dev/null))
    local count=${#backups[@]}

    if [ $count -eq 0 ]; then
        msg "暂无备份"
        return 0
    fi

    msg "\n可用的配置备份 (共 $count 个):\n"
    local index=1
    for backup_dir in "${backups[@]}"; do
        local backup_name=$(basename "$backup_dir")
        local info_file="$backup_dir/backup.info"

        if [ -f "$info_file" ]; then
            local time=$(grep "时间:" "$info_file" | cut -d: -f2- | xargs)
            local desc=$(grep "描述:" "$info_file" | cut -d: -f2- | xargs)
            echo "  $index) $backup_name"
            echo "     时间: $time"
            echo "     描述: $desc"
            echo
        else
            echo "  $index) $backup_name"
            echo
        fi
        index=$((index + 1))
    done
}

# 回滚到指定备份
# 用法: rollback_to_backup <backup_dir>
rollback_to_backup() {
    local backup_dir="$1"

    if [ ! -d "$backup_dir" ]; then
        err "备份目录不存在: $backup_dir"
    fi

    msg "准备回滚到备份: $(basename $backup_dir)"

    # 在回滚前先备份当前配置
    backup_config "before_rollback"

    # 停止服务
    if systemctl is-active --quiet $is_core 2>/dev/null; then
        msg "停止 $is_core 服务..."
        systemctl stop $is_core 2>/dev/null
    fi

    # 恢复配置文件
    local restore_count=0
    for file in "$backup_dir"/*.json; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            local target_file="${is_conf_dir}/${filename}"

            cp "$file" "$target_file" 2>/dev/null && {
                msg "已恢复: $filename"
                restore_count=$((restore_count + 1))
            } || {
                warn "恢复失败: $filename"
            }
        fi
    done

    # 恢复 Caddy 配置
    if [ -f "$backup_dir/Caddyfile" ]; then
        cp "$backup_dir/Caddyfile" "$is_caddyfile" 2>/dev/null && {
            msg "已恢复: Caddyfile"
        }
    fi

    if [ $restore_count -eq 0 ]; then
        err "回滚失败: 未找到可恢复的配置文件"
    fi

    # 验证配置
    if [ -f "$is_config_json" ]; then
        msg "验证配置文件..."
        if $is_core_bin check -c "$is_config_json" 2>/dev/null; then
            _green "配置验证通过 ✓"
        else
            warn "配置验证失败，可能需要手动检查"
        fi
    fi

    # 重启服务
    msg "重启服务..."
    systemctl daemon-reload 2>/dev/null
    systemctl restart $is_core 2>/dev/null && {
        _green "服务重启成功"
    } || {
        warn "服务重启失败，请手动检查"
    }

    _green "回滚完成!"
}

# 回滚到最后一次备份
# 用法: rollback_to_last
rollback_to_last() {
    if [ ! -f "$LAST_BACKUP_FILE" ]; then
        err "未找到最后一次备份记录"
    fi

    local last_backup=$(cat "$LAST_BACKUP_FILE")
    if [ ! -d "$last_backup" ]; then
        err "最后一次备份目录不存在: $last_backup"
    fi

    rollback_to_backup "$last_backup"
}

# 清理旧备份（保留最近的 N 个）
# 用法: cleanup_old_backups
cleanup_old_backups() {
    if [ ! -d "$BACKUP_ROOT_DIR" ]; then
        return 0
    fi

    local backups=($(ls -dt "$BACKUP_ROOT_DIR"/* 2>/dev/null))
    local count=${#backups[@]}

    if [ $count -le $BACKUP_MAX_COUNT ]; then
        return 0
    fi

    msg "清理旧备份 (保留最近 $BACKUP_MAX_COUNT 个)..."

    # 删除超出限制的旧备份
    local delete_count=$((count - BACKUP_MAX_COUNT))
    for ((i=BACKUP_MAX_COUNT; i<count; i++)); do
        local old_backup="${backups[$i]}"
        rm -rf "$old_backup" 2>/dev/null && {
            msg "已删除旧备份: $(basename $old_backup)"
        }
    done
}

# 删除指定备份
# 用法: delete_backup <backup_dir>
delete_backup() {
    local backup_dir="$1"

    if [ ! -d "$backup_dir" ]; then
        err "备份目录不存在: $backup_dir"
    fi

    rm -rf "$backup_dir" 2>/dev/null && {
        _green "备份已删除: $(basename $backup_dir)"
    } || {
        err "删除备份失败: $backup_dir"
    }
}

# 清空所有备份
# 用法: clear_all_backups
clear_all_backups() {
    if [ ! -d "$BACKUP_ROOT_DIR" ]; then
        msg "暂无备份"
        return 0
    fi

    local count=$(ls -1 "$BACKUP_ROOT_DIR" 2>/dev/null | wc -l)
    if [ $count -eq 0 ]; then
        msg "暂无备份"
        return 0
    fi

    ask_if "确定要删除所有备份吗? (共 $count 个)"
    if [ $? -eq 0 ]; then
        rm -rf "$BACKUP_ROOT_DIR"/* 2>/dev/null && {
            _green "已清空所有备份"
        } || {
            err "清空备份失败"
        }
    fi
}

# 交互式回滚
# 用法: interactive_rollback
interactive_rollback() {
    list_backups

    local backups=($(ls -dt "$BACKUP_ROOT_DIR"/* 2>/dev/null))
    local count=${#backups[@]}

    if [ $count -eq 0 ]; then
        return 1
    fi

    echo -n "请选择要回滚的备份 (1-$count, 0=取消): "
    read choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ $choice -gt 0 ] && [ $choice -le $count ]; then
        local backup_dir="${backups[$((choice - 1))]}"
        rollback_to_backup "$backup_dir"
    else
        msg "已取消"
    fi
}

# 导出备份（打包为 tar.gz）
# 用法: export_backup <backup_dir> [output_file]
export_backup() {
    local backup_dir="$1"
    local output_file="${2:-$(basename $backup_dir).tar.gz}"

    if [ ! -d "$backup_dir" ]; then
        err "备份目录不存在: $backup_dir"
    fi

    tar czf "$output_file" -C "$(dirname $backup_dir)" "$(basename $backup_dir)" 2>/dev/null && {
        _green "备份已导出: $output_file"
    } || {
        err "导出备份失败"
    }
}

# 导入备份（从 tar.gz 解压）
# 用法: import_backup <backup_file>
import_backup() {
    local backup_file="$1"

    if [ ! -f "$backup_file" ]; then
        err "备份文件不存在: $backup_file"
    fi

    mkdir -p "$BACKUP_ROOT_DIR" 2>/dev/null
    tar xzf "$backup_file" -C "$BACKUP_ROOT_DIR" 2>/dev/null && {
        _green "备份已导入"
    } || {
        err "导入备份失败"
    }
}

# 显示备份统计信息
# 用法: show_backup_stats
show_backup_stats() {
    if [ ! -d "$BACKUP_ROOT_DIR" ]; then
        msg "暂无备份"
        return 0
    fi

    local count=$(ls -1 "$BACKUP_ROOT_DIR" 2>/dev/null | wc -l)
    local size=$(du -sh "$BACKUP_ROOT_DIR" 2>/dev/null | awk '{print $1}')
    local oldest=$(ls -t "$BACKUP_ROOT_DIR" 2>/dev/null | tail -1)
    local newest=$(ls -t "$BACKUP_ROOT_DIR" 2>/dev/null | head -1)

    msg "\n备份统计信息:"
    msg "  备份总数: $count"
    msg "  占用空间: $size"
    msg "  最旧备份: $oldest"
    msg "  最新备份: $newest"
    msg "  最大保留: $BACKUP_MAX_COUNT"
    msg
}
