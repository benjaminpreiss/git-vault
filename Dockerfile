FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    bash \
    git \
    curl \
    wget \
    tar \
    sed \
    grep \
    botan \
    && rm -rf /var/lib/apt/lists/*

# Set up a non-root user for testing
RUN useradd -m -s /bin/bash testuser && \
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
mkdir -p secrets private
echo "secret-api-key=abc123" > secrets/api.key
echo "database-password=xyz789" > secrets/db.conf
echo "private-note=confidential" > private/notes.txt
echo "Created test files in secrets/ and private/"
echo

# Test 3: Configure git-vault
echo "=== Test 3: Configuring git-vault ==="
cat > .git-vault-dirs << 'DIRS'
secrets
private
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
ls -la secrets/ private/ 2>/dev/null || echo "No directories found"
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

echo "=== All tests completed successfully! ==="
EOF

RUN chmod +x /home/testuser/test-git-vault.sh

# Default command
CMD ["/home/testuser/test-git-vault.sh"]