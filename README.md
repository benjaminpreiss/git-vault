# git-vault

A secure directory encryption tool for Git repositories that uses AES-256/GCM encryption to protect sensitive directories.

## Quick Start (One-Liner Installation)

Install git-vault in your repository with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/benjaminpreiss/git-vault/main/install.sh | bash
```

Or specify a custom installation directory:

```bash
curl -fsSL https://raw.githubusercontent.com/benjaminpreiss/git-vault/main/install.sh | bash -s -- --dir my-vault
```

This will:

-   Download git-vault scripts to `.git-vault/` (or your specified directory)
-   Create `.git-vault-dirs` configuration file
-   Set up automatic `.gitignore` entries
-   Install a pre-commit hook for automatic encryption
-   Create a `./git-vault` wrapper script for easy access

## Overview

git-vault allows you to encrypt and decrypt specific directories within a Git repository using a configuration-based approach. Instead of hardcoding directory paths, you specify which directories to encrypt in a `.git-vault-dirs` configuration file.

## Manual Setup

If you prefer manual installation:

### 1. Download Files

Download the scripts to your preferred directory (default: `.git-vault/`):

-   `locker.sh` - Main encryption/decryption script
-   `encrypt_decrypt.sh` - Core encryption functionality

### 2. Configuration File (Auto-Generated)

The `.git-vault-dirs` configuration file is automatically created in your Git repository root:

```
# git-vault directories configuration
# Add one directory path per line (relative to git repository root)
# Lines starting with # are comments and will be ignored
#
# Example:
# secrets
# private
# config/sensitive
```

Add your directory paths to encrypt (one per line):

```
secrets
private
config/sensitive
```

Directory paths should be relative to your Git repository root. Lines starting with `#` are treated as comments.

### 3. Environment File (Auto-Generated)

The encryption key is automatically generated and stored in `.git-vault.env` in your repository root when you run your first lock operation.

**Important**:

-   The `.git-vault.env` file is automatically added to `.gitignore`
-   Secret directories are automatically added to `.gitignore` to prevent committing unencrypted data
-   Encrypted files (`.nonce` and `.tar.gz.aes256gcm.enc`) are explicitly included in Git via gitignore exceptions
-   Keep your `.git-vault.env` file secure and backed up separately from your repository

**Gitignore Pattern Example:**

```
# Added by git-vault for secrets
secrets/*
!secrets/*.nonce
!secrets/*.tar.gz.aes256gcm.enc
```

## Usage

### Using the Wrapper Script

After installation, use the convenient wrapper:

```bash
./git-vault lock    # Encrypt directories
./git-vault unlock  # Decrypt directories
```

### Direct Script Usage

Or call the scripts directly:

```bash
./.git-vault/locker.sh lock
./.git-vault/locker.sh unlock
```

### Lock (Encrypt) Directories

```bash
./git-vault lock
```

This will:

-   Read directories from `.git-vault-dirs`
-   Encrypt each directory specified in the configuration
-   Create `.tar.gz.aes256gcm.enc` and `.nonce` files for each directory

### Unlock (Decrypt) Directories

```bash
./git-vault unlock
```

This will:

-   Read directories from `.git-vault-dirs`
-   Decrypt each directory using the corresponding encrypted files
-   Restore the original directory contents

## Automatic Pre-Commit Hook

The installation automatically sets up a pre-commit hook that:

-   Runs `git-vault lock` before each commit
-   Stages encrypted files automatically
-   Prevents commits if encryption fails

**Existing Pre-Commit Hooks:**
If you already have a pre-commit hook, git-vault will:

-   Create a backup of your existing hook (`.git/hooks/pre-commit.backup`)
-   Append git-vault functionality to your existing hook
-   Preserve all existing pre-commit functionality

This ensures your sensitive directories are always encrypted before being committed to Git while maintaining compatibility with existing workflows.

## Files Structure

After installation, your repository will contain:

```
your-repo/
├── .git-vault/              # git-vault installation directory
│   ├── locker.sh           # Main script
│   └── encrypt_decrypt.sh  # Core encryption functionality
├── git-vault               # Wrapper script for easy access
├── .git-vault-dirs         # Configuration file
├── .git-vault.env          # Environment file (auto-generated, not committed)
├── .gitignore              # Updated with git-vault entries
└── .git/hooks/pre-commit   # Auto-encryption hook
```

## Security Features

-   **AES-256/GCM encryption** - Industry-standard authenticated encryption
-   **Random nonces** - Each encryption uses a unique 96-bit nonce
-   **Key validation** - Ensures proper 256-bit hexadecimal key format
-   **Git integration** - Automatically finds Git repository root
-   **Configuration-based** - Flexible directory specification via plain text
-   **Automatic gitignore** - Prevents accidental key commits

## Requirements

-   Bash shell
-   Git
-   Botan cryptography library
-   Standard Unix tools (tar, sed, grep, etc.)
-   curl or wget (for installation)

## Example Workflow

1. **Install**: Run the one-liner installation command
2. **Configure**: Edit `.git-vault-dirs` to specify directories to encrypt
3. **Encrypt**: Run `./git-vault lock` to encrypt directories
4. **Commit**: Git commits will automatically encrypt directories via pre-commit hook
5. **Decrypt**: Run `./git-vault unlock` when you need to work with decrypted files

## Advanced Usage

### Custom Installation Directory

```bash
curl -fsSL https://raw.githubusercontent.com/benjaminpreiss/git-vault/main/install.sh | bash -s -- --dir custom-vault-dir
```

### Manual Key Management

If you need to manually manage your encryption key:

```bash
# Generate a new key
botan rng --format=hex 32

# Add to .git-vault.env
echo "GIT_VAULT_PASS=your-generated-key" > .git-vault.env
```

### Disable Pre-Commit Hook

To temporarily disable automatic encryption:

```bash
chmod -x .git/hooks/pre-commit
```

Re-enable with:

```bash
chmod +x .git/hooks/pre-commit
```

## Notes

-   Encrypted files are stored in the same location as the original directories
-   Original directories are replaced with their encrypted counterparts during locking
-   The tool works from the Git repository root, regardless of where scripts are located
-   Directory paths in `.git-vault-dirs` are always relative to the Git repository root
-   The pre-commit hook ensures you never accidentally commit unencrypted sensitive data

## Troubleshooting

### Installation Issues

If the one-liner installation fails:

1. Ensure you're in a Git repository
2. Check that curl or wget is available
3. Verify internet connectivity
4. Try manual installation instead

### Encryption Issues

If encryption fails:

1. Verify Botan is installed: `botan version`
2. Check that directories in `.git-vault-dirs` exist
3. Ensure you have write permissions in the repository
4. Check `.git-vault.env` file exists and contains valid key

### Pre-Commit Hook Issues

If commits are being blocked:

1. Check that `./git-vault lock` runs successfully
2. Verify all directories in `.git-vault-dirs` exist
3. Temporarily disable hook if needed: `chmod -x .git/hooks/pre-commit`

**Existing Hook Conflicts:**

If you have issues with existing pre-commit hooks:

1. Check if backup was created: `ls -la .git/hooks/pre-commit.backup`
2. Restore original hook: `mv .git/hooks/pre-commit.backup .git/hooks/pre-commit`
3. Manually integrate git-vault by adding the encryption call to your existing hook
4. Re-run setup to append git-vault functionality again

**Manual Integration:**
Add this to your existing pre-commit hook:

```bash
# git-vault integration
"$(git rev-parse --show-toplevel)/.git-vault/locker.sh" lock || exit 1
```

## Testing with Docker

git-vault includes a comprehensive Docker testing environment for safe testing and development.

### Quick Test

Run the automated test suite:

```bash
./test-docker.sh test
```

### Interactive Testing

Start an interactive testing environment:

```bash
./test-docker.sh interactive
```

### Available Test Commands

```bash
./test-docker.sh test        # Run automated test suite
./test-docker.sh interactive # Start interactive shell
./test-docker.sh build       # Build Docker image only
./test-docker.sh clean       # Clean up Docker resources
./test-docker.sh help        # Show help
```

### Test Environment Details

The Docker test environment includes:

-   **Ubuntu 22.04** base image
-   **All dependencies** pre-installed (bash, git, botan, etc.)
-   **Non-root user** for realistic testing
-   **Isolated environment** safe for testing
-   **Automated test suite** covering all functionality

### Manual Testing Steps

In the interactive environment, you can manually test:

```bash
# 1. Create a test repository
mkdir test-project && cd test-project
git init

# 2. Install git-vault
bash /home/testuser/git-vault-source/setup.sh

# 3. Create test data
mkdir secrets
echo "api-key=secret123" > secrets/config.env

# 4. Configure git-vault
echo "secrets" > .git-vault-dirs

# 5. Test encryption
./git-vault lock

# 6. Test decryption
./git-vault unlock

# 7. Test git integration
git add . && git commit -m "Test commit"
```

### Test Coverage

The automated tests verify:

-   ✅ **Installation process** (setup.sh)
-   ✅ **Configuration creation** (.git-vault-dirs)
-   ✅ **Key generation** (.git-vault.env)
-   ✅ **Directory encryption** (lock operation)
-   ✅ **Directory decryption** (unlock operation)
-   ✅ **Git integration** (gitignore patterns)
-   ✅ **Pre-commit hooks** (automatic encryption)
-   ✅ **File staging** (encrypted files added to git)

### Requirements for Testing

-   Docker
-   Docker Compose
-   Bash (for test script)

### Troubleshooting Tests

If tests fail:

1. **Check Docker**: Ensure Docker daemon is running
2. **Check permissions**: Ensure test-docker.sh is executable
3. **Clean environment**: Run `./test-docker.sh clean` and retry
4. **View logs**: Docker will show detailed error output
