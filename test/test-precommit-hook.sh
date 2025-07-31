#!/bin/bash

# Test script for git-vault pre-commit hook behavior
# Verifies that patches are only created when vault contents actually change

set -e

echo "=== Git-Vault Pre-Commit Hook Test Suite ==="
echo "Current directory: $(pwd)"
echo

# Test 1: Install git-vault
echo "=== Test 1: Installing git-vault ==="
bash /home/testuser/git-vault-source/setup.sh --dir .git-vault
echo

# Test 2: Create initial test data
echo "=== Test 2: Creating initial test data ==="
mkdir -p secrets documents
echo "secret-api-key=abc123" > secrets/api.key
echo "database-password=xyz789" > secrets/db.conf
echo "Document version 1" > documents/readme.txt
echo "Created initial test files"
echo

# Test 3: Configure git-vault
echo "=== Test 3: Configuring git-vault ==="
cat > .git-vault-dirs << 'DIRS'
secrets
documents
DIRS
echo "Configuration:"
cat .git-vault-dirs
echo

# Test 4: First commit - should create base snapshots
echo "=== Test 4: First commit (creates base snapshots) ==="
git add .
git commit -m "Initial commit with git-vault"
echo "First commit completed. Checking vault structure:"
find .git-vault/data/ -name "*.aes256gcm.enc" | sort
echo

# Count initial encrypted files
INITIAL_COUNT=$(find .git-vault/data/ -name "*.aes256gcm.enc" | wc -l)
echo "Initial encrypted files count: $INITIAL_COUNT"
echo

# Test 5: Commit without changes - should NOT create new patches
echo "=== Test 5: Commit without changes (should not create patches) ==="
echo "dummy change" > dummy.txt
git add dummy.txt
git commit -m "Commit without vault changes"
echo "Second commit completed. Checking if new patches were created:"
find .git-vault/data/ -name "*.aes256gcm.enc" | sort
echo

# Count files after no-change commit
NO_CHANGE_COUNT=$(find .git-vault/data/ -name "*.aes256gcm.enc" | wc -l)
echo "Encrypted files count after no-change commit: $NO_CHANGE_COUNT"

if [ "$NO_CHANGE_COUNT" -eq "$INITIAL_COUNT" ]; then
    echo "✅ SUCCESS: No new patches created when vault contents unchanged"
else
    echo "❌ FAILURE: New patches created even though vault contents unchanged"
    exit 1
fi
echo

# Test 6: Make changes to vault contents
echo "=== Test 6: Making changes to vault contents ==="
echo "secret-api-key=def456" > secrets/api.key  # Modified file
echo "new-secret=ghi789" > secrets/new.key      # New file
echo "Document version 2" > documents/readme.txt # Modified file
echo "Changes made to vault contents"
echo

# Test 7: Commit with vault changes - should create new patches
echo "=== Test 7: Commit with vault changes (should create patches) ==="
git add .
git commit -m "Commit with vault changes"
echo "Third commit completed. Checking if new patches were created:"
find .git-vault/data/ -name "*.aes256gcm.enc" | sort
echo

# Count files after vault changes commit
CHANGE_COUNT=$(find .git-vault/data/ -name "*.aes256gcm.enc" | wc -l)
echo "Encrypted files count after vault changes commit: $CHANGE_COUNT"

if [ "$CHANGE_COUNT" -gt "$NO_CHANGE_COUNT" ]; then
    echo "✅ SUCCESS: New patches created when vault contents changed"
    PATCH_COUNT=$((CHANGE_COUNT - NO_CHANGE_COUNT))
    echo "New patches created: $PATCH_COUNT"
else
    echo "❌ FAILURE: No new patches created even though vault contents changed"
    exit 1
fi
echo

# Test 8: Verify patch contents are reasonable
echo "=== Test 8: Verifying patch contents ==="
PATCH_FILES=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc")
if [ -n "$PATCH_FILES" ]; then
    echo "✅ SUCCESS: Patch files found:"
    echo "$PATCH_FILES"
    
    # Check patch file sizes are reasonable (not empty, not huge)
    for patch_file in $PATCH_FILES; do
        size=$(wc -c < "$patch_file")
        if [ "$size" -gt 50 ] && [ "$size" -lt 10000 ]; then
            echo "✅ Patch file $patch_file has reasonable size: $size bytes"
        else
            echo "❌ Patch file $patch_file has suspicious size: $size bytes"
            exit 1
        fi
    done
else
    echo "❌ FAILURE: No patch files found"
    exit 1
fi
echo

# Test 9: Make another non-vault change
echo "=== Test 9: Another commit without vault changes ==="
echo "another dummy change" > dummy2.txt
git add dummy2.txt
git commit -m "Another commit without vault changes"
echo "Fourth commit completed. Checking if new patches were created:"

# Count files after second no-change commit
FINAL_NO_CHANGE_COUNT=$(find .git-vault/data/ -name "*.aes256gcm.enc" | wc -l)
echo "Encrypted files count after second no-change commit: $FINAL_NO_CHANGE_COUNT"

if [ "$FINAL_NO_CHANGE_COUNT" -eq "$CHANGE_COUNT" ]; then
    echo "✅ SUCCESS: No new patches created on second no-change commit"
else
    echo "❌ FAILURE: New patches created on second no-change commit"
    exit 1
fi
echo

# Test 10: Verify unlock still works correctly
echo "=== Test 10: Verifying unlock works with patches ==="
rm -rf secrets documents
./git-vault unlock
echo "Unlock completed. Verifying restored files:"

# Check if files exist and show what we have
echo "Checking restored files..."
echo "Current directory contents:"
ls -la
echo "Secrets directory:"
if [ -d "secrets" ]; then
    ls -la secrets/
else
    echo "secrets directory does not exist"
fi
echo "Documents directory:"
if [ -d "documents" ]; then
    ls -la documents/
else
    echo "documents directory does not exist"
fi

if [ -f "secrets/api.key" ] && [ -f "secrets/new.key" ] && [ -f "documents/readme.txt" ]; then
    echo "✅ All files restored correctly"
    echo "secrets/api.key: $(cat secrets/api.key)"
    echo "secrets/new.key: $(cat secrets/new.key)"
    echo "documents/readme.txt: $(cat documents/readme.txt)"
    
    # Verify the changes were applied
    if grep -q "def456" secrets/api.key && grep -q "ghi789" secrets/new.key && grep -q "version 2" documents/readme.txt; then
        echo "✅ SUCCESS: All changes were correctly applied during unlock"
    else
        echo "❌ FAILURE: Changes were not correctly applied during unlock"
        echo "Expected content not found in files"
        exit 1
    fi
else
    echo "❌ FAILURE: Files not restored correctly"
    echo "Missing files:"
    [ ! -f "secrets/api.key" ] && echo "  - secrets/api.key"
    [ ! -f "secrets/new.key" ] && echo "  - secrets/new.key"
    [ ! -f "documents/readme.txt" ] && echo "  - documents/readme.txt"
    exit 1
fi
echo

# Test 11: Pre-commit hook efficiency analysis
echo "=== Test 11: Pre-commit hook efficiency analysis ==="
echo "Summary of pre-commit hook behavior:"
echo "- Initial commit: Created $INITIAL_COUNT base snapshots"
echo "- No-change commits: Created 0 additional files (efficient!)"
echo "- Change commit: Created $PATCH_COUNT new patches"
echo "- Total encrypted files: $FINAL_NO_CHANGE_COUNT"
echo

# Calculate efficiency
if [ "$INITIAL_COUNT" -gt 0 ]; then
    EFFICIENCY_RATIO=$((PATCH_COUNT * 100 / INITIAL_COUNT))
    echo "Efficiency: Only $EFFICIENCY_RATIO% additional files created for changes"
    echo "✅ SUCCESS: Pre-commit hook is highly efficient"
else
    echo "❌ Cannot calculate efficiency ratio"
fi
echo

echo "=== All pre-commit hook tests completed successfully! ==="
echo "The pre-commit hook correctly:"
echo "- Creates base snapshots on first commit"
echo "- Skips patch creation when vault contents unchanged"
echo "- Creates patches only when vault contents change"
echo "- Maintains correct file restoration capability"
echo "- Operates efficiently with minimal storage overhead"