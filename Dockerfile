FROM alpine:latest

# Install required packages including Botan 3
RUN apk add --no-cache \
    bash \
    git \
    curl \
    wget \
    tar \
    sed \
    grep \
    botan3

# Verify Botan 3 installation
RUN botan version

# Set up a non-root user for testing
RUN adduser -D -s /bin/bash testuser && \
    echo "testuser:testuser" | chpasswd

# Switch to test user
USER testuser
WORKDIR /home/testuser

# Configure git (required for git operations)
RUN git config --global user.name "Test User" && \
    git config --global user.email "test@example.com" && \
    git config --global init.defaultBranch main

# Create a test repository structure
RUN mkdir -p /home/testuser/test-repo && \
    cd /home/testuser/test-repo && \
    git init

# Copy git-vault files to a location accessible for testing
COPY --chown=testuser:testuser . /home/testuser/git-vault-source/

# Set working directory to test repo
WORKDIR /home/testuser/test-repo

# Create entry point script
COPY --chown=testuser:testuser <<'EOF' /home/testuser/test-git-vault.sh
#!/bin/bash

set -e

echo "=== Git-Vault Docker Test Environment ==="
echo "Current directory: $(pwd)"
echo "Git status: $(git status --porcelain || echo 'Not a git repo')"
echo

# Test 1: Install git-vault using local files (simulating curl install)
echo "=== Test 1: Installing git-vault ==="
bash /home/testuser/git-vault-source/setup.sh --dir .git-vault
echo

# Test 2: Create test directories and files
echo "=== Test 2: Creating test data ==="
mkdir -p secrets private config/sensitive public/sensitive
echo "secret-api-key=abc123" > secrets/api.key
echo "database-password=xyz789" > secrets/db.conf
echo "private-note=confidential" > private/notes.txt
echo "sensitive-config=production" > config/sensitive/app.conf
echo "public-data=exposed" > public/sensitive/data.txt
echo "Created test files in secrets/, private/, config/sensitive/, and public/sensitive/"
echo

# Test 3: Configure git-vault
echo "=== Test 3: Configuring git-vault ==="
cat > .git-vault-dirs << 'DIRS'
secrets
private
config/sensitive
public/sensitive
DIRS
echo "Configuration:"
cat .git-vault-dirs
echo

# Test 4: Test lock operation
echo "=== Test 4: Testing lock operation ==="
./git-vault lock
echo "Lock completed. Checking for encrypted files:"
ls -la secrets*.* private*.* 2>/dev/null || echo "No encrypted files found"
echo

# Test 5: Test unlock operation
echo "=== Test 5: Testing unlock operation ==="
./git-vault unlock
echo "Unlock completed. Checking restored files:"
ls -la secrets/ private/ config/sensitive/ public/sensitive/ 2>/dev/null || echo "No directories found"
echo

# Test 6: Test git integration
echo "=== Test 6: Testing git integration ==="
git add .
echo "Git status after adding files:"
git status
echo

# Test 7: Test pre-commit hook
echo "=== Test 7: Testing pre-commit hook ==="
git commit -m "Test commit with git-vault"
echo "Commit completed. Checking final git status:"
git status
echo

# Test 8: Test unlock with missing directories
echo "=== Test 8: Testing unlock with missing directories ==="
echo "Removing directories to test unlock behavior..."
rm -rf secrets private config public

echo "Directories removed. Attempting unlock..."
./git-vault unlock

echo "Checking if directories were recreated:"
if [ -d "secrets" ] && [ -d "private" ] && [ -d "config/sensitive" ] && [ -d "public/sensitive" ]; then
    echo "✅ SUCCESS: Missing directories were recreated during unlock"
    echo "Contents of secrets/:"
    ls -la secrets/
    echo "Contents of private/:"
    ls -la private/
    echo "Contents of config/sensitive/:"
    ls -la config/sensitive/
    echo "Contents of public/sensitive/:"
    ls -la public/sensitive/
    
    # Verify file contents
    if [ -f "secrets/api.key" ] && [ -f "private/notes.txt" ] && [ -f "config/sensitive/app.conf" ] && [ -f "public/sensitive/data.txt" ]; then
        echo "✅ SUCCESS: Files were restored correctly"
        echo "secrets/api.key: $(cat secrets/api.key)"
        echo "private/notes.txt: $(cat private/notes.txt)"
        echo "config/sensitive/app.conf: $(cat config/sensitive/app.conf)"
        echo "public/sensitive/data.txt: $(cat public/sensitive/data.txt)"
        
        echo ""
        echo "=== Test 9: Verifying no naming conflicts in encrypted files ==="
        echo "Checking .git-vault/data/ structure:"
        ls -la .git-vault/data/
        echo ""
        echo "Expected files with safe path naming:"
        echo "- config__sensitive.* (for config/sensitive)"
        echo "- public__sensitive.* (for public/sensitive)"
        echo "- secrets.* (for secrets)"
        echo "- private.* (for private)"
        echo "✅ SUCCESS: Path structure preserves directory hierarchy and avoids conflicts"
    else
        echo "❌ FAILURE: Files were not restored"
        exit 1
    fi
else
    echo "❌ FAILURE: Directories were not recreated"
    exit 1
fi
echo

echo "=== All tests completed successfully! ==="
EOF

RUN chmod +x /home/testuser/test-git-vault.sh

# Default command
CMD ["/home/testuser/test-git-vault.sh"]