#!/bin/bash
# 跨平台兼容性测试脚本
# 用于验证 start_aio_pod.sh 和 stop_aio_pod.sh 在 macOS 和 Linux 上的兼容性

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# 检测操作系统
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macOS"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [[ -f /etc/lsb-release ]] && grep -q Ubuntu /etc/lsb-release; then
            echo "Ubuntu"
        else
            echo "Linux"
        fi
    else
        echo "Unknown"
    fi
}

# 测试命令是否存在
test_command() {
    local cmd=$1
    local required=$2
    
    print_test "检查命令: $cmd"
    
    if command -v "$cmd" &> /dev/null; then
        print_pass "$cmd 可用"
        return 0
    else
        if [[ "$required" == "true" ]]; then
            print_fail "$cmd 不可用 (必需)"
            return 1
        else
            print_info "$cmd 不可用 (可选)"
            return 0
        fi
    fi
}

# 测试 xargs 兼容性
test_xargs_compatibility() {
    print_test "测试 xargs 兼容性"
    
    # 测试空输入
    local result=$(echo "" | xargs echo "test" 2>&1 || true)
    
    if [[ -z "$result" ]] || [[ "$result" == "test" ]]; then
        print_pass "xargs 空输入处理正常"
    else
        print_fail "xargs 空输入处理异常"
        return 1
    fi
    
    # 测试非空输入
    result=$(echo "1 2 3" | xargs echo)
    if [[ "$result" == "1 2 3" ]]; then
        print_pass "xargs 非空输入处理正常"
    else
        print_fail "xargs 非空输入处理异常"
        return 1
    fi
}

# 测试脚本语法
test_script_syntax() {
    local script=$1
    print_test "检查脚本语法: $script"
    
    if bash -n "$script" 2>&1; then
        print_pass "$script 语法正确"
        return 0
    else
        print_fail "$script 语法错误"
        return 1
    fi
}

# 测试进程管理
test_process_management() {
    print_test "测试进程管理功能"
    
    # 启动一个测试进程
    sleep 100 &
    local test_pid=$!
    
    # 测试 kill
    if kill -0 "$test_pid" 2>/dev/null; then
        print_pass "进程存在检测正常"
        kill -TERM "$test_pid" 2>/dev/null || true
        sleep 1
        if ! kill -0 "$test_pid" 2>/dev/null; then
            print_pass "进程终止正常"
        else
            kill -KILL "$test_pid" 2>/dev/null || true
            print_info "需要 KILL 信号才能终止"
        fi
    else
        print_fail "进程检测失败"
        return 1
    fi
}

# 测试 lsof
test_lsof() {
    print_test "测试 lsof 功能"
    
    # 启动一个测试 HTTP 服务器
    python3 -m http.server 19999 > /dev/null 2>&1 &
    local server_pid=$!
    
    sleep 2
    
    # 测试端口检测
    if lsof -i :19999 > /dev/null 2>&1; then
        print_pass "lsof 端口检测正常"
        
        # 测试获取 PID
        local pids=$(lsof -ti:19999 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            print_pass "lsof PID 获取正常"
            echo "$pids" | xargs kill -9 2>/dev/null || true
        else
            print_fail "lsof PID 获取失败"
            kill -9 "$server_pid" 2>/dev/null || true
            return 1
        fi
    else
        print_fail "lsof 端口检测失败"
        kill -9 "$server_pid" 2>/dev/null || true
        return 1
    fi
    
    sleep 1
    
    # 确认清理
    if ! lsof -i :19999 > /dev/null 2>&1; then
        print_pass "端口清理正常"
    else
        print_fail "端口清理失败"
        lsof -ti:19999 | xargs kill -9 2>/dev/null || true
        return 1
    fi
}

# 主测试流程
main() {
    local os_type=$(detect_os)
    echo "=========================================="
    echo "跨平台兼容性测试"
    echo "=========================================="
    echo "操作系统: $os_type"
    echo "Bash 版本: $BASH_VERSION"
    echo "=========================================="
    echo
    
    local failed=0
    
    # 1. 测试必需命令
    print_info "=== 1. 测试必需命令 ==="
    test_command "bash" "true" || ((failed++))
    test_command "lsof" "true" || ((failed++))
    test_command "kill" "true" || ((failed++))
    test_command "curl" "true" || ((failed++))
    test_command "python3" "true" || ((failed++))
    test_command "grep" "true" || ((failed++))
    test_command "xargs" "true" || ((failed++))
    echo
    
    # 2. 测试可选命令
    print_info "=== 2. 测试可选命令 ==="
    test_command "systemctl" "false"
    test_command "nginx" "false"
    test_command "conda" "false"
    test_command "pgrep" "false"
    echo
    
    # 3. 测试 xargs 兼容性
    print_info "=== 3. 测试 xargs 兼容性 ==="
    test_xargs_compatibility || ((failed++))
    echo
    
    # 4. 测试脚本语法
    print_info "=== 4. 测试脚本语法 ==="
    test_script_syntax "start_aio_pod.sh" || ((failed++))
    test_script_syntax "stop_aio_pod.sh" || ((failed++))
    echo
    
    # 5. 测试进程管理
    print_info "=== 5. 测试进程管理 ==="
    test_process_management || ((failed++))
    echo
    
    # 6. 测试 lsof
    print_info "=== 6. 测试 lsof ==="
    test_lsof || ((failed++))
    echo
    
    # 总结
    echo "=========================================="
    if [[ $failed -eq 0 ]]; then
        print_pass "所有测试通过！"
        echo "脚本可以在 $os_type 上正常运行"
    else
        print_fail "有 $failed 个测试失败"
        echo "请检查失败的测试项"
        exit 1
    fi
    echo "=========================================="
}

# 运行测试
main "$@"
