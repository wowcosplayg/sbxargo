#!/bin/bash

# P0 优化验证测试脚本
# 用于验证已实施的 P0 级别安全修复
# 版本: 1.0
# 日期: 2025-12-31

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试结果统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 打印带颜色的消息
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${NC}ℹ${NC} $1"
}

# 测试函数
run_test() {
    local test_name="$1"
    local test_func="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
    echo "测试 #$TOTAL_TESTS: $test_name"
    echo "----------------------------------------"

    if $test_func; then
        print_success "测试通过"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        print_error "测试失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# P0.1: 测试 download.sh SHA256 校验功能
test_download_sha256() {
    local file="D:\\project\\a\\src\\download.sh"

    # 检查文件是否存在
    if [ ! -f "$file" ]; then
        print_error "文件不存在: $file"
        return 1
    fi

    # 检查是否包含 verify_checksum 函数
    if ! grep -q "verify_checksum()" "$file"; then
        print_error "未找到 verify_checksum 函数"
        return 1
    fi

    print_success "verify_checksum 函数已添加"

    # 检查是否在 download_file 中调用
    if ! grep -q 'verify_checksum.*download_type' "$file"; then
        print_error "verify_checksum 未在 download_file 中调用"
        return 1
    fi

    print_success "verify_checksum 已在 download_file 中调用"

    # 检查是否支持 sha256sum 命令
    if ! grep -q "sha256sum" "$file"; then
        print_error "未找到 sha256sum 校验逻辑"
        return 1
    fi

    print_success "SHA256 校验逻辑已实现"

    # 检查是否有错误处理
    if ! grep -q "校验失败" "$file"; then
        print_error "未找到校验失败的错误处理"
        return 1
    fi

    print_success "校验失败错误处理已添加"

    # 检查是否有跳过校验的逻辑（容错处理）
    if ! grep -q "跳过.*验证\|跳过.*校验" "$file"; then
        print_error "未找到容错处理逻辑"
        return 1
    fi

    print_success "容错处理逻辑已添加"

    return 0
}

# P0.2: 测试 systemd.sh 非特权用户配置
test_systemd_nonroot() {
    local file="D:\\project\\a\\src\\systemd.sh"

    # 检查文件是否存在
    if [ ! -f "$file" ]; then
        print_error "文件不存在: $file"
        return 1
    fi

    # 检查是否包含 create_service_user 函数
    if ! grep -q "create_service_user()" "$file"; then
        print_error "未找到 create_service_user 函数"
        return 1
    fi

    print_success "create_service_user 函数已添加"

    # 检查 sing-box 服务配置
    if grep -q "^User=root" "$file"; then
        print_error "sing-box 服务仍使用 root 用户"
        return 1
    fi

    if ! grep -q "User=sing-box" "$file"; then
        print_error "未找到 User=sing-box 配置"
        return 1
    fi

    print_success "sing-box 服务已配置为非 root 用户"

    # 检查 caddy 服务配置
    if ! grep -q "User=caddy" "$file"; then
        print_error "未找到 User=caddy 配置"
        return 1
    fi

    print_success "caddy 服务已配置为非 root 用户"

    # 检查是否设置了 Capabilities
    if ! grep -q "AmbientCapabilities=CAP_NET_BIND_SERVICE" "$file"; then
        print_error "未找到 CAP_NET_BIND_SERVICE capability"
        return 1
    fi

    print_success "已设置必要的 Linux Capabilities"

    # 检查是否有安全增强配置
    if ! grep -q "ProtectSystem=strict" "$file"; then
        print_error "未找到 ProtectSystem=strict 配置"
        return 1
    fi

    print_success "已添加安全增强配置 (ProtectSystem)"

    # 检查是否有 ProtectHome
    if ! grep -q "ProtectHome=true" "$file"; then
        print_error "未找到 ProtectHome 配置"
        return 1
    fi

    print_success "已添加 ProtectHome 配置"

    # 检查是否有 NoNewPrivileges
    if ! grep -q "NoNewPrivileges=true" "$file"; then
        print_error "未找到 NoNewPrivileges 配置"
        return 1
    fi

    print_success "已添加 NoNewPrivileges 配置"

    return 0
}

# P0.3: 测试配置备份与回滚机制
test_backup_rollback() {
    local backup_file="D:\\project\\a\\src\\backup.sh"
    local core_file="D:\\project\\a\\src\\core.sh"

    # 检查 backup.sh 是否存在
    if [ ! -f "$backup_file" ]; then
        print_error "文件不存在: $backup_file"
        return 1
    fi

    print_success "backup.sh 模块已创建"

    # 检查核心功能函数
    local required_functions=(
        "backup_config"
        "rollback_to_backup"
        "rollback_to_last"
        "list_backups"
        "cleanup_old_backups"
    )

    for func in "${required_functions[@]}"; do
        if ! grep -q "${func}()" "$backup_file"; then
            print_error "未找到函数: $func"
            return 1
        fi
    done

    print_success "所有必需的备份函数已实现"

    # 检查 core.sh 是否调用备份
    if ! grep -q "backup_config.*auto_before" "$core_file"; then
        print_error "core.sh 未调用自动备份"
        return 1
    fi

    print_success "core.sh 已集成自动备份调用"

    # 检查是否有备份元数据
    if ! grep -q "backup.info" "$backup_file"; then
        print_error "未找到备份元数据逻辑"
        return 1
    fi

    print_success "备份元数据逻辑已实现"

    # 检查是否有配置验证
    if ! grep -q "check.*config" "$backup_file"; then
        print_error "未找到配置验证逻辑"
        return 1
    fi

    print_success "配置验证逻辑已实现"

    # 检查是否有服务重启逻辑
    if ! grep -q "systemctl.*restart" "$backup_file"; then
        print_error "未找到服务重启逻辑"
        return 1
    fi

    print_success "服务重启逻辑已实现"

    return 0
}

# 代码质量检查
test_code_quality() {
    local files=(
        "D:\\project\\a\\src\\download.sh"
        "D:\\project\\a\\src\\systemd.sh"
        "D:\\project\\a\\src\\backup.sh"
    )

    for file in "${files[@]}"; do
        if [ ! -f "$file" ]; then
            print_warning "文件不存在，跳过: $file"
            continue
        fi

        # 检查 Shell 语法
        if bash -n "$file" 2>/dev/null; then
            print_success "$(basename $file) 语法检查通过"
        else
            print_error "$(basename $file) 语法错误"
            return 1
        fi
    done

    return 0
}

# 文档完整性检查
test_documentation() {
    local docs=(
        "D:\\project\\a\\src\\BACKUP_GUIDE.md"
        "D:\\project\\a\\src\\CRITICAL_ANALYSIS.md"
        "D:\\project\\a\\src\\OPTIMIZATION_PLAN.md"
    )

    for doc in "${docs[@]}"; do
        if [ ! -f "$doc" ]; then
            print_warning "文档不存在: $(basename $doc)"
            continue
        fi

        print_success "文档存在: $(basename $doc)"
    done

    return 0
}

# 安全配置检查
test_security_hardening() {
    local systemd_file="D:\\project\\a\\src\\systemd.sh"

    if [ ! -f "$systemd_file" ]; then
        print_error "systemd.sh 不存在"
        return 1
    fi

    # 检查是否移除了 root 用户
    if grep -q "^User=root" "$systemd_file" 2>/dev/null; then
        print_error "仍然存在 User=root 配置"
        return 1
    fi

    print_success "已移除 User=root 配置"

    # 检查安全增强配置
    local security_configs=(
        "ProtectSystem=strict"
        "ProtectHome=true"
        "ProtectKernelTunables=true"
        "NoNewPrivileges=true"
    )

    for config in "${security_configs[@]}"; do
        if ! grep -q "$config" "$systemd_file"; then
            print_warning "未找到安全配置: $config"
        else
            print_success "已配置: $config"
        fi
    done

    return 0
}

# 主测试流程
main() {
    echo "=========================================="
    echo "  P0 优化验证测试"
    echo "=========================================="
    echo ""
    echo "测试目标: 验证 P0 级别安全修复"
    echo "测试日期: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # 运行所有测试
    run_test "P0.1: SHA256 完整性校验" test_download_sha256
    run_test "P0.2: 非特权用户运行服务" test_systemd_nonroot
    run_test "P0.3: 配置备份与回滚机制" test_backup_rollback
    run_test "代码质量检查" test_code_quality
    run_test "文档完整性检查" test_documentation
    run_test "安全配置强化检查" test_security_hardening

    # 打印测试结果
    echo ""
    echo "=========================================="
    echo "  测试结果摘要"
    echo "=========================================="
    echo ""
    echo "总测试数:   $TOTAL_TESTS"
    echo "通过:       ${GREEN}$PASSED_TESTS${NC}"
    echo "失败:       ${RED}$FAILED_TESTS${NC}"
    echo "通过率:     $(awk "BEGIN {printf \"%.1f\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")%"
    echo ""

    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}=========================================="
        echo "  ✓ 所有测试通过！"
        echo "==========================================${NC}"
        echo ""
        echo "P0 级别优化已成功实施："
        echo "  ✓ SHA256 完整性校验已添加"
        echo "  ✓ 服务已配置为非特权用户运行"
        echo "  ✓ 配置备份与回滚机制已实现"
        echo ""
        echo "建议下一步："
        echo "  1. 在测试环境中验证实际功能"
        echo "  2. 进行集成测试"
        echo "  3. 继续实施 P1 级别优化"
        echo ""
        return 0
    else
        echo -e "${RED}=========================================="
        echo "  ✗ 存在失败的测试"
        echo "==========================================${NC}"
        echo ""
        echo "请检查失败的测试项并修复问题"
        echo ""
        return 1
    fi
}

# 运行主函数
main "$@"
