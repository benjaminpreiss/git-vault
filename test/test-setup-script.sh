#!/bin/bash

# Test script for git-vault setup.sh functionality
# This test verifies that the setup script properly configures git-vault

set -e

echo "================================"
echo "Setup Script Test"
echo "================================"

# Create a temporary test directory
TEST_DIR="/tmp/test-setup-$(date +%s)"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

echo "ℹ️  Starting git-vault setup script tests..."
echo "ℹ️  Test directory: $TEST_DIR"

# Initialize git repository
git init
git config user.name "Test User"
git config user.email "test@example.com"

# Create initial commit
echo "test file" > test.txt
git add test.txt
git commit -m "Initial commit"

echo "ℹ️  Test environment set up complete"

echo "ℹ️  Test 1: Basic setup script execution"

# Run setup script
bash /home/testuser/git-vault-source/setup.sh --dir .git-vault

echo "✅ Setup script executed successfully"

echo "ℹ️  Test 2: Verify installation directory created"

if [ -d ".git-vault" ]; then
    echo "✅ Installation directory .git-vault created"
else
    echo "❌ Installation directory .git-vault not found"
    exit 1
fi

echo "ℹ️  Test 3: Verify required files installed"

required_files=("locker.sh" "git_incremental_encrypt.sh" "pre-commit-hook.sh")
for file in "${required_files[@]}"; do
    if [ -f ".git-vault/$file" ]; then
        echo "✅ Required file $file installed"
    else
        echo "❌ Required file $file not found"
        exit 1
    fi
done

echo "ℹ️  Test 4: Verify .git-vault-dirs configuration file created"

if [ -f ".git-vault-dirs" ]; then
    echo "✅ Configuration file .git-vault-dirs created"
else
    echo "❌ Configuration file .git-vault-dirs not found"
    exit 1
fi

echo "ℹ️  Test 5: Verify .gitignore entries"

if [ -f ".gitignore" ]; then
    echo "✅ .gitignore file exists"
    
    # Check for .git-vault.env entry
    if grep -q "^\.git-vault\.env$" .gitignore; then
        echo "✅ .git-vault.env properly added to .gitignore"
    else
        echo "❌ .git-vault.env not found in .gitignore"
        exit 1
    fi
    
    # Check for cache directory entry
    if grep -q "^\.git-vault/cache/$" .gitignore; then
        echo "✅ .git-vault/cache/ properly added to .gitignore"
    else
        echo "❌ .git-vault/cache/ not found in .gitignore"
        exit 1
    fi
else
    echo "❌ .gitignore file not created"
    exit 1
fi

echo "ℹ️  Test 6: Verify pre-commit hook installation"

if [ -f ".git/hooks/pre-commit" ]; then
    echo "✅ Pre-commit hook installed"
    
    if grep -q "git-vault pre-commit hook" .git/hooks/pre-commit; then
        echo "✅ Git-vault functionality added to pre-commit hook"
    else
        echo "❌ Git-vault functionality not found in pre-commit hook"
        exit 1
    fi
else
    echo "❌ Pre-commit hook not installed"
    exit 1
fi

echo "ℹ️  Test 7: Verify wrapper script creation"

if [ -f "git-vault" ] && [ -x "git-vault" ]; then
    echo "✅ Wrapper script git-vault created and executable"
else
    echo "❌ Wrapper script git-vault not found or not executable"
    exit 1
fi

echo "ℹ️  Test 8: Test with existing .gitignore file"

# Add some content to .gitignore
echo "existing-ignore-entry" >> .gitignore
echo "another-entry" >> .gitignore

# Run setup again to test existing .gitignore handling (pipe 'y' for confirmation)
echo "y" | bash /home/testuser/git-vault-source/setup.sh --dir .git-vault

# Verify existing entries are preserved
if grep -q "existing-ignore-entry" .gitignore && grep -q "another-entry" .gitignore; then
    echo "✅ Existing .gitignore entries preserved"
else
    echo "❌ Existing .gitignore entries not preserved"
    exit 1
fi

# Verify git-vault entries are still present
if grep -q "^\.git-vault\.env$" .gitignore && grep -q "^\.git-vault/cache/$" .gitignore; then
    echo "✅ Git-vault .gitignore entries maintained after re-run"
else
    echo "❌ Git-vault .gitignore entries missing after re-run"
    exit 1
fi

echo "ℹ️  Test 9: Test with configured directories in .git-vault-dirs"

# Add some directories to .git-vault-dirs
echo "secrets" >> .git-vault-dirs
echo "private" >> .git-vault-dirs
echo "config/sensitive" >> .git-vault-dirs

# Run setup again to test directory gitignore handling (pipe 'y' for confirmation)
echo "y" | bash /home/testuser/git-vault-source/setup.sh --dir .git-vault

# Verify directories are added to .gitignore
if grep -q "secrets/\*" .gitignore; then
    echo "✅ secrets/ directory added to .gitignore"
else
    echo "❌ secrets/ directory not found in .gitignore"
    exit 1
fi

if grep -q "private/\*" .gitignore; then
    echo "✅ private/ directory added to .gitignore"
else
    echo "❌ private/ directory not found in .gitignore"
    exit 1
fi

if grep -q "config/sensitive/\*" .gitignore; then
    echo "✅ config/sensitive/ directory added to .gitignore"
else
    echo "❌ config/sensitive/ directory not found in .gitignore"
    exit 1
fi

echo "ℹ️  Test 10: Verify final .gitignore structure"

echo "ℹ️  Final .gitignore contents:"
cat .gitignore

# Count expected entries
expected_entries=(
    "\.git-vault\.env"
    "\.git-vault/cache/"
    "secrets/\*"
    "private/\*"
    "config/sensitive/\*"
)

for entry in "${expected_entries[@]}"; do
    if grep -q "$entry" .gitignore; then
        echo "✅ Expected entry found: $entry"
    else
        echo "❌ Expected entry missing: $entry"
        exit 1
    fi
done

echo "✅ All setup script tests passed!"
echo "ℹ️  Setup script correctly:"
echo "ℹ️  - Installs required files"
echo "ℹ️  - Creates configuration files"
echo "ℹ️  - Sets up .gitignore with cache directory exclusion"
echo "ℹ️  - Installs pre-commit hook"
echo "ℹ️  - Creates wrapper script"
echo "ℹ️  - Handles existing files gracefully"
echo "ℹ️  - Adds configured directories to .gitignore"

echo "ℹ️  Cleaning up test environment..."
cd /
rm -rf "$TEST_DIR"

echo "[SUCCESS] Setup Script Test completed successfully"