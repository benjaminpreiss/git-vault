#!/bin/bash

# Test script to verify that pre-commit hook stages all .git-vault directory contents
# including state.hash files

set -e

echo "=== Git-Vault State Hash Staging Test ==="
echo "Testing that pre-commit hook stages all .git-vault directory contents"
echo

# Create a temporary test directory
TEST_DIR="/tmp/git-vault-test-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "Working in: $TEST_DIR"

# Initialize git repository
git init
git config user.email "test@example.com"
git config user.name "Test User"

# Copy git-vault files to test directory
cp -r /home/testuser/git-vault-source/* .

# Install git-vault in the test repository
bash setup.sh --dir .git-vault

# Create test directories and files
mkdir -p secrets documents
echo "secret-api-key=abc123" > secrets/api.key
echo "database-password=xyz789" > secrets/db.conf
echo "Document version 1" > documents/readme.txt

# Configure git-vault
cat > .git-vault-dirs << 'EOF'
secrets
documents
EOF

echo "=== Test 1: Initial commit - verify state.hash files are created and staged ==="

# Make initial commit
git add .
git commit -m "Initial commit with git-vault"

# Check if state.hash files exist
STATE_HASH_FILES=$(find .git-vault -name "state.hash" 2>/dev/null || true)
if [ -n "$STATE_HASH_FILES" ]; then
    echo "✅ SUCCESS: state.hash files found:"
    echo "$STATE_HASH_FILES"
else
    echo "❌ FAILURE: No state.hash files found"
    exit 1
fi

# Check if state.hash files are tracked by git
TRACKED_STATE_HASH=$(git ls-files | grep "state.hash" || true)
if [ -n "$TRACKED_STATE_HASH" ]; then
    echo "✅ SUCCESS: state.hash files are tracked by git:"
    echo "$TRACKED_STATE_HASH"
else
    echo "❌ FAILURE: state.hash files are not tracked by git"
    echo "Git tracked files in .git-vault:"
    git ls-files | grep ".git-vault" || echo "No .git-vault files tracked"
    exit 1
fi

echo

echo "=== Test 2: Modify vault contents and verify state.hash files are updated and staged ==="

# Modify vault contents
echo "secret-api-key=def456" > secrets/api.key
echo "new-secret=ghi789" > secrets/new.key
echo "Document version 2" > documents/readme.txt

# Get current state.hash content before commit
BEFORE_HASH=""
for hash_file in $STATE_HASH_FILES; do
    if [ -f "$hash_file" ]; then
        BEFORE_HASH="$BEFORE_HASH$(cat "$hash_file")"
    fi
done

# Make commit with changes
git add .
git commit -m "Modified vault contents"

# Get state.hash content after commit
AFTER_HASH=""
for hash_file in $STATE_HASH_FILES; do
    if [ -f "$hash_file" ]; then
        AFTER_HASH="$AFTER_HASH$(cat "$hash_file")"
    fi
done

# Verify state.hash files were updated
if [ "$BEFORE_HASH" != "$AFTER_HASH" ]; then
    echo "✅ SUCCESS: state.hash files were updated after vault changes"
else
    echo "❌ FAILURE: state.hash files were not updated after vault changes"
    exit 1
fi

# Verify updated state.hash files are tracked
UPDATED_TRACKED_STATE_HASH=$(git ls-files | grep "state.hash" || true)
if [ -n "$UPDATED_TRACKED_STATE_HASH" ]; then
    echo "✅ SUCCESS: Updated state.hash files are tracked by git"
else
    echo "❌ FAILURE: Updated state.hash files are not tracked by git"
    exit 1
fi

echo

echo "=== Test 3: Verify all .git-vault directory contents are staged (excluding cache) ==="

# Check that all files in .git-vault are tracked (excluding cache directory)
ALL_VAULT_FILES=$(find .git-vault -type f 2>/dev/null | grep -v "/cache/" | sort)
TRACKED_VAULT_FILES=$(git ls-files | grep "^\.git-vault/" | sort)

echo "All .git-vault files (excluding cache):"
echo "$ALL_VAULT_FILES"
echo
echo "Tracked .git-vault files:"
echo "$TRACKED_VAULT_FILES"
echo

# Compare the lists
MISSING_FILES=""
for file in $ALL_VAULT_FILES; do
    if ! echo "$TRACKED_VAULT_FILES" | grep -q "^$file$"; then
        MISSING_FILES="$MISSING_FILES$file\n"
    fi
done

if [ -z "$MISSING_FILES" ]; then
    echo "✅ SUCCESS: All .git-vault directory contents are tracked by git (cache directory properly excluded)"
else
    echo "❌ FAILURE: Some .git-vault files are not tracked:"
    echo -e "$MISSING_FILES"
    exit 1
fi

# Verify cache directory is properly gitignored
if [ -d ".git-vault/cache" ]; then
    CACHE_FILES=$(find .git-vault/cache -type f 2>/dev/null || true)
    if [ -n "$CACHE_FILES" ]; then
        TRACKED_CACHE_FILES=$(git ls-files | grep "^\.git-vault/cache/" || true)
        if [ -z "$TRACKED_CACHE_FILES" ]; then
            echo "✅ SUCCESS: Cache directory files are properly gitignored"
        else
            echo "❌ FAILURE: Cache directory files are being tracked (should be gitignored):"
            echo "$TRACKED_CACHE_FILES"
            exit 1
        fi
    fi
fi

echo

echo "=== Test 4: Verify pre-commit hook behavior without changes ==="

# Make a commit without vault changes
echo "dummy change" > dummy.txt
git add dummy.txt
git commit -m "Commit without vault changes"

# Verify state.hash files are still tracked and unchanged
FINAL_TRACKED_STATE_HASH=$(git ls-files | grep "state.hash" || true)
if [ -n "$FINAL_TRACKED_STATE_HASH" ]; then
    echo "✅ SUCCESS: state.hash files remain tracked after no-change commit"
else
    echo "❌ FAILURE: state.hash files lost tracking after no-change commit"
    exit 1
fi

echo

# Cleanup
cd /
rm -rf "$TEST_DIR"

echo "=== All state.hash staging tests completed successfully! ==="
echo "The pre-commit hook correctly:"
echo "- Creates and stages state.hash files on initial commit"
echo "- Updates and stages state.hash files when vault contents change"
echo "- Stages all .git-vault directory contents"
echo "- Maintains tracking of all vault files across commits"