# git-vault Manual

## What is git-vault?

git-vault is a secure directory encryption tool for Git repositories that uses AES-256/GCM encryption with incremental storage to protect sensitive directories efficiently. It automatically encrypts specified directories before commits and provides easy decryption when needed.

## Getting Started (Fresh Clone)

When you clone a repository that uses git-vault, follow these steps:

### 1. Set up your encryption key

Create the `.git-vault.env` file with your encryption key:

```bash
echo "GIT_VAULT_PASS=your-256-bit-hex-key" > .git-vault.env
```

**Generate a new key:**

```bash
botan rng --format=hex 32
```

**Important:** The `.git-vault.env` file contains your encryption key and is automatically gitignored. Never commit this file.

### 2. Unlock encrypted directories

Decrypt the protected directories to access their contents:

```bash
./git-vault unlock
```

## Manual Operations

### Lock (Encrypt) Directories

```bash
./git-vault lock
```

### Unlock (Decrypt) Directories

```bash
./git-vault unlock
```

### Check Dependencies

```bash
./git-vault --check-deps
```

## Automatic Operations

The pre-commit hook automatically:

-   Runs `git-vault lock` before each commit
-   Stages encrypted files
-   Prevents commits if encryption fails

This ensures sensitive directories are always encrypted in your Git history.

## File Structure

```
your-repo/
├── .git-vault/                      # git-vault installation
│   ├── locker.sh                   # Main script
│   ├── git_incremental_encrypt.sh  # Encryption engine
│   ├── pre-commit-hook.sh          # Hook script
│   ├── MANUAL.md                   # User documentation (this file)
│   ├── data/                       # Encrypted storage (committed)
│   └── cache/                      # Performance cache (gitignored)
├── git-vault                       # Wrapper script
├── .git-vault-dirs                 # Configuration (committed)
├── .git-vault.env                  # Your encryption key (gitignored)
└── .git/hooks/pre-commit           # Auto-encryption hook
```

## What Gets Committed vs. Gitignored

**Committed to Git:**

-   `.git-vault/` directory (scripts and encrypted data)
-   `.git-vault-dirs` (configuration file)
-   `git-vault` (wrapper script)

**Gitignored (not committed):**

-   `.git-vault.env` (your encryption key)
-   `.git-vault/cache/` (performance cache)
-   Decrypted sensitive directories (when unlocked)

## Configuration

Edit `.git-vault-dirs` to specify directories to encrypt:

```
secrets
private
config/sensitive
```

Directory paths are relative to your Git repository root. Lines starting with `#` are comments.

## Requirements

-   **Bash** ≥3.2.57
-   **Git** (any recent version)
-   **Botan** ≥3.5.0 (cryptography library)
-   Standard Unix tools: tar, find, base64, sed, grep

## Troubleshooting

**Encryption fails:** Verify Botan is installed (`botan version`) and `.git-vault.env` contains a valid 256-bit hex key.

**Permission denied:** Ensure you have write permissions in the repository directory.

**Hook issues:** Check that `./git-vault lock` runs successfully manually.
