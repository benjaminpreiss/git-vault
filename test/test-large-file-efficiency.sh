#!/bin/bash

# Test script to verify patch efficiency with large files and minimal changes

set -e

echo "=== Git-Vault Large File Efficiency Test ==="
echo "Testing patch size efficiency with 100MB file and 1-byte change"
echo "Current directory: $(pwd)"
echo

# Test 1: Install git-vault using local files
echo "=== Test 1: Installing git-vault ==="
bash /home/testuser/git-vault-source/setup.sh --dir .git-vault
echo

# Test 2: Create a large test file (100MB)
echo "=== Test 2: Creating large test file (100MB) ==="
mkdir -p bigdata
echo "Creating 100MB file with random data..."
dd if=/dev/urandom of=bigdata/largefile.bin bs=1M count=100 2>/dev/null
echo "Large file created: $(ls -lh bigdata/largefile.bin)"
echo

# Test 3: Configure git-vault
echo "=== Test 3: Configuring git-vault ==="
cat > .git-vault-dirs << 'DIRS'
bigdata
DIRS
echo "Configuration:"
cat .git-vault-dirs
echo

# Test 4: First lock operation (creates base snapshot)
echo "=== Test 4: First lock operation (base snapshot) ==="
./git-vault lock
echo "First lock completed. Checking vault structure:"
find .git-vault/data/ -type f | sort
echo

# Test 5: Check base snapshot size
echo "=== Test 5: Analyzing base snapshot size ==="
base_archive=".git-vault/data/bigdata/base.tar.gz.aes256gcm.enc"
if [ -f "$base_archive" ]; then
    base_size=$(wc -c < "$base_archive")
    echo "Base snapshot size: $base_size bytes ($(echo "scale=2; $base_size/1024/1024" | bc -l) MB)"
else
    echo "❌ Base snapshot not found"
    exit 1
fi
echo

# Test 6: Make minimal change (1 byte)
echo "=== Test 6: Making minimal change (1 byte) ==="
echo "Original file hash: $(sha256sum bigdata/largefile.bin)"
# Change just the first byte
printf '\xFF' | dd of=bigdata/largefile.bin bs=1 count=1 conv=notrunc 2>/dev/null
echo "Modified file hash: $(sha256sum bigdata/largefile.bin)"
echo "Changed only 1 byte in 100MB file"
echo

# Test 7: Second lock operation (should create small patch)
echo "=== Test 7: Second lock operation (incremental patch) ==="
./git-vault lock
echo "Second lock completed. Checking vault structure:"
find .git-vault/data/ -type f | sort
echo

# Test 8: Analyze patch size efficiency
echo "=== Test 8: Analyzing patch size efficiency ==="
patch_archive=".git-vault/data/bigdata/patches/001.patch.aes256gcm.enc"
if [ -f "$patch_archive" ]; then
    patch_size=$(wc -c < "$patch_archive")
    echo "Patch size: $patch_size bytes ($(echo "scale=2; $patch_size/1024/1024" | bc -l) MB)"
    
    # Calculate efficiency
    efficiency_ratio=$(echo "scale=2; $patch_size * 100 / $base_size" | bc -l)
    echo "Patch is $efficiency_ratio% of base snapshot size"
    
    # Expected: patch should be much smaller than base (ideally < 1% for 1-byte change)
    if [ $(echo "$efficiency_ratio < 5.0" | bc -l) -eq 1 ]; then
        echo "✅ EXCELLENT: Patch is very efficient ($efficiency_ratio% of base)"
    elif [ $(echo "$efficiency_ratio < 20.0" | bc -l) -eq 1 ]; then
        echo "✅ GOOD: Patch is reasonably efficient ($efficiency_ratio% of base)"
    elif [ $(echo "$efficiency_ratio < 50.0" | bc -l) -eq 1 ]; then
        echo "⚠️  MODERATE: Patch efficiency could be better ($efficiency_ratio% of base)"
    else
        echo "❌ POOR: Patch is not efficient ($efficiency_ratio% of base)"
        echo "   For a 1-byte change, patch should be much smaller!"
    fi
    
    # Absolute size check
    if [ $patch_size -lt 1048576 ]; then  # Less than 1MB
        echo "✅ Patch size is under 1MB as expected"
    else
        echo "❌ Patch size exceeds 1MB - this indicates the entire file is being stored"
    fi
else
    echo "❌ Patch file not found"
    exit 1
fi
echo

# Test 9: Verify unlock still works correctly
echo "=== Test 9: Testing unlock with large file ==="
rm -rf bigdata
./git-vault unlock
echo "Unlock completed. Verifying restored file:"
if [ -f "bigdata/largefile.bin" ]; then
    restored_size=$(wc -c < "bigdata/largefile.bin")
    echo "Restored file size: $restored_size bytes ($(echo "scale=2; $restored_size/1024/1024" | bc -l) MB)"
    echo "Restored file hash: $(sha256sum bigdata/largefile.bin)"
    
    if [ $restored_size -eq 104857600 ]; then  # 100MB
        echo "✅ File size correctly restored"
    else
        echo "❌ File size incorrect"
        exit 1
    fi
else
    echo "❌ File not restored"
    exit 1
fi
echo

echo "=== Large File Efficiency Test Results ==="
echo "Base snapshot: $(echo "scale=2; $base_size/1024/1024" | bc -l) MB"
echo "Patch size: $(echo "scale=2; $patch_size/1024/1024" | bc -l) MB"
echo "Efficiency: $efficiency_ratio% of base size"
echo
if [ $(echo "$efficiency_ratio < 5.0" | bc -l) -eq 1 ] && [ $patch_size -lt 1048576 ]; then
    echo "✅ SUCCESS: Patch system is highly efficient for large files with small changes"
else
    echo "❌ FAILURE: Patch system needs optimization for large files with small changes"
    echo "   Expected: Patch < 5% of base size and < 1MB absolute size"
    echo "   Actual: Patch = $efficiency_ratio% of base size and $(echo "scale=2; $patch_size/1024/1024" | bc -l) MB"
fi