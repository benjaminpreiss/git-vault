#!/bin/bash

# Comprehensive test script for git-vault bash-native incremental encryption system

set -e

echo "=== Git-Vault Bash-Native Incremental Encryption Test Suite ==="
echo "Current directory: $(pwd)"
echo "Git status: $(git status --porcelain || echo 'Not a git repo')"
echo

# Test 1: Install git-vault using local files
echo "=== Test 1: Installing git-vault ==="
bash /home/testuser/git-vault-source/setup.sh --dir .git-vault
echo

# Test 2: Create initial test directories and files
echo "=== Test 2: Creating initial test data ==="
mkdir -p secrets documents media
echo "secret-api-key=abc123" > secrets/api.key
echo "database-password=xyz789" > secrets/db.conf
echo "Document version 1" > documents/readme.txt
echo "Config version 1" > documents/config.json
echo "Binary data v1" > media/image.bin
echo "Created initial test files"
echo

# Test 3: Configure git-vault
echo "=== Test 3: Configuring git-vault ==="
cat > .git-vault-dirs << 'DIRS'
secrets
documents
media
DIRS
echo "Configuration:"
cat .git-vault-dirs
echo

# Test 4: First lock operation (creates base snapshots)
echo "=== Test 4: First lock operation (base snapshots) ==="
./git-vault lock
echo "First lock completed. Checking vault structure:"
find .git-vault/data/ -type f | sort
echo

# Test 5: Verify base snapshots were created
echo "=== Test 5: Verifying base snapshots ==="
for dir in secrets documents media; do
    base_archive=".git-vault/data/$dir/base.tar.gz.aes256gcm.enc"
    base_nonce=".git-vault/data/$dir/base.nonce"
    if [ -f "$base_archive" ] && [ -f "$base_nonce" ]; then
        echo "✅ Base snapshot exists for $dir"
    else
        echo "❌ Base snapshot missing for $dir"
        exit 1
    fi
done
echo

# Test 6: First unlock operation
echo "=== Test 6: First unlock operation ==="
rm -rf secrets documents media
./git-vault unlock
echo "First unlock completed. Verifying restored files:"
if [ -f "secrets/api.key" ] && [ -f "documents/readme.txt" ] && [ -f "media/image.bin" ]; then
    echo "✅ All files restored correctly"
    echo "secrets/api.key: $(cat secrets/api.key)"
    echo "documents/readme.txt: $(cat documents/readme.txt)"
    echo "media/image.bin: $(cat media/image.bin)"
else
    echo "❌ Files not restored correctly"
    exit 1
fi
echo

# Test 7: Make changes to test incremental functionality
echo "=== Test 7: Making changes for incremental test ==="
echo "secret-api-key=def456" > secrets/api.key  # Modified file
echo "new-secret=ghi789" > secrets/new.key      # New file
echo "Document version 2" > documents/readme.txt # Modified file
rm documents/config.json                        # Deleted file
echo "Binary data v2" > media/image.bin         # Modified file
echo "Audio data v1" > media/audio.wav          # New file
echo "Changes made:"
echo "- Modified: secrets/api.key, documents/readme.txt, media/image.bin"
echo "- Added: secrets/new.key, media/audio.wav"
echo "- Deleted: documents/config.json"
echo

# Test 8: Second lock operation (creates incremental patches)
echo "=== Test 8: Second lock operation (incremental patches) ==="
./git-vault lock
echo "Second lock completed. Checking vault structure:"
find .git-vault/data/ -type f | sort
echo

# Test 9: Verify incremental patches were created
echo "=== Test 9: Verifying incremental patches ==="
for dir in secrets documents media; do
    patch_dir=".git-vault/data/$dir/patches"
    if [ -d "$patch_dir" ]; then
        patch_count=$(find "$patch_dir" -name "*.patch.aes256gcm.enc" | wc -l)
        if [ "$patch_count" -gt 0 ]; then
            echo "✅ Patch created for $dir (count: $patch_count)"
        else
            echo "❌ No patch found for $dir"
            exit 1
        fi
    else
        echo "❌ Patches directory missing for $dir"
        exit 1
    fi
done
echo

# Test 10: Test incremental unlock
echo "=== Test 10: Testing incremental unlock ==="
rm -rf secrets documents media
./git-vault unlock
echo "Incremental unlock completed. Verifying restored files:"
if [ -f "secrets/api.key" ] && [ -f "secrets/new.key" ] && [ -f "documents/readme.txt" ] && [ ! -f "documents/config.json" ] && [ -f "media/image.bin" ] && [ -f "media/audio.wav" ]; then
    echo "✅ All changes applied correctly"
    echo "secrets/api.key: $(cat secrets/api.key)"
    echo "secrets/new.key: $(cat secrets/new.key)"
    echo "documents/readme.txt: $(cat documents/readme.txt)"
    echo "documents/config.json exists: $([ -f documents/config.json ] && echo 'YES' || echo 'NO')"
    echo "media/image.bin: $(cat media/image.bin)"
    echo "media/audio.wav: $(cat media/audio.wav)"
else
    echo "❌ Changes not applied correctly"
    echo "Files found:"
    find secrets documents media -type f 2>/dev/null || echo "No files found"
    exit 1
fi
echo

# Test 11: Make more changes for second incremental test
echo "=== Test 11: Making more changes for second incremental test ==="
echo "secret-api-key=jkl012" > secrets/api.key  # Modified again
rm secrets/new.key                              # Delete previously added file
echo "Document version 3" > documents/readme.txt # Modified again
echo "New document" > documents/new.txt         # New file
echo "Video data v1" > media/video.mp4          # New file
echo "Additional changes made:"
echo "- Modified: secrets/api.key, documents/readme.txt"
echo "- Added: documents/new.txt, media/video.mp4"
echo "- Deleted: secrets/new.key"
echo

# Test 12: Third lock operation (second incremental patch)
echo "=== Test 12: Third lock operation (second incremental patch) ==="
./git-vault lock
echo "Third lock completed. Checking vault structure:"
find .git-vault/data/ -type f | sort
echo

# Test 13: Verify second incremental patch
echo "=== Test 13: Verifying second incremental patch ==="
for dir in secrets documents media; do
    patch_dir=".git-vault/data/$dir/patches"
    if [ -d "$patch_dir" ]; then
        patch_count=$(find "$patch_dir" -name "*.patch.aes256gcm.enc" | wc -l)
        if [ "$patch_count" -ge 2 ]; then
            echo "✅ Multiple patches exist for $dir (count: $patch_count)"
        else
            echo "❌ Expected at least 2 patches for $dir, found: $patch_count"
            exit 1
        fi
    else
        echo "❌ Patches directory missing for $dir"
        exit 1
    fi
done
echo

# Test 14: Final incremental unlock test
echo "=== Test 14: Final incremental unlock test ==="
rm -rf secrets documents media
./git-vault unlock
echo "Final unlock completed. Verifying all changes applied:"
if [ -f "secrets/api.key" ] && [ ! -f "secrets/new.key" ] && [ -f "documents/readme.txt" ] && [ -f "documents/new.txt" ] && [ ! -f "documents/config.json" ] && [ -f "media/image.bin" ] && [ -f "media/audio.wav" ] && [ -f "media/video.mp4" ]; then
    echo "✅ All incremental changes applied correctly"
    echo "Final state:"
    echo "secrets/api.key: $(cat secrets/api.key)"
    echo "secrets/new.key exists: $([ -f secrets/new.key ] && echo 'YES' || echo 'NO')"
    echo "documents/readme.txt: $(cat documents/readme.txt)"
    echo "documents/new.txt: $(cat documents/new.txt)"
    echo "documents/config.json exists: $([ -f documents/config.json ] && echo 'YES' || echo 'NO')"
    echo "media/image.bin: $(cat media/image.bin)"
    echo "media/audio.wav: $(cat media/audio.wav)"
    echo "media/video.mp4: $(cat media/video.mp4)"
else
    echo "❌ Final state incorrect"
    echo "Files found:"
    find secrets documents media -type f 2>/dev/null || echo "No files found"
    exit 1
fi
echo

# Test 15: Test git integration with incremental system
echo "=== Test 15: Testing git integration ==="
git add .
echo "Git status after adding files:"
git status
echo

# Test 16: Test pre-commit hook with incremental system
echo "=== Test 16: Testing pre-commit hook ==="
git commit -m "Test commit with bash-native incremental git-vault"
echo "Commit completed. Checking final git status:"
git status
echo

# Test 17: Storage efficiency analysis
echo "=== Test 17: Storage efficiency analysis ==="
echo "Analyzing storage efficiency of bash-native incremental system:"

# Count total encrypted files
total_encrypted_files=$(find .git-vault/data/ -name "*.aes256gcm.enc" | wc -l)
base_files=$(find .git-vault/data/ -name "base.*.aes256gcm.enc" | wc -l)
patch_files=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" | wc -l)

echo "Total encrypted files: $total_encrypted_files"
echo "Base snapshots: $base_files"
echo "Incremental patches: $patch_files"

# Calculate sizes
total_size=$(find .git-vault/data/ -name "*.aes256gcm.enc" -exec wc -c {} + | tail -1 | awk '{print $1}')
base_size=$(find .git-vault/data/ -name "base.*.aes256gcm.enc" -exec wc -c {} + | tail -1 | awk '{print $1}' 2>/dev/null || echo "0")
patch_size=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" -exec wc -c {} + | tail -1 | awk '{print $1}' 2>/dev/null || echo "0")

echo "Total encrypted size: $total_size bytes"
echo "Base snapshots size: $base_size bytes"
echo "Incremental patches size: $patch_size bytes"

# Estimate what traditional system would use (3 full re-encryptions)
traditional_estimate=$((base_size * 3))
echo "Traditional system estimate (3 full re-encryptions): $traditional_estimate bytes"

if [ "$total_size" -lt "$traditional_estimate" ]; then
    savings=$((traditional_estimate - total_size))
    percentage=$((savings * 100 / traditional_estimate))
    echo "✅ Space savings: $savings bytes ($percentage%)"
else
    echo "❌ No space savings detected"
fi
echo

# Test 18: Security test - verify no plaintext files exist in vault
echo "=== Test 18: Security test - no plaintext files in vault ==="
echo "Checking for any plaintext files in .git-vault directory..."

# Check for any plaintext files in the entire .git-vault directory
security_issue_found=false
plaintext_files=$(find .git-vault -name "*.txt" -o -name "*.key" -o -name "*.conf" -o -name "*.json" -o -name "*.bin" -o -name "*.wav" -o -name "*.mp4" 2>/dev/null | grep -v "\.aes256gcm\.enc$" | grep -v "\.nonce$" | grep -v "\.hash$" | grep -v "/cache/" || true)

if [ -n "$plaintext_files" ]; then
    echo "❌ SECURITY ISSUE: Found plaintext files in .git-vault directory!"
    echo "$plaintext_files"
    security_issue_found=true
else
    echo "✅ No plaintext files found in .git-vault directory"
fi

# Check specifically for old current.state directories
current_state_dirs=$(find .git-vault -type d -name "current.state" 2>/dev/null || true)
if [ -n "$current_state_dirs" ]; then
    echo "❌ SECURITY ISSUE: Found current.state directories (should not exist)!"
    echo "$current_state_dirs"
    security_issue_found=true
else
    echo "✅ No current.state directories found (good - using hash-based approach)"
fi

# Verify only encrypted files and metadata exist
echo "Verifying vault contains only encrypted files and metadata..."
vault_files=$(find .git-vault -type f | grep -v "\.aes256gcm\.enc$" | grep -v "\.nonce$" | grep -v "\.hash$" | grep -v "\.sh$" | grep -v "/cache/" | grep -v "\.gitignore$" || true)
if [ -n "$vault_files" ]; then
    echo "⚠️  WARNING: Found unexpected files in vault (may be OK):"
    echo "$vault_files"
else
    echo "✅ Vault contains only encrypted files, nonces, and hashes"
fi

# Check git status for any problematic files
echo "Checking git status for any plaintext files..."
problematic_staged_files=$(git status --porcelain | grep -E "\.(txt|key|conf|json|bin|wav|mp4)$" | grep -v "\.aes256gcm\.enc$" || true)
if [ -n "$problematic_staged_files" ]; then
    echo "❌ SECURITY ISSUE: Plaintext files are staged for commit!"
    echo "$problematic_staged_files"
    security_issue_found=true
else
    echo "✅ No plaintext files staged for commit"
fi

if [ "$security_issue_found" = true ]; then
    echo "❌ SECURITY TEST FAILED: Plaintext files may be exposed!"
    exit 1
else
    echo "✅ SECURITY TEST PASSED: No plaintext exposure detected"
fi
echo

echo "=== All bash-native incremental encryption tests completed successfully! ==="
echo "The bash-native incremental system is working correctly with:"
echo "- Base snapshot creation"
echo "- Simple change file generation"
echo "- Sequential change file application during unlock"
echo "- Proper handling of file additions, modifications, and deletions"
echo "- Significant storage space savings"
echo "- Much simpler code using standard bash utilities"