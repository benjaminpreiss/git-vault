#!/bin/bash

# Test script for git-vault file deletion scenarios
# Tests both lock and unlock operations when files are deleted after patches exist

set -e

echo "=== Git-Vault File Deletion Test Suite ==="
echo "Testing file deletion scenarios with existing patches"
echo "Current directory: $(pwd)"
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
echo "Audio data v1" > media/audio.wav
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

# Test 5: Make some changes and create first patch
echo "=== Test 5: Making changes to create first patch ==="
echo "secret-api-key=def456" > secrets/api.key  # Modified file
echo "new-secret=ghi789" > secrets/new.key      # New file
echo "Document version 2" > documents/readme.txt # Modified file
echo "Binary data v2" > media/image.bin         # Modified file
echo "Changes made for first patch"
echo

# Test 6: Second lock operation (creates first incremental patch)
echo "=== Test 6: Second lock operation (first incremental patch) ==="
./git-vault lock
echo "Second lock completed. Verifying patches exist:"
find .git-vault/data/ -name "*.patch.aes256gcm.enc" | sort
echo

# Test 7: Delete files after patches exist - this is the key test
echo "=== Test 7: Deleting files after patches exist ==="
echo "Files before deletion:"
find secrets documents media -type f | sort
echo
echo "Deleting files:"
rm secrets/db.conf                    # Delete original file
rm secrets/new.key                    # Delete file added in patch
rm documents/config.json              # Delete original file
rm media/audio.wav                    # Delete original file
echo "- Deleted secrets/db.conf (original file)"
echo "- Deleted secrets/new.key (file added in patch)"
echo "- Deleted documents/config.json (original file)"
echo "- Deleted media/audio.wav (original file)"
echo
echo "Files after deletion:"
find secrets documents media -type f 2>/dev/null | sort || echo "Some directories may be empty"
echo

# Test 8: Third lock operation (should handle deletions correctly)
echo "=== Test 8: Third lock operation (handling deletions) ==="
./git-vault lock
echo "Third lock completed. Checking for new patch:"
patch_count=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" | wc -l)
echo "Total patches now: $patch_count"
echo

# Test 9: Verify deletion patch was created
echo "=== Test 9: Verifying deletion patch creation ==="
latest_patch=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" | sort | tail -1)
if [ -n "$latest_patch" ]; then
    echo "✅ Latest patch created: $latest_patch"
    
    # Check if patch contains deletion operations (we can't decrypt here, but we can verify it exists)
    patch_size=$(wc -c < "$latest_patch")
    if [ "$patch_size" -gt 50 ]; then
        echo "✅ Patch has reasonable size: $patch_size bytes"
    else
        echo "❌ Patch size seems too small: $patch_size bytes"
        exit 1
    fi
else
    echo "❌ No patch found after deletions"
    exit 1
fi
echo

# Test 10: Test unlock with deletions (critical test)
echo "=== Test 10: Testing unlock with file deletions ==="
echo "Removing all directories to test full restoration..."
rm -rf secrets documents media
echo "Directories removed. Now unlocking..."
./git-vault unlock
echo "Unlock completed. Verifying file state:"
echo

# Test 11: Verify correct files exist and deleted files are gone
echo "=== Test 11: Verifying deletion handling ==="
echo "Files that should exist:"
expected_files=(
    "secrets/api.key"
    "documents/readme.txt"
    "media/image.bin"
)

echo "Files that should NOT exist (were deleted):"
deleted_files=(
    "secrets/db.conf"
    "secrets/new.key"
    "documents/config.json"
    "media/audio.wav"
)

# Check expected files exist
all_good=true
for file in "${expected_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file exists (correct)"
        echo "   Content: $(cat "$file")"
    else
        echo "❌ $file missing (should exist)"
        all_good=false
    fi
done

# Check deleted files don't exist
for file in "${deleted_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "✅ $file does not exist (correct - was deleted)"
    else
        echo "❌ $file exists (should have been deleted)"
        echo "   Content: $(cat "$file")"
        all_good=false
    fi
done

if [ "$all_good" = true ]; then
    echo "✅ SUCCESS: All file deletions handled correctly"
else
    echo "❌ FAILURE: File deletion handling has issues"
    exit 1
fi
echo

# Test 12: Test adding files after deletions
echo "=== Test 12: Adding files after deletions ==="
echo "replacement-secret=xyz123" > secrets/replacement.key
echo "New document after deletions" > documents/new-doc.txt
echo "New media file" > media/new-media.bin
echo "Added new files after deletions"
echo

# Test 13: Lock with new files after deletions
echo "=== Test 13: Lock operation with new files after deletions ==="
./git-vault lock
echo "Lock completed. Checking patch count:"
final_patch_count=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" | wc -l)
echo "Final patch count: $final_patch_count"
echo

# Test 14: Final unlock test
echo "=== Test 14: Final unlock test with all changes ==="
rm -rf secrets documents media
./git-vault unlock
echo "Final unlock completed. Verifying final state:"
echo

# Test 15: Verify final state
echo "=== Test 15: Verifying final state ==="
echo "All files in final state:"
find secrets documents media -type f 2>/dev/null | sort

final_expected_files=(
    "secrets/api.key"
    "secrets/replacement.key"
    "documents/readme.txt"
    "documents/new-doc.txt"
    "media/image.bin"
    "media/new-media.bin"
)

final_deleted_files=(
    "secrets/db.conf"
    "secrets/new.key"
    "documents/config.json"
    "media/audio.wav"
)

echo
echo "Final verification:"
final_all_good=true
for file in "${final_expected_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file exists"
    else
        echo "❌ $file missing"
        final_all_good=false
    fi
done

for file in "${final_deleted_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "✅ $file correctly deleted"
    else
        echo "❌ $file should not exist"
        final_all_good=false
    fi
done

if [ "$final_all_good" = true ]; then
    echo "✅ SUCCESS: All file operations handled correctly"
else
    echo "❌ FAILURE: Final state verification failed"
    exit 1
fi
echo

echo "=== File Deletion Test Results ==="
echo "✅ Base snapshots created successfully"
echo "✅ Initial patches created successfully"
echo "✅ File deletions after patches handled correctly"
echo "✅ Lock operations with deletions work correctly"
echo "✅ Unlock operations restore correct file state"
echo "✅ Files added after deletions work correctly"
echo "✅ Complex file operation sequences work correctly"
echo
echo "=== All file deletion tests completed successfully! ==="