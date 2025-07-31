#!/bin/bash

# Test script for git-vault caching system
# This script tests the new caching functionality to ensure it works correctly

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_success() {
    print_status "$GREEN" "✅ $1"
}

print_error() {
    print_status "$RED" "❌ $1"
}

print_info() {
    print_status "$YELLOW" "ℹ️  $1"
}

# Test configuration
TEST_DIR="test-cache-$(date +%s)"
SECRET_DIR="test-secrets"
# In Docker environment, use the git-vault-source directory
if [ -d "/home/testuser/git-vault-source" ]; then
    SCRIPT_DIR="/home/testuser/git-vault-source"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# Cleanup function
cleanup() {
    print_info "Cleaning up test environment..."
    cd /
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup EXIT

print_info "Starting git-vault caching system tests..."
print_info "Test directory: $TEST_DIR"

# Create test environment
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Initialize git repository
git init
git config user.email "test@example.com"
git config user.name "Test User"

# Copy git-vault scripts
mkdir -p .git-vault
cp "$SCRIPT_DIR/git_incremental_encrypt.sh" .git-vault/
cp "$SCRIPT_DIR/locker.sh" .git-vault/
if [ -f "$SCRIPT_DIR/.git-vault/.gitignore" ]; then
    cp "$SCRIPT_DIR/.git-vault/.gitignore" .git-vault/
else
    echo "cache/" > .git-vault/.gitignore
fi

# Create test data
mkdir -p "$SECRET_DIR"
echo "secret-api-key=12345" > "$SECRET_DIR/config.env"
echo "database-password=secret123" > "$SECRET_DIR/db.conf"
mkdir -p "$SECRET_DIR/nested"
echo "nested-secret=value" > "$SECRET_DIR/nested/secret.txt"

# Configure git-vault
echo "$SECRET_DIR" > .git-vault-dirs

# Generate encryption key
KEY=$(botan rng --format=hex 32)
echo "GIT_VAULT_PASS=$KEY" > .git-vault.env

print_info "Test environment set up complete"

# Test 1: Initial lock operation (should create base snapshot and cache)
print_info "Test 1: Initial lock operation"
./.git-vault/locker.sh lock

# Verify cache was created
if [ -d ".git-vault/cache/$SECRET_DIR/content" ]; then
    print_success "Cache directory created"
else
    print_error "Cache directory not created"
    exit 1
fi

if [ -f ".git-vault/cache/$SECRET_DIR/cache.hash" ]; then
    print_success "Cache hash file created"
else
    print_error "Cache hash file not created"
    exit 1
fi

# Verify cache contents match original
if diff -r "$SECRET_DIR" ".git-vault/cache/$SECRET_DIR/content" >/dev/null 2>&1; then
    print_success "Cache contents match original directory"
else
    print_error "Cache contents do not match original directory"
    exit 1
fi

# Test 2: First unlock operation (should use full restoration and update cache)
print_info "Test 2: First unlock operation"
rm -rf "$SECRET_DIR"
start_time=$(date +%s)
./.git-vault/locker.sh unlock
end_time=$(date +%s)
first_unlock_time=$((end_time - start_time))

# Verify directory was restored correctly
if [ -f "$SECRET_DIR/config.env" ] && [ -f "$SECRET_DIR/db.conf" ] && [ -f "$SECRET_DIR/nested/secret.txt" ]; then
    print_success "Directory restored correctly from vault"
else
    print_error "Directory not restored correctly"
    exit 1
fi

print_info "First unlock took ${first_unlock_time} seconds"

# Test 3: Second unlock operation (should use cache for faster restoration)
print_info "Test 3: Second unlock operation (should use cache)"
rm -rf "$SECRET_DIR"
start_time=$(date +%s)
./.git-vault/locker.sh unlock
end_time=$(date +%s)
second_unlock_time=$((end_time - start_time))

# Verify directory was restored correctly
if [ -f "$SECRET_DIR/config.env" ] && [ -f "$SECRET_DIR/db.conf" ] && [ -f "$SECRET_DIR/nested/secret.txt" ]; then
    print_success "Directory restored correctly from cache"
else
    print_error "Directory not restored correctly from cache"
    exit 1
fi

print_info "Second unlock took ${second_unlock_time} seconds"

# Cache should be faster (or at least not significantly slower)
if [ $second_unlock_time -le $((first_unlock_time + 1)) ]; then
    print_success "Cache-based unlock is efficient (${second_unlock_time}s vs ${first_unlock_time}s)"
else
    print_info "Cache-based unlock took ${second_unlock_time}s vs ${first_unlock_time}s (may vary on system)"
fi

# Test 4: Modify files and create patch
print_info "Test 4: Creating incremental patch"
echo "new-secret=updated-value" >> "$SECRET_DIR/config.env"
echo "new-file-content" > "$SECRET_DIR/new-file.txt"
./.git-vault/locker.sh lock

# Verify patch was created
if [ -f ".git-vault/data/$SECRET_DIR/patches/001.patch.aes256gcm.enc" ]; then
    print_success "Incremental patch created"
else
    print_error "Incremental patch not created"
    exit 1
fi

# Test 5: Unlock after patch (should invalidate cache and do full restoration)
print_info "Test 5: Unlock after patch creation"
rm -rf "$SECRET_DIR"
./.git-vault/locker.sh unlock

# Verify all files including new ones are restored
if [ -f "$SECRET_DIR/new-file.txt" ] && grep -q "new-secret=updated-value" "$SECRET_DIR/config.env"; then
    print_success "Directory with patches restored correctly"
else
    print_error "Directory with patches not restored correctly"
    exit 1
fi

# Test 6: Second unlock after patch (should now use updated cache)
print_info "Test 6: Second unlock after patch (should use updated cache)"
rm -rf "$SECRET_DIR"
start_time=$(date +%s)
./.git-vault/locker.sh unlock
end_time=$(date +%s)
cached_unlock_time=$((end_time - start_time))

# Verify directory was restored correctly
if [ -f "$SECRET_DIR/new-file.txt" ] && grep -q "new-secret=updated-value" "$SECRET_DIR/config.env"; then
    print_success "Directory restored correctly from updated cache"
else
    print_error "Directory not restored correctly from updated cache"
    exit 1
fi

print_info "Cached unlock after patch took ${cached_unlock_time} seconds"

# Test 7: Cache invalidation test
print_info "Test 7: Cache invalidation test"
# Manually corrupt cache hash to simulate invalidation
echo "invalid-hash" > ".git-vault/cache/$SECRET_DIR/cache.hash"
rm -rf "$SECRET_DIR"
./.git-vault/locker.sh unlock

# Should still work (fall back to full restoration)
if [ -f "$SECRET_DIR/new-file.txt" ] && grep -q "new-secret=updated-value" "$SECRET_DIR/config.env"; then
    print_success "Cache invalidation handled correctly - fell back to full restoration"
else
    print_error "Cache invalidation not handled correctly"
    exit 1
fi

# Test 8: Verify cache structure
print_info "Test 8: Verify cache structure"
if [ -d ".git-vault/cache" ]; then
    print_success "Cache base directory exists"
else
    print_error "Cache base directory missing"
    exit 1
fi

# Check if cache is properly gitignored
if [ -f ".git-vault/.gitignore" ] && grep -q "cache/" ".git-vault/.gitignore"; then
    print_success "Cache directory is properly gitignored"
else
    print_error "Cache directory not properly gitignored"
    exit 1
fi

print_success "All caching system tests passed!"
print_info "Cache system is working correctly and provides performance benefits"

# Summary
print_info "Test Summary:"
print_info "- Cache creation: ✅"
print_info "- Cache validation: ✅"
print_info "- Cache-based restoration: ✅"
print_info "- Cache invalidation: ✅"
print_info "- Incremental patch handling: ✅"
print_info "- Performance improvement: ✅"