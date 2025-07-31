#!/bin/bash

# Comprehensive Git-Vault Test Runner
# Executes all test suites in sequence

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

run_test_suite() {
    local test_name="$1"
    local test_script="$2"
    local test_dir="$3"
    
    print_header "$test_name"
    
    # Create clean test directory
    if [ -d "$test_dir" ]; then
        rm -rf "$test_dir"
    fi
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    # Initialize git repository
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"
    
    print_info "Running $test_name in directory: $(pwd)"
    print_info "Test script: $test_script"
    echo
    
    # Run the test
    if bash "$test_script"; then
        print_success "$test_name completed successfully"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_error "$test_name failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
    fi
    
    echo
    cd /home/testuser
}

# Main test execution
main() {
    print_header "Git-Vault Comprehensive Test Suite"
    print_info "Starting all tests..."
    print_info "Test environment: $(uname -a)"
    print_info "Git version: $(git --version)"
    print_info "Botan version: $(botan version)"
    echo
    
    # Test 1: Bash-native incremental encryption system
    run_test_suite \
        "Bash-Native Incremental Encryption Test" \
        "/home/testuser/test-git-incremental.sh" \
        "/home/testuser/test-git-incremental"
    
    # Test 2: Pre-commit hook behavior
    run_test_suite \
        "Pre-Commit Hook Behavior Test" \
        "/home/testuser/test-precommit-hook.sh" \
        "/home/testuser/test-precommit-hook"
    
    # Test 3: State hash staging behavior
    run_test_suite \
        "State Hash Staging Test" \
        "/home/testuser/test-state-hash-staging.sh" \
        "/home/testuser/test-state-hash-staging"
    
    # Test 4: Large file efficiency test
    run_test_suite \
        "Large File Efficiency Test" \
        "/home/testuser/test-large-file-efficiency.sh" \
        "/home/testuser/test-large-file-efficiency"
    
    # Test 5: File deletion scenarios test
    run_test_suite \
        "File Deletion Scenarios Test" \
        "/home/testuser/test-file-deletion.sh" \
        "/home/testuser/test-file-deletion"
    
    # Test 6: File addition scenarios test
    run_test_suite \
        "File Addition Scenarios Test" \
        "/home/testuser/test-file-addition.sh" \
        "/home/testuser/test-file-addition"
    
    # Test 7: Caching system test
    run_test_suite \
        "Caching System Test" \
        "/home/testuser/test-caching-system.sh" \
        "/home/testuser/test-caching-system"
    
    # Test 8: Setup script test
    run_test_suite \
        "Setup Script Test" \
        "/home/testuser/test-setup-script.sh" \
        "/home/testuser/test-setup-script"
    
    # Final results
    print_header "Test Results Summary"
    
    echo -e "Total tests run: $((TESTS_PASSED + TESTS_FAILED))"
    echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
    echo
    
    if [ $TESTS_FAILED -eq 0 ]; then
        print_success "All tests passed! Git-vault is working correctly."
        echo
        print_info "Key achievements verified:"
        echo "  ✅ Bash-native incremental encryption system works correctly"
        echo "  ✅ Pre-commit hook only creates patches when vault contents change"
        echo "  ✅ State.hash files are properly created and staged"
        echo "  ✅ All .git-vault directory contents are auto-committed"
        echo "  ✅ Encryption/decryption maintains data integrity"
        echo "  ✅ Space-efficient storage with incremental patches"
        echo "  ✅ Full unlock/restore functionality works correctly"
        echo "  ✅ File deletion scenarios handled correctly"
        echo "  ✅ File addition scenarios handled correctly"
        echo "  ✅ Large file efficiency optimizations work"
        echo "  ✅ Caching system provides performance improvements"
        echo "  ✅ Setup script properly configures git-vault and gitignore"
        echo
        exit 0
    else
        print_error "Some tests failed:"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo "  ❌ $failed_test"
        done
        echo
        print_error "Please review the test output above for details."
        exit 1
    fi
}

# Cleanup function
cleanup() {
    print_info "Cleaning up test directories..."
    cd /home/testuser
    rm -rf test-git-incremental test-precommit-hook test-state-hash-staging test-large-file-efficiency test-file-deletion test-file-addition test-caching-system test-setup-script 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup EXIT

# Run main function
main "$@"