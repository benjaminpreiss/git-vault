#!/bin/bash

# Test script to reproduce JSON file corruption issue
# This script tests multiple lock/unlock cycles with JSON files to identify data corruption

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
TEST_DIR="test-json-corruption-$(date +%s)"
SECRET_DIR="json-data"
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

print_info "Starting JSON corruption test..."
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

# Create test JSON data (similar to user's example)
mkdir -p "$SECRET_DIR"
cat > "$SECRET_DIR/artworks.json" << 'EOF'
[
	{
		"id": 1,
		"title": "Still, 2022",
		"description": "135 x 110 cm\nacrylics- and graphite on canvas",
		"alt": "...",
		"imgUrl": "/artworks/putainwtf_kalu.jpg",
		"width": 2234,
		"height": 2779,
		"isNft": false,
		"currency": "EUR",
		"startDate": "2025-07-20T10:00:00Z",
		"endDate": "2025-07-27T18:00:00Z",
		"artist": 1,
		"startPrice": 1000,
		"sort": 1
	},
	{
		"id": 2,
		"title": "ANIMALITY, 2019",
		"description": "80.5 x 100.5 cm\noil on canvas",
		"alt": "...",
		"imgUrl": "/artworks/TiGor-ANIMALITY.jpg",
		"width": 3123,
		"height": 3929,
		"isNft": false,
		"currency": "EUR",
		"startDate": "2025-07-28T14:00:00Z",
		"endDate": "2025-08-04T20:00:00Z",
		"artist": 2,
		"startPrice": 100,
		"sort": 2
	},
	{
		"id": 3,
		"title": "Motivational Quote, 2021",
		"description": "17 x 26 x 9 cm\nglazed stoneware",
		"alt": "...",
		"imgUrl": "/artworks/61995D7E-64BA-4B2A-AB75-DAA07D478644.jpeg",
		"width": 3024,
		"height": 4032,
		"isNft": false,
		"currency": "EUR",
		"startDate": "2025-08-05T12:00:00Z",
		"endDate": "2025-08-12T16:00:00Z",
		"artist": 3,
		"startPrice": 100,
		"sort": 3
	}
]
EOF

# Store original JSON for comparison
cp "$SECRET_DIR/artworks.json" original_artworks.json

# Configure git-vault
echo "$SECRET_DIR" > .git-vault-dirs

# Generate encryption key
KEY=$(botan rng --format=hex 32)
echo "GIT_VAULT_PASS=$KEY" > .git-vault.env

print_info "Test environment set up complete"

# Function to compare JSON files
compare_json() {
    local cycle=$1
    if ! diff -u original_artworks.json "$SECRET_DIR/artworks.json" > /dev/null 2>&1; then
        print_error "JSON corruption detected after cycle $cycle!"
        print_error "Differences found:"
        diff -u original_artworks.json "$SECRET_DIR/artworks.json" || true
        return 1
    else
        print_success "JSON file intact after cycle $cycle"
        return 0
    fi
}

# Test 1: Initial lock operation
print_info "Test 1: Initial lock operation"
./.git-vault/locker.sh lock

# Verify JSON is still intact after lock (lock doesn't remove files)
if [ -f "$SECRET_DIR/artworks.json" ]; then
    print_success "JSON file properly locked (original preserved)"
else
    print_error "JSON file missing after lock - should be preserved"
    exit 1
fi

# Manually remove directory to simulate normal workflow
rm -rf "$SECRET_DIR"

# Test 2: First unlock
print_info "Test 2: First unlock operation"
./.git-vault/locker.sh unlock

# Verify JSON is restored correctly
if [ ! -f "$SECRET_DIR/artworks.json" ]; then
    print_error "JSON file not restored after unlock"
    exit 1
fi

compare_json 1 || exit 1

# Test 3-10: Multiple lock/unlock cycles with modifications
for i in {2..10}; do
    print_info "Test $((i+1)): Lock/unlock cycle $i"
    
    # Make a small modification to the JSON - replace the current startPrice with the new one
    current_price=$(grep -o '"startPrice": [0-9]*' "$SECRET_DIR/artworks.json" | head -1 | grep -o '[0-9]*')
    new_price=$((1000 + i))
    sed -i "s/\"startPrice\": $current_price/\"startPrice\": $new_price/g" "$SECRET_DIR/artworks.json"
    
    # Lock the modified file
    ./.git-vault/locker.sh lock
    
    # Verify file is still there after lock (lock preserves originals)
    if [ ! -f "$SECRET_DIR/artworks.json" ]; then
        print_error "JSON file missing after lock in cycle $i - should be preserved"
        exit 1
    fi
    
    # Manually remove directory to simulate normal workflow
    rm -rf "$SECRET_DIR"
    
    # Unlock the file
    ./.git-vault/locker.sh unlock
    
    # Verify file is restored
    if [ ! -f "$SECRET_DIR/artworks.json" ]; then
        print_error "JSON file not restored after unlock in cycle $i"
        exit 1
    fi
    
    # Check if the modification is preserved
    if ! grep -q "\"startPrice\": $((1000 + i))" "$SECRET_DIR/artworks.json"; then
        print_error "JSON modification lost in cycle $i"
        print_error "Expected startPrice: $((1000 + i))"
        print_error "Actual content:"
        cat "$SECRET_DIR/artworks.json"
        exit 1
    else
        print_success "JSON modification preserved in cycle $i"
    fi
done

# Test 11: Cache deletion test after 2nd patch
print_info "Test 11: Cache deletion test after 2nd patch"

# First, create a 2nd patch by modifying the file again
current_price=$(grep -o '"startPrice": [0-9]*' "$SECRET_DIR/artworks.json" | head -1 | grep -o '[0-9]*')
new_price=$((current_price + 1))
sed -i "s/\"startPrice\": $current_price/\"startPrice\": $new_price/g" "$SECRET_DIR/artworks.json"

# Lock to create the 2nd patch
./.git-vault/locker.sh lock

# Verify file is still there after lock
if [ ! -f "$SECRET_DIR/artworks.json" ]; then
    print_error "JSON file missing after lock - should be preserved"
    exit 1
fi

# Remove directory to simulate normal workflow
rm -rf "$SECRET_DIR"

# Delete the cache to force full restoration from vault
print_info "Deleting cache to test full restoration from vault..."
rm -rf .git-vault/cache/

# Unlock the file (should fall back to full restoration)
./.git-vault/locker.sh unlock

# Verify file is restored correctly
if [ ! -f "$SECRET_DIR/artworks.json" ]; then
    print_error "JSON file not restored after unlock with deleted cache"
    exit 1
fi

# Check if the modification is preserved (should have the new price)
if ! grep -q "\"startPrice\": $new_price" "$SECRET_DIR/artworks.json"; then
    print_error "JSON modification lost after cache deletion and unlock"
    print_error "Expected startPrice: $new_price"
    print_error "Actual content:"
    cat "$SECRET_DIR/artworks.json"
    exit 1
else
    print_success "JSON modification preserved after cache deletion and full restoration"
fi

# Test 12: Final integrity check
print_info "Test 12: Final integrity check"
print_info "Final JSON content:"
echo "--- START JSON ---"
cat "$SECRET_DIR/artworks.json"
echo "--- END JSON ---"

# Verify the final state has the last modification (should be 1011 after the cache deletion test)
current_final_price=$(grep -o '"startPrice": [0-9]*' "$SECRET_DIR/artworks.json" | head -1 | grep -o '[0-9]*')
if [ "$current_final_price" -lt 1011 ]; then
    print_error "Final JSON state is incorrect - expected at least 1011, got $current_final_price"
    exit 1
else
    print_success "Final JSON state is correct (startPrice: $current_final_price)"
fi

# Test 13: Check file size consistency
print_info "Test 13: Check file size consistency"
original_size=$(wc -c < original_artworks.json)
final_size=$(wc -c < "$SECRET_DIR/artworks.json")

print_info "Original file size: $original_size bytes"
print_info "Final file size: $final_size bytes"

# The final file should be slightly larger due to the price change
if [ "$final_size" -lt "$original_size" ]; then
    print_error "Final file is smaller than original - possible data loss"
    exit 1
else
    print_success "File size is consistent"
fi

print_success "All JSON corruption tests passed!"
print_info "No data corruption detected in 11 lock/unlock cycles including cache deletion test"