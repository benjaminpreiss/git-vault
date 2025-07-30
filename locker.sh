#!/bin/bash

# Check for quiet mode (used by pre-commit hook)
QUIET_MODE=false
if [ "$1" = "--quiet" ]; then
    QUIET_MODE=true
    shift
fi

# Function to show usage
usage() {
    echo "Usage: $0 [--quiet] <mode>"
    echo "  --quiet: Suppress non-error output (for use in git hooks)"
    echo "  <mode>: Either 'lock' or 'unlock'"
    echo ""
    echo "Note: The encryption key is stored in a .git-vault.env file in the git repository root."
    echo "The .git-vault.env file should contain a line like: GIT_VAULT_PASS=<your-256-bit-key-in-hex>"
    echo "If no .git-vault.env file exists, one will be auto-generated on first lock operation."
    echo ""
    echo "Configuration: Directories to encrypt/decrypt are specified in .git-vault-dirs"
    echo "The .git-vault-dirs file should contain one directory path per line (relative to git root)."
    echo "Lines starting with # are treated as comments and ignored."
    echo ""
    echo "Tip: To generate a suitable 256-bit key, you can use the following command:"
    echo "  botan rng --format=hex 32"
    exit 1
}

# Function for quiet-aware output
log_info() {
    if [ "$QUIET_MODE" = false ]; then
        echo "$1"
    fi
}

log_error() {
    echo "Error: $1" >&2
}

# Check if one argument is provided
if [ $# -ne 1 ]; then
    usage
fi

# Assign argument to variable
MODE="$1"

# Get the directory of the script (cross-platform compatible)
get_script_dir() {
    # Try to get the directory of the script in a portable way
    if [ -n "${BASH_SOURCE:-}" ]; then
        # Bash
        cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
    elif [ -n "${ZSH_VERSION:-}" ]; then
        # Zsh
        cd "$(dirname "${(%):-%x}")" && pwd
    else
        # Fallback for other shells
        cd "$(dirname "$0")" && pwd
    fi
}
SCRIPT_DIR="$(get_script_dir)"

# Find git repository root
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$GIT_ROOT" ]; then
    echo "Error: Not in a git repository or git not available."
    exit 1
fi

# Check if .git-vault-dirs exists, create if missing
CONFIG_FILE="$GIT_ROOT/.git-vault-dirs"
if [ ! -f "$CONFIG_FILE" ]; then
    echo ".git-vault-dirs not found. Creating default configuration..."
    cat > "$CONFIG_FILE" << 'EOF'
# git-vault directories configuration
# Add one directory path per line (relative to git repository root)
# Lines starting with # are comments and will be ignored
#
# Example:
# secrets
# private
# config/sensitive
EOF
    echo "Created .git-vault-dirs with example configuration."
    echo "Add directory paths (one per line) to specify which directories to encrypt."
fi

# Function to generate and save a new key
generate_key() {
    log_info "Generating new encryption key..."
    NEW_KEY=$(botan rng --format=hex 32)
    if [ $? -ne 0 ]; then
        log_error "Failed to generate key. Please ensure Botan is installed."
        exit 1
    fi
    echo "GIT_VAULT_PASS=$NEW_KEY" > "$GIT_ROOT/.git-vault.env"
    log_info "New encryption key generated and saved to .git-vault.env file."
    GIT_VAULT_PASS="$NEW_KEY"
}

# Read the key from the .git-vault.env file or generate if needed
ENV_FILE="$GIT_ROOT/.git-vault.env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    if [ -z "$GIT_VAULT_PASS" ]; then
        log_error "GIT_VAULT_PASS not found in .git-vault.env file."
        if [ "$MODE" = "lock" ]; then
            generate_key
        else
            log_error "Cannot decrypt without existing key. Please run lock operation first or manually set GIT_VAULT_PASS in .git-vault.env file."
            exit 1
        fi
    fi
else
    if [ "$MODE" = "lock" ]; then
        generate_key
    else
        log_error ".git-vault.env file not found. Cannot decrypt without existing key."
        log_error "Please run lock operation first to generate a key, or manually create .git-vault.env file with GIT_VAULT_PASS."
        exit 1
    fi
fi

# Validate the key (hex encoded 256-bit key is 64 characters long)
# Cross-platform regex check
if ! echo "$GIT_VAULT_PASS" | grep -E '^[0-9A-Fa-f]{64}$' >/dev/null 2>&1; then
    log_error "Invalid key in .git-vault.env file. Please provide a 256-bit key in hexadecimal format (64 characters)."
    log_error "Tip: You can generate a suitable key using: botan rng --format=hex 32"
    exit 1
fi

# Ensure .gitignore exists and contains .git-vault.env entry
GITIGNORE_FILE="$GIT_ROOT/.gitignore"
if [ ! -f "$GITIGNORE_FILE" ]; then
    log_info "Creating .gitignore file..."
    echo ".git-vault.env" > "$GITIGNORE_FILE"
    log_info ".gitignore created with .git-vault.env entry."
elif ! grep -q "^\.git-vault\.env$" "$GITIGNORE_FILE"; then
    log_info "Adding .git-vault.env to .gitignore..."
    echo ".git-vault.env" >> "$GITIGNORE_FILE"
    log_info ".git-vault.env entry added to .gitignore."
fi

# Read directories from plain text file using only bash built-ins
read_directories() {
    local config_file="$1"
    local directories=""
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Trim leading and trailing whitespace using bash parameter expansion
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        
        # Skip empty lines and comments (lines starting with #) - cross-platform
        if [ -z "$line" ] || echo "$line" | grep -E '^#' >/dev/null 2>&1; then
            continue
        fi
        
        # Add directory to list (cross-platform newline)
        if [ -z "$directories" ]; then
            directories="$line"
        else
            directories="$directories
$line"
        fi
    done < "$config_file"
    
    echo "$directories"
}

DIRECTORIES=$(read_directories "$CONFIG_FILE")

if [ $? -ne 0 ]; then
    log_error "Failed to read .git-vault-dirs. Please ensure the file exists."
    exit 1
fi

# Add secret directories to .gitignore (encrypted files are now stored in .git-vault/data/)
if [ -n "$DIRECTORIES" ]; then
    echo "$DIRECTORIES" | while IFS= read -r dir; do
        if [ -n "$dir" ]; then
            # Add directory to .gitignore if not already present
            if ! grep -q "^$dir/\*$" "$GITIGNORE_FILE" 2>/dev/null && ! grep -q "^$dir$" "$GITIGNORE_FILE" 2>/dev/null; then
                echo "" >> "$GITIGNORE_FILE"
                echo "# Added by git-vault for $dir" >> "$GITIGNORE_FILE"
                echo "$dir/*" >> "$GITIGNORE_FILE"
                log_info "Added $dir/ to .gitignore."
            fi
        fi
    done
fi

# Change to git repository root
cd "$GIT_ROOT" || { echo "Error: Cannot change to git repository root."; exit 1; }

# Function to lock directories
lock() {
    if [ -z "$DIRECTORIES" ]; then
        log_info "No directories specified in .git-vault-dirs"
        return 0
    fi
    
    echo "$DIRECTORIES" | while IFS= read -r dir; do
        if [ -n "$dir" ]; then
            if [ -d "$dir" ]; then
                log_info "Locking $dir"
                if [ "$QUIET_MODE" = true ]; then
                    "$SCRIPT_DIR/encrypt_decrypt.sh" "$dir" encrypt "$GIT_VAULT_PASS" --quiet
                else
                    "$SCRIPT_DIR/encrypt_decrypt.sh" "$dir" encrypt "$GIT_VAULT_PASS"
                fi
            else
                log_info "Warning: Directory '$dir' not found, skipping."
            fi
        fi
    done
}

# Function to unlock directories
unlock() {
    if [ -z "$DIRECTORIES" ]; then
        log_info "No directories specified in .git-vault-dirs"
        return 0
    fi
    
    echo "$DIRECTORIES" | while IFS= read -r dir; do
        if [ -n "$dir" ]; then
            # Check if encrypted files exist for this directory
            # Use the same path structure as encrypt_decrypt.sh
            BASE_NAME=$(basename "$dir")
            DATA_SUBDIR=".git-vault/data/$(dirname "$dir")"
            
            # Handle root-level directories (no subdirectory)
            if [ "$(dirname "$dir")" = "." ]; then
                ENCRYPTED_ARCHIVE=".git-vault/data/${BASE_NAME}.tar.gz.aes256gcm.enc"
                NONCE_FILE=".git-vault/data/${BASE_NAME}.nonce"
            else
                ENCRYPTED_ARCHIVE="${DATA_SUBDIR}/${BASE_NAME}.tar.gz.aes256gcm.enc"
                NONCE_FILE="${DATA_SUBDIR}/${BASE_NAME}.nonce"
            fi
            
            if [ -f "$ENCRYPTED_ARCHIVE" ] && [ -f "$NONCE_FILE" ]; then
                log_info "Unlocking $dir"
                if [ "$QUIET_MODE" = true ]; then
                    "$SCRIPT_DIR/encrypt_decrypt.sh" "$dir" decrypt "$GIT_VAULT_PASS" --quiet
                else
                    "$SCRIPT_DIR/encrypt_decrypt.sh" "$dir" decrypt "$GIT_VAULT_PASS"
                fi
            else
                log_info "Warning: No encrypted files found for '$dir' (looking for $ENCRYPTED_ARCHIVE and $NONCE_FILE)"
            fi
        fi
    done
}

# Perform the requested operation
case "$MODE" in
    lock)
        lock
        ;;
    unlock)
        unlock
        ;;
    *)
        log_error "Invalid mode. Use 'lock' or 'unlock'."
        usage
        ;;
esac