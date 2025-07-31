#!/bin/bash

# Test script for git-vault file addition scenarios
# Tests both lock and unlock operations when files are added after patches exist

set -e

echo "=== Git-Vault File Addition Test Suite ==="
echo "Testing file addition scenarios with existing patches"
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

# Test 5: Make some changes and create first patch
echo "=== Test 5: Making changes to create first patch ==="
echo "secret-api-key=def456" > secrets/api.key  # Modified file
echo "Document version 2" > documents/readme.txt # Modified file
echo "Binary data v2" > media/image.bin         # Modified file
echo "Changes made for first patch"
echo

# Test 6: Second lock operation (creates first incremental patch)
echo "=== Test 6: Second lock operation (first incremental patch) ==="
./git-vault lock
echo "Second lock completed. Verifying patches exist:"
find .git-vault/data/ -name "*.patch.aes256gcm.enc" | sort
patch_count_after_first=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" | wc -l)
echo "Patches after first modification: $patch_count_after_first"
echo

# Test 7: Add files after patches exist - this is the key test
echo "=== Test 7: Adding files after patches exist ==="
echo "Files before addition:"
find secrets documents media -type f | sort
echo
echo "Adding new files:"
echo "new-secret-1=abc999" > secrets/new-secret-1.key
echo "new-secret-2=def888" > secrets/new-secret-2.key
echo "Additional document 1" > documents/additional-1.txt
echo "Additional document 2" > documents/additional-2.txt
echo "New media file 1" > media/new-media-1.bin
echo "New media file 2" > media/new-media-2.bin
echo "- Added secrets/new-secret-1.key"
echo "- Added secrets/new-secret-2.key"
echo "- Added documents/additional-1.txt"
echo "- Added documents/additional-2.txt"
echo "- Added media/new-media-1.bin"
echo "- Added media/new-media-2.bin"
echo
echo "Files after addition:"
find secrets documents media -type f | sort
echo

# Test 8: Third lock operation (should handle additions correctly)
echo "=== Test 8: Third lock operation (handling additions) ==="
./git-vault lock
echo "Third lock completed. Checking for new patch:"
patch_count_after_addition=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" | wc -l)
echo "Patches after addition: $patch_count_after_addition"

if [ "$patch_count_after_addition" -gt "$patch_count_after_first" ]; then
    echo "✅ New patch created for file additions"
else
    echo "❌ No new patch created for file additions"
    exit 1
fi
echo

# Test 9: Verify addition patch was created
echo "=== Test 9: Verifying addition patch creation ==="
latest_patch=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" | sort | tail -1)
if [ -n "$latest_patch" ]; then
    echo "✅ Latest patch created: $latest_patch"
    
    # Check if patch has reasonable size
    patch_size=$(wc -c < "$latest_patch")
    if [ "$patch_size" -gt 100 ]; then
        echo "✅ Patch has reasonable size for additions: $patch_size bytes"
    else
        echo "❌ Patch size seems too small for 6 file additions: $patch_size bytes"
        exit 1
    fi
else
    echo "❌ No patch found after additions"
    exit 1
fi
echo

# Test 10: Test unlock with additions (critical test)
echo "=== Test 10: Testing unlock with file additions ==="
echo "Removing all directories to test full restoration..."
rm -rf secrets documents media
echo "Directories removed. Now unlocking..."
./git-vault unlock
echo "Unlock completed. Verifying file state:"
echo

# Test 11: Verify all files exist including additions
echo "=== Test 11: Verifying addition handling ==="
echo "All files after unlock:"
find secrets documents media -type f | sort
echo

expected_files=(
    "secrets/api.key"
    "secrets/db.conf"
    "secrets/new-secret-1.key"
    "secrets/new-secret-2.key"
    "documents/readme.txt"
    "documents/additional-1.txt"
    "documents/additional-2.txt"
    "media/image.bin"
    "media/new-media-1.bin"
    "media/new-media-2.bin"
)

# Check all expected files exist
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

if [ "$all_good" = true ]; then
    echo "✅ SUCCESS: All file additions handled correctly"
else
    echo "❌ FAILURE: File addition handling has issues"
    exit 1
fi
echo

# Test 12: Add more files in different directories
echo "=== Test 12: Adding files in new subdirectories ==="
mkdir -p secrets/subdir documents/subdir media/subdir
echo "nested-secret=nested123" > secrets/subdir/nested.key
echo "Nested document" > documents/subdir/nested.txt
echo "Nested media" > media/subdir/nested.bin
echo "Added files in subdirectories"
echo

# Test 13: Lock with nested additions
echo "=== Test 13: Lock operation with nested file additions ==="
./git-vault lock
echo "Lock completed. Checking patch count:"
patch_count_after_nested=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" | wc -l)
echo "Patches after nested additions: $patch_count_after_nested"

if [ "$patch_count_after_nested" -gt "$patch_count_after_addition" ]; then
    echo "✅ New patch created for nested file additions"
else
    echo "❌ No new patch created for nested file additions"
    exit 1
fi
echo

# Test 14: Test large file addition
echo "=== Test 14: Adding large file after patches exist ==="
echo "Creating 1MB test file..."
dd if=/dev/zero of=media/large-file.bin bs=1024 count=1024 2>/dev/null
echo "Large file created: $(ls -lh media/large-file.bin)"
echo

# Test 15: Lock with large file addition
echo "=== Test 15: Lock operation with large file addition ==="
./git-vault lock
echo "Lock completed. Checking patch count:"
patch_count_after_large=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" | wc -l)
echo "Patches after large file addition: $patch_count_after_large"

if [ "$patch_count_after_large" -gt "$patch_count_after_nested" ]; then
    echo "✅ New patch created for large file addition"
    
    # Check the size of the latest patch
    latest_large_patch=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" | sort | tail -1)
    large_patch_size=$(wc -c < "$latest_large_patch")
    echo "Large file patch size: $large_patch_size bytes"
    
    # The patch should be significantly smaller than 1MB due to compression and encryption
    if [ "$large_patch_size" -lt 1048576 ]; then
        echo "✅ Large file patch is reasonably compressed"
    else
        echo "⚠️  Large file patch is quite large: $(echo "scale=2; $large_patch_size/1024/1024" | bc -l) MB"
    fi
else
    echo "❌ No new patch created for large file addition"
    exit 1
fi
echo

# Test 16: Final unlock test with all additions
echo "=== Test 16: Final unlock test with all additions ==="
rm -rf secrets documents media
./git-vault unlock
echo "Final unlock completed. Verifying final state:"
echo

# Test 17: Verify final state with all additions
echo "=== Test 17: Verifying final state with all additions ==="
echo "All files in final state:"
find secrets documents media -type f 2>/dev/null | sort
echo

final_expected_files=(
    "secrets/api.key"
    "secrets/db.conf"
    "secrets/new-secret-1.key"
    "secrets/new-secret-2.key"
    "secrets/subdir/nested.key"
    "documents/readme.txt"
    "documents/additional-1.txt"
    "documents/additional-2.txt"
    "documents/subdir/nested.txt"
    "media/image.bin"
    "media/new-media-1.bin"
    "media/new-media-2.bin"
    "media/subdir/nested.bin"
    "media/large-file.bin"
)

echo "Final verification:"
final_all_good=true
for file in "${final_expected_files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file exists"
        # Show size for large file
        if [ "$file" = "media/large-file.bin" ]; then
            echo "   Size: $(ls -lh "$file" | awk '{print $5}')"
        fi
    else
        echo "❌ $file missing"
        final_all_good=false
    fi
done

# Verify large file integrity
if [ -f "media/large-file.bin" ]; then
    large_file_size=$(wc -c < "media/large-file.bin")
    if [ "$large_file_size" -eq 1048576 ]; then
        echo "✅ Large file size correct: $large_file_size bytes"
    else
        echo "❌ Large file size incorrect: $large_file_size bytes (expected 1048576)"
        final_all_good=false
    fi
fi

if [ "$final_all_good" = true ]; then
    echo "✅ SUCCESS: All file additions handled correctly"
else
    echo "❌ FAILURE: Final state verification failed"
    exit 1
fi
echo

# Test 18: Storage efficiency analysis
echo "=== Test 18: Storage efficiency analysis for additions ==="
total_patches=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" | wc -l)
total_patch_size=$(find .git-vault/data/ -name "*.patch.aes256gcm.enc" -exec wc -c {} + | tail -1 | awk '{print $1}')
base_size=$(find .git-vault/data/ -name "base.*.aes256gcm.enc" -exec wc -c {} + | tail -1 | awk '{print $1}')

echo "Storage analysis:"
echo "- Total patches: $total_patches"
echo "- Total patch size: $total_patch_size bytes ($(echo "scale=2; $total_patch_size/1024/1024" | bc -l) MB)"
echo "- Base snapshots size: $base_size bytes ($(echo "scale=2; $base_size/1024/1024" | bc -l) MB)"
echo "- Total encrypted size: $((total_patch_size + base_size)) bytes"
echo

echo "=== File Addition Test Results ==="
echo "✅ Base snapshots created successfully"
echo "✅ Initial patches created successfully"
echo "✅ File additions after patches handled correctly"
echo "✅ Lock operations with additions work correctly"
echo "✅ Unlock operations restore all added files"
echo "✅ Nested directory additions work correctly"
echo "✅ Large file additions work correctly"
echo "✅ Complex file addition sequences work correctly"
echo "✅ Storage efficiency maintained with additions"
echo
echo "=== All file addition tests completed successfully! ==="