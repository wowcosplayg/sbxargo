#!/bin/bash

################################################################################
# 文件名: validator.sh
# 功能: 配置文件验证 - 验证配置合法性、备份与回滚
# 依赖: $is_core_bin, utils/display.sh
################################################################################

# 备份目录和配置
readonly BACKUP_DIR="$is_conf_dir/backup"
readonly MAX_BACKUPS=10

################################################################################
# 函数名: validate_config
# 功能: 验证配置文件是否合法
# 参数: $1 - 配置文件路径
# 返回: 0 表示有效, 1 表示无效
# 说明: 使用 sing-box check 命令验证配置
# 示例:
#   validate_config "$is_config_json" && echo "配置有效"
################################################################################
validate_config() {
    local config_file=$1

    if [[ ! -f "$config_file" ]]; then
        err "配置文件不存在: $config_file"
        return 1
    fi

    log_info "验证配置文件: $config_file"

    if $is_core_bin check -c "$config_file" &>/dev/null; then
        log_info "配置验证通过 ✓"
        return 0
    else
        log_error "配置验证失败 ✗"
        $is_core_bin check -c "$config_file" 2>&1 | head -20
        return 1
    fi
}

################################################################################
# 函数名: backup_config
# 功能: 备份配置文件
# 参数: $1 - 要备份的配置文件路径
# 返回: 0 表示成功, 1 表示失败
# 说明:
#   - 自动创建备份目录
#   - 备份文件名格式: config_YYYYMMDD_HHMMSS.json
#   - 保留最近 MAX_BACKUPS 个备份
#   - 记录最后备份路径到 .last_backup
################################################################################
backup_config() {
    local config_file=$1
    local backup_name="$(basename "$config_file" .json)_$(date +%Y%m%d_%H%M%S).json"
    local backup_path="$BACKUP_DIR/$backup_name"

    # 创建备份目录
    mkdir -p "$BACKUP_DIR"

    # 检查源文件
    if [[ ! -f "$config_file" ]]; then
        log_warn "配置文件不存在,跳过备份: $config_file"
        return 0
    fi

    # 执行备份
    if cp "$config_file" "$backup_path"; then
        log_info "配置已备份: $backup_path"
        echo "$backup_path" > "$is_conf_dir/.last_backup"

        # 清理旧备份
        cleanup_old_backups
        return 0
    else
        log_error "备份失败: $config_file"
        return 1
    fi
}

################################################################################
# 函数名: cleanup_old_backups
# 功能: 清理旧的备份文件,保留最近的 N 个
# 参数: 无
# 返回: 无
# 说明: 按修改时间排序,删除超过 MAX_BACKUPS 的旧备份
################################################################################
cleanup_old_backups() {
    local backup_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)

    if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
        log_info "清理旧备份,保留最近 $MAX_BACKUPS 个"
        # 按时间倒序列出,跳过前 MAX_BACKUPS 个,删除其余的
        ls -1t "$BACKUP_DIR" | tail -n +$((MAX_BACKUPS + 1)) | \
            xargs -I {} rm -f "$BACKUP_DIR/{}"
    fi
}

################################################################################
# 函数名: rollback_config
# 功能: 回滚到最后一次备份的配置
# 参数: 无
# 返回: 0 表示成功, 1 表示失败
# 说明:
#   - 从 .last_backup 读取最后备份路径
#   - 验证备份文件有效性
#   - 恢复配置并重启服务
################################################################################
rollback_config() {
    local last_backup=$(cat "$is_conf_dir/.last_backup" 2>/dev/null)

    if [[ -z "$last_backup" || ! -f "$last_backup" ]]; then
        log_error "未找到备份文件"
        return 1
    fi

    log_warn "回滚到备份: $last_backup"

    # 验证备份文件
    if ! validate_config "$last_backup"; then
        log_error "备份文件也无效!"
        return 1
    fi

    # 恢复配置
    if cp "$last_backup" "$is_config_json"; then
        log_info "配置已恢复"

        # 重启服务
        if systemctl is-active "$is_core" &>/dev/null; then
            systemctl restart "$is_core"
            log_info "服务已重启"
        fi

        return 0
    else
        log_error "配置恢复失败"
        return 1
    fi
}

################################################################################
# 函数名: list_backups
# 功能: 列出所有可用的备份文件
# 参数: 无
# 返回: 输出备份文件列表
# 说明: 按时间倒序显示,最新的在最上面
################################################################################
list_backups() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "没有找到备份目录"
        return 1
    fi

    local backup_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)

    if [[ $backup_count -eq 0 ]]; then
        echo "没有可用的备份文件"
        return 1
    fi

    echo "可用的备份文件 (总计: $backup_count):"
    echo "----------------------------------------"

    local i=1
    ls -1t "$BACKUP_DIR" | while read backup_file; do
        local full_path="$BACKUP_DIR/$backup_file"
        local size=$(du -h "$full_path" | cut -f1)
        local date=$(stat -c %y "$full_path" | cut -d. -f1)
        echo "$i) $backup_file"
        echo "   大小: $size  时间: $date"
        ((i++))
    done
}

################################################################################
# 函数名: restore_backup
# 功能: 恢复指定的备份文件
# 参数: $1 - 备份文件名或索引号
# 返回: 0 表示成功, 1 表示失败
################################################################################
restore_backup() {
    local backup_id=$1
    local backup_file=""

    # 如果是数字,按索引查找
    if [[ $backup_id =~ ^[0-9]+$ ]]; then
        backup_file=$(ls -1t "$BACKUP_DIR" | sed -n "${backup_id}p")
    else
        backup_file=$backup_id
    fi

    local backup_path="$BACKUP_DIR/$backup_file"

    if [[ ! -f "$backup_path" ]]; then
        log_error "备份文件不存在: $backup_file"
        return 1
    fi

    log_info "恢复备份: $backup_file"

    # 验证备份
    if ! validate_config "$backup_path"; then
        log_error "备份文件无效"
        return 1
    fi

    # 备份当前配置
    backup_config "$is_config_json"

    # 恢复
    if cp "$backup_path" "$is_config_json"; then
        log_info "配置已恢复"

        # 重启服务
        if systemctl is-active "$is_core" &>/dev/null; then
            systemctl restart "$is_core"
            log_info "服务已重启"
        fi

        return 0
    else
        log_error "恢复失败"
        return 1
    fi
}

################################################################################
# 函数名: safe_update_config
# 功能: 安全地更新配置 (备份 → 验证 → 应用 → 回滚)
# 参数:
#   $1 - 新配置文件路径
# 返回: 0 表示成功, 1 表示失败
# 说明:
#   1. 备份当前配置
#   2. 验证新配置
#   3. 如果验证失败,自动回滚
#   4. 如果验证成功,应用新配置并重启服务
################################################################################
safe_update_config() {
    local new_config=$1

    # 1. 备份当前配置
    log_info "步骤 1/4: 备份当前配置"
    backup_config "$is_config_json" || log_warn "备份失败,继续操作"

    # 2. 验证新配置
    log_info "步骤 2/4: 验证新配置"
    if ! validate_config "$new_config"; then
        log_error "新配置验证失败,操作中止"
        return 1
    fi

    # 3. 应用新配置
    log_info "步骤 3/4: 应用新配置"
    if ! cp "$new_config" "$is_config_json"; then
        log_error "配置应用失败"
        rollback_config
        return 1
    fi

    # 4. 重启服务
    log_info "步骤 4/4: 重启服务"
    if systemctl is-active "$is_core" &>/dev/null; then
        if ! systemctl restart "$is_core"; then
            log_error "服务重启失败,正在回滚..."
            rollback_config
            return 1
        fi

        # 等待服务启动
        sleep 2

        # 检查服务状态
        if ! systemctl is-active "$is_core" &>/dev/null; then
            log_error "服务启动失败,正在回滚..."
            rollback_config
            return 1
        fi
    fi

    log_info "配置更新成功 ✓"
    return 0
}
