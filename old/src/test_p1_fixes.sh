#!/bin/bash

# P1 优化验证测试脚本
# 用于验证已实施的 P1 级别健壮性改进
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

# P1.1: 测试统一错误处理机制
test_error_handler() {
    local file="D:\\project\\a\\src\\error_handler.sh"

    # 检查文件是否存在
    if [ ! -f "$file" ]; then
        print_error "文件不存在: $file"
        return 1
    fi

    print_success "error_handler.sh 模块已创建"

    # 检查核心函数
    local required_functions=(
        "log_debug"
        "log_info"
        "log_warn"
        "log_error"
        "log_fatal"
        "die"
        "error"
        "warn"
        "info"
        "debug"
        "enable_error_tracking"
        "error_trap_handler"
        "print_error_stack"
        "check_success"
        "safe_exec"
        "must_exec"
        "require_env"
        "require_command"
        "retry"
    )

    for func in "${required_functions[@]}"; do
        if ! grep -q "${func}()" "$file"; then
            print_error "未找到函数: $func"
            return 1
        fi
    done

    print_success "所有必需的错误处理函数已实现 (${#required_functions[@]} 个)"

    # 检查错误级别定义
    if ! grep -q "ERROR_LEVEL_DEBUG" "$file"; then
        print_error "未找到错误级别定义"
        return 1
    fi

    print_success "错误级别定义已实现"

    # 检查错误栈功能
    if ! grep -q "ERROR_STACK" "$file"; then
        print_error "未找到错误栈功能"
        return 1
    fi

    print_success "错误栈跟踪功能已实现"

    # 检查 trap 机制
    if ! grep -q "trap.*ERR" "$file"; then
        print_error "未找到 ERR trap 机制"
        return 1
    fi

    print_success "ERR trap 错误捕获机制已实现"

    # 测试基本的错误处理函数
    source "$file" 2>/dev/null || {
        print_error "加载 error_handler.sh 失败"
        return 1
    }

    print_success "error_handler.sh 加载成功"

    # 测试日志函数
    if ! log_info "测试信息日志" >/dev/null 2>&1; then
        print_error "log_info 函数测试失败"
        return 1
    fi

    print_success "日志函数工作正常"

    return 0
}

# P1.2: 测试多源 IP 获取容灾
test_multi_source_ip() {
    local file="D:\\project\\a\\src\\core.sh"

    # 检查文件是否存在
    if [ ! -f "$file" ]; then
        print_error "文件不存在: $file"
        return 1
    fi

    # 检查是否包含多源 IP 列表
    if ! grep -q "ip_sources=" "$file"; then
        print_error "未找到多源 IP 列表"
        return 1
    fi

    print_success "多源 IP 列表已添加"

    # 检查 IP 源数量（至少 3 个）
    local source_count=$(grep -A 10 "ip_sources=" "$file" | grep -c "https://")
    if [ "$source_count" -lt 3 ]; then
        print_error "IP 源数量不足 (当前: $source_count, 要求: >=3)"
        return 1
    fi

    print_success "配置了 $source_count 个 IP 获取源"

    # 检查是否包含不同的 IP 服务
    local expected_sources=(
        "one.one.one.one"
        "ifconfig.me"
        "ipify.org"
    )

    for source in "${expected_sources[@]}"; do
        if ! grep -q "$source" "$file"; then
            print_warning "未找到 IP 源: $source"
        else
            print_success "已配置 IP 源: $source"
        fi
    done

    # 检查是否有 IPv4 验证
    if ! grep -q "validate.*ipv4\|验证.*IPv4" "$file"; then
        print_warning "可能缺少 IPv4 格式验证"
    else
        print_success "包含 IP 格式验证逻辑"
    fi

    # 检查是否有 IPv6 支持
    if ! grep -q "ipv6\|IPv6" "$file"; then
        print_warning "可能缺少 IPv6 支持"
    else
        print_success "包含 IPv6 支持"
    fi

    # 检查是否有超时设置
    if ! grep -q "timeout" "$file"; then
        print_warning "未找到超时设置"
    else
        print_success "配置了请求超时"
    fi

    return 0
}

# P1.3: 测试输入验证和过滤
test_input_validation() {
    local file="D:\\project\\a\\src\\input_validator.sh"

    # 检查文件是否存在
    if [ ! -f "$file" ]; then
        print_error "文件不存在: $file"
        return 1
    fi

    print_success "input_validator.sh 模块已创建"

    # 检查验证函数
    local validation_functions=(
        "validate_port"
        "validate_ipv4"
        "validate_ipv6"
        "validate_domain"
        "validate_url"
        "validate_path"
        "validate_uuid"
        "validate_email"
        "validate_username"
        "validate_password"
        "validate_integer"
        "validate_boolean"
        "validate_json"
    )

    for func in "${validation_functions[@]}"; do
        if ! grep -q "${func}()" "$file"; then
            print_error "未找到验证函数: $func"
            return 1
        fi
    done

    print_success "所有验证函数已实现 (${#validation_functions[@]} 个)"

    # 检查过滤/清理函数
    local sanitize_functions=(
        "sanitize_input"
        "validate_and_sanitize"
        "url_encode"
        "html_escape"
    )

    for func in "${sanitize_functions[@]}"; do
        if ! grep -q "${func}()" "$file"; then
            print_error "未找到清理函数: $func"
            return 1
        fi
    done

    print_success "所有清理函数已实现 (${#sanitize_functions[@]} 个)"

    # 测试加载模块
    source "$file" 2>/dev/null || {
        print_error "加载 input_validator.sh 失败"
        return 1
    }

    print_success "input_validator.sh 加载成功"

    # 测试端口验证
    if validate_port "8080"; then
        print_success "端口验证: 有效端口 8080"
    else
        print_error "端口验证测试失败"
        return 1
    fi

    if ! validate_port "99999"; then
        print_success "端口验证: 无效端口 99999 被正确拒绝"
    else
        print_error "端口验证: 应该拒绝无效端口"
        return 1
    fi

    # 测试 IPv4 验证
    if validate_ipv4 "192.168.1.1"; then
        print_success "IPv4 验证: 有效 IP 192.168.1.1"
    else
        print_error "IPv4 验证测试失败"
        return 1
    fi

    if ! validate_ipv4 "999.999.999.999"; then
        print_success "IPv4 验证: 无效 IP 被正确拒绝"
    else
        print_error "IPv4 验证: 应该拒绝无效 IP"
        return 1
    fi

    # 测试域名验证
    if validate_domain "example.com"; then
        print_success "域名验证: 有效域名 example.com"
    else
        print_error "域名验证测试失败"
        return 1
    fi

    # 测试路径验证
    if validate_path "/etc/config"; then
        print_success "路径验证: 有效路径 /etc/config"
    else
        print_error "路径验证测试失败"
        return 1
    fi

    if ! validate_path "../../../etc/passwd"; then
        print_success "路径验证: 路径遍历被正确拒绝"
    else
        print_error "路径验证: 应该拒绝路径遍历"
        return 1
    fi

    # 测试输入清理
    local dangerous_input='rm -rf /; echo "hacked"'
    local cleaned=$(sanitize_input "$dangerous_input" "strict")
    if [ "$cleaned" != "$dangerous_input" ]; then
        print_success "输入清理: 危险字符被过滤"
    else
        print_error "输入清理: 应该过滤危险字符"
        return 1
    fi

    return 0
}

# 代码质量检查
test_code_quality() {
    local files=(
        "D:\\project\\a\\src\\error_handler.sh"
        "D:\\project\\a\\src\\input_validator.sh"
        "D:\\project\\a\\src\\core.sh"
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

# 集成测试
test_integration() {
    # 测试模块互相集成
    local error_handler="D:\\project\\a\\src\\error_handler.sh"
    local input_validator="D:\\project\\a\\src\\input_validator.sh"

    if [ -f "$error_handler" ] && [ -f "$input_validator" ]; then
        # 同时加载两个模块
        if source "$error_handler" 2>/dev/null && source "$input_validator" 2>/dev/null; then
            print_success "多模块集成加载成功"

            # 测试组合使用
            if log_info "测试信息" >/dev/null 2>&1 && validate_port "8080" >/dev/null 2>&1; then
                print_success "模块间功能协作正常"
            else
                print_error "模块间功能协作失败"
                return 1
            fi
        else
            print_error "多模块加载失败"
            return 1
        fi
    else
        print_warning "跳过集成测试（模块文件缺失）"
    fi

    return 0
}

# 功能完整性检查
test_completeness() {
    print_info "检查 P1 优化完整性..."

    local checks=0
    local passed=0

    # P1.1 检查
    checks=$((checks + 1))
    if [ -f "D:\\project\\a\\src\\error_handler.sh" ]; then
        passed=$((passed + 1))
        print_success "P1.1: 错误处理模块已创建"
    else
        print_error "P1.1: 错误处理模块缺失"
    fi

    # P1.2 检查
    checks=$((checks + 1))
    if grep -q "ip_sources=" "D:\\project\\a\\src\\core.sh" 2>/dev/null; then
        passed=$((passed + 1))
        print_success "P1.2: 多源 IP 获取已实现"
    else
        print_error "P1.2: 多源 IP 获取未实现"
    fi

    # P1.3 检查
    checks=$((checks + 1))
    if [ -f "D:\\project\\a\\src\\input_validator.sh" ]; then
        passed=$((passed + 1))
        print_success "P1.3: 输入验证模块已创建"
    else
        print_error "P1.3: 输入验证模块缺失"
    fi

    print_info "完整性: $passed/$checks"

    [ $passed -eq $checks ]
    return $?
}

# 主测试流程
main() {
    echo "=========================================="
    echo "  P1 优化验证测试"
    echo "=========================================="
    echo ""
    echo "测试目标: 验证 P1 级别健壮性改进"
    echo "测试日期: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # 运行所有测试
    run_test "P1.1: 统一错误处理机制" test_error_handler
    run_test "P1.2: 多源 IP 获取容灾" test_multi_source_ip
    run_test "P1.3: 输入验证和过滤" test_input_validation
    run_test "代码质量检查" test_code_quality
    run_test "模块集成测试" test_integration
    run_test "功能完整性检查" test_completeness

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
        echo "P1 级别优化已成功实施："
        echo "  ✓ 统一错误处理机制已实现"
        echo "  ✓ 多源 IP 获取容灾已实现"
        echo "  ✓ 输入验证和过滤已实现"
        echo ""
        echo "新增模块："
        echo "  • error_handler.sh - 错误处理模块"
        echo "  • input_validator.sh - 输入验证模块"
        echo ""
        echo "建议下一步："
        echo "  1. 在测试环境中验证实际功能"
        echo "  2. 集成到主脚本中"
        echo "  3. 进行端到端测试"
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
