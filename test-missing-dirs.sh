#!/bin/bash

# Test script to verify unlock behavior with missing directories

set -e

echo "=== Testing unlock behavior with missing directories ==="

# Clean up any existing test
rm -rf test-missing-dirs-repo
mkdir test-missing-dirs-repo
cd test-missing-dirs-repo

# Initialize git repo
git init
git config user.name "Test User"
git config user.email "test@example.com"

# Install git-vault
../setup.sh

# Create test directories and files
mkdir -p secrets private
echo "secret api key" > secrets/api.key
echo "private notes" > private/notes.txt

# Configure git-vault
echo "secrets" > .git-vault-dirs
echo "private" >> .git-vault-dirs

echo "Created test directories:"
ls -la secrets/ private/

# Lock the directories
echo "Locking directories..."
./git-vault lock

echo "Encrypted files created:"
ls -la .git-vault/data/

# Remove the original directories to simulate missing directories
echo "Removing original directories to simulate missing directories..."
rm -rf secrets private

echo "Directories removed. Current state:"
ls -la | grep -E "(secrets|private)" || echo "No secrets or private directories found (as expected)"

# Now try to unlock - this should recreate the directories
echo "Unlocking directories (should recreate missing directories)..."
./git-vault unlock

echo "After unlock, checking if directories were recreated:"
if [ -d "secrets" ] && [ -d "private" ]; then
    echo "✅ SUCCESS: Directories were recreated"
    echo "Contents of secrets/:"
    ls -la secrets/
    echo "Contents of private/:"
    ls -la private/
    
    # Verify file contents
    if [ -f "secrets/api.key" ] && [ -f "private/notes.txt" ]; then
        echo "✅ SUCCESS: Files were restored correctly"
        echo "secrets/api.key: $(cat secrets/api.key)"
        echo "private/notes.txt: $(cat private/notes.txt)"
    else
        echo "❌ FAILURE: Files were not restored"
        exit 1
    fi
else
    echo "❌ FAILURE: Directories were not recreated"
    exit 1
fi

# Clean up
cd ..
rm -rf test-missing-dirs-repo

echo "✅ All tests passed! Unlock correctly recreates missing directories."