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
    patch \
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

# Copy test scripts from test directory
COPY --chown=testuser:testuser test/test-git-incremental.sh /home/testuser/test-git-incremental.sh
COPY --chown=testuser:testuser test/test-precommit-hook.sh /home/testuser/test-precommit-hook.sh
COPY --chown=testuser:testuser test/test-state-hash-staging.sh /home/testuser/test-state-hash-staging.sh
COPY --chown=testuser:testuser test/test-large-file-efficiency.sh /home/testuser/test-large-file-efficiency.sh
COPY --chown=testuser:testuser test/test-file-deletion.sh /home/testuser/test-file-deletion.sh
COPY --chown=testuser:testuser test/test-file-addition.sh /home/testuser/test-file-addition.sh
RUN chmod +x /home/testuser/test-git-incremental.sh /home/testuser/test-precommit-hook.sh /home/testuser/test-state-hash-staging.sh /home/testuser/test-large-file-efficiency.sh /home/testuser/test-file-deletion.sh /home/testuser/test-file-addition.sh

# Create comprehensive test runner
COPY --chown=testuser:testuser test/run-all-tests.sh /home/testuser/run-all-tests.sh
RUN chmod +x /home/testuser/run-all-tests.sh

# Default command
CMD ["/home/testuser/run-all-tests.sh"]