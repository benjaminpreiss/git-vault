#!/bin/bash

# Bash-native incremental encryption script for git-vault
# Uses standard diff to create patches and simple bash operations to restore changes

# Check for quiet mode
QUIET_MODE=false
if [ "$4" = "--quiet" ] || [ "$5" = "--quiet" ]; then
    QUIET_MODE=true
fi

# Function to show usage
usage() {
    echo "Usage: $0 <directory> <operation> <key> [<file_path>] [--quiet]"
    echo "  <directory>: The directory to process (can be relative to git repo root)"
    echo "  <operation>: Either 'lock' or 'unlock'"
    echo "  <key>: 256-bit key in hexadecimal format (64 characters)"
    echo "  [<file_path>]: Optional path to encrypted files (default: .git-vault/data/)"
    echo "  [--quiet]: Suppress non-error output"
    echo ""
    echo "This script implements incremental encryption using git diff patches."
    echo "Only changed files are re-encrypted, dramatically reducing repository growth."
}

# Function for quiet-aware output
log_info() {
    if [ "$QUIET_MODE" = false ]; then
        echo "$1"
    fi
}

log_debug() {
    if [ "$QUIET_MODE" = false ]; then
        echo "$1"
    fi
}

log_error() {
    echo "Error: $1" >&2
}

# Check if at least three arguments are provided
if [ $# -lt 3 ]; then
    usage
    exit 1
fi

# Assign arguments to variables
DIRECTORY="${1%/}"  # Remove trailing slash if present
OPERATION="$2"
KEY="$3"
FILE_PATH="${4:-./}"  # Use ./ if not specified

# Handle --quiet flag in file_path position
if [ "$FILE_PATH" = "--quiet" ]; then
    FILE_PATH="./"
    QUIET_MODE=true
fi

# Ensure FILE_PATH ends with a slash
FILE_PATH="${FILE_PATH%/}/"

# Create .git-vault/data directory if it doesn't exist
DATA_DIR=".git-vault/data"
if [ ! -d "$DATA_DIR" ]; then
    mkdir -p "$DATA_DIR"
fi

# Override FILE_PATH to use .git-vault/data/
FILE_PATH="$DATA_DIR/"

# Validate the key (hex encoded 256-bit key is 64 characters long)
if ! echo "$KEY" | grep -E '^[0-9A-Fa-f]{64}$' >/dev/null 2>&1; then
    log_error "Invalid key. Please provide a 256-bit key in hexadecimal format (64 characters)."
    log_error "Tip: You can generate a suitable key using: botan rng --format=hex 32"
    exit 1
fi

# Set up directory structure for incremental storage
BASE_NAME=$(basename "$DIRECTORY")
DATA_SUBDIR="${FILE_PATH}$(dirname "$DIRECTORY")"

# Create the directory structure within .git-vault/data/ to mirror the original
if [ "$DATA_SUBDIR" != "${FILE_PATH}." ] && [ ! -d "$DATA_SUBDIR" ]; then
    mkdir -p "$DATA_SUBDIR"
fi

# Handle root-level directories (no subdirectory)
if [ "$(dirname "$DIRECTORY")" = "." ]; then
    VAULT_DIR="${FILE_PATH}${BASE_NAME}"
else
    VAULT_DIR="${DATA_SUBDIR}/${BASE_NAME}"
fi

# Create vault directory structure
mkdir -p "$VAULT_DIR/patches"

# File paths for incremental storage
BASE_ARCHIVE="$VAULT_DIR/base.tar.gz.aes256gcm.enc"
BASE_NONCE="$VAULT_DIR/base.nonce"
CURRENT_STATE="$VAULT_DIR/current.state"

# Ensure current.state is in .gitignore
GITIGNORE_FILE=".gitignore"
if [ -f "$GITIGNORE_FILE" ]; then
    if ! grep -q "\.git-vault/data/.*/current\.state" "$GITIGNORE_FILE" 2>/dev/null; then
        echo "" >> "$GITIGNORE_FILE"
        echo "# git-vault current state directories (not committed)" >> "$GITIGNORE_FILE"
        echo ".git-vault/data/*/current.state/" >> "$GITIGNORE_FILE"
    fi
fi

# Function to create base snapshot
create_base_snapshot() {
    local dir="$1"
    
    log_info "Creating base snapshot for $dir..."
    
    # Create a temporary directory
    if command -v mktemp >/dev/null 2>&1; then
        TEMP_DIR=$(mktemp -d)
    else
        TEMP_DIR="/tmp/git-vault-$$-$(date +%s)"
        mkdir -p "$TEMP_DIR"
    fi
    
    # Create an archive of the source directory
    tar -czf "$TEMP_DIR/base.tar.gz" -C "$dir" .
    
    # Generate a random 96-bit nonce in hex format
    NONCE=$(botan rng --format=hex 12)
    
    # Save the nonce to a file
    echo -n "$NONCE" > "$BASE_NONCE"
    
    # Encrypt the archive using Botan 3 with AES-256/GCM
    if ! botan cipher --cipher=AES-256/GCM --key="$KEY" --nonce="$NONCE" "$TEMP_DIR/base.tar.gz" > "$BASE_ARCHIVE"; then
        log_error "Base snapshot encryption failed."
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Create a copy of the directory for future diff comparisons
    rm -rf "$CURRENT_STATE"
    cp -r "$dir" "$CURRENT_STATE"
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    log_info "Base snapshot created: $BASE_ARCHIVE"
    return 0
}

# Function to create incremental patch using bash-native diff
create_patch() {
    local dir="$1"
    
    log_info "Creating incremental patch for $dir..."
    
    # Check if there are any changes by comparing directories
    if diff -r "$CURRENT_STATE" "$dir" >/dev/null 2>&1; then
        log_info "No changes detected in $dir"
        return 0
    fi
    
    # Create temporary directory
    if command -v mktemp >/dev/null 2>&1; then
        TEMP_DIR=$(mktemp -d)
    else
        TEMP_DIR="/tmp/git-vault-$$-$(date +%s)"
        mkdir -p "$TEMP_DIR"
    fi
    
    # Create a simple change list instead of complex patches
    CHANGES_FILE="$TEMP_DIR/changes.txt"
    
    # Find all files in both directories
    find "$CURRENT_STATE" -type f 2>/dev/null | sed "s|^$CURRENT_STATE/||" | sort > "$TEMP_DIR/old_files.txt"
    find "$dir" -type f 2>/dev/null | sed "s|^$dir/||" | sort > "$TEMP_DIR/new_files.txt"
    
    # Start building the changes file
    echo "# Incremental changes for $dir" > "$CHANGES_FILE"
    echo "# Format: ACTION:FILEPATH:CONTENT_OR_HASH" >> "$CHANGES_FILE"
    
    # Find deleted files
    comm -23 "$TEMP_DIR/old_files.txt" "$TEMP_DIR/new_files.txt" | while read -r file; do
        echo "DELETE:$file:" >> "$CHANGES_FILE"
    done
    
    # Find new files
    comm -13 "$TEMP_DIR/old_files.txt" "$TEMP_DIR/new_files.txt" | while read -r file; do
        echo "CREATE:$file:$(base64 -w 0 "$dir/$file")" >> "$CHANGES_FILE"
    done
    
    # Find modified files
    comm -12 "$TEMP_DIR/old_files.txt" "$TEMP_DIR/new_files.txt" | while read -r file; do
        if ! cmp -s "$CURRENT_STATE/$file" "$dir/$file" 2>/dev/null; then
            echo "MODIFY:$file:$(base64 -w 0 "$dir/$file")" >> "$CHANGES_FILE"
        fi
    done
    
    # Check if any changes were recorded
    if [ "$(wc -l < "$CHANGES_FILE")" -le 2 ]; then
        log_info "No changes detected in $dir"
        rm -rf "$TEMP_DIR"
        return 0
    fi
    
    # Get next patch number
    PATCH_NUM=$(find "$VAULT_DIR/patches" -name "*.patch.aes256gcm.enc" | wc -l | tr -d ' ')
    PATCH_NUM=$((PATCH_NUM + 1))
    PATCH_NUM_PADDED=$(printf "%03d" "$PATCH_NUM")
    
    PATCH_ARCHIVE="$VAULT_DIR/patches/${PATCH_NUM_PADDED}.patch.aes256gcm.enc"
    PATCH_NONCE="$VAULT_DIR/patches/${PATCH_NUM_PADDED}.nonce"
    
    log_info "Creating patch $PATCH_NUM_PADDED"
    
    # Generate a random 96-bit nonce in hex format
    NONCE=$(botan rng --format=hex 12)
    
    # Save the nonce to a file
    echo -n "$NONCE" > "$PATCH_NONCE"
    
    # Encrypt the changes file
    if ! botan cipher --cipher=AES-256/GCM --key="$KEY" --nonce="$NONCE" "$CHANGES_FILE" > "$PATCH_ARCHIVE"; then
        log_error "Patch encryption failed."
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Update current state
    rm -rf "$CURRENT_STATE"
    cp -r "$dir" "$CURRENT_STATE"
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    log_info "Patch created: $PATCH_ARCHIVE"
    return 0
}

# Function to lock (encrypt) directory
lock() {
    if [ ! -d "$DIRECTORY" ]; then
        log_error "Directory $DIRECTORY does not exist for encryption."
        exit 1
    fi
    
    # Check if base snapshot exists
    if [ ! -f "$BASE_ARCHIVE" ] || [ ! -f "$BASE_NONCE" ]; then
        # Create base snapshot
        create_base_snapshot "$DIRECTORY"
    else
        # Create incremental patch
        create_patch "$DIRECTORY"
    fi
}

# Function to apply changes from a simple changes file
apply_changes() {
    local changes_file="$1"
    local target_dir="$2"
    
    log_debug "Applying changes from $changes_file to $target_dir"
    
    # Process each line in the changes file
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^# ]] || [ -z "$line" ]; then
            continue
        fi
        
        # Parse the line format: ACTION:FILEPATH:CONTENT_OR_HASH
        IFS=':' read -r action filepath content <<< "$line"
        
        case "$action" in
            DELETE)
                if [ -f "$target_dir/$filepath" ]; then
                    rm -f "$target_dir/$filepath"
                    log_debug "Deleted file: $filepath"
                fi
                ;;
            CREATE)
                # Create directory if needed
                mkdir -p "$(dirname "$target_dir/$filepath")"
                # Decode base64 content and write to file
                echo "$content" | base64 -d > "$target_dir/$filepath"
                log_debug "Created file: $filepath"
                ;;
            MODIFY)
                # Create directory if needed
                mkdir -p "$(dirname "$target_dir/$filepath")"
                # Decode base64 content and write to file
                echo "$content" | base64 -d > "$target_dir/$filepath"
                log_debug "Modified file: $filepath"
                ;;
            *)
                log_debug "Unknown action: $action for file: $filepath"
                ;;
        esac
    done < "$changes_file"
}

# Function to unlock (decrypt) directory
unlock() {
    log_info "Restoring $DIRECTORY from incremental vault..."
    
    # Check if base snapshot exists
    if [ ! -f "$BASE_ARCHIVE" ] || [ ! -f "$BASE_NONCE" ]; then
        log_error "No base snapshot found for $DIRECTORY"
        exit 1
    fi
    
    # Create temporary directory
    if command -v mktemp >/dev/null 2>&1; then
        TEMP_DIR=$(mktemp -d)
    else
        TEMP_DIR="/tmp/git-vault-$$-$(date +%s)"
        mkdir -p "$TEMP_DIR"
    fi
    
    # Create target directory if it doesn't exist
    if [ ! -d "$DIRECTORY" ]; then
        mkdir -p "$DIRECTORY"
    fi
    
    # Restore base snapshot
    log_info "Restoring base snapshot..."
    
    # Read base nonce
    BASE_NONCE_VALUE=$(cat "$BASE_NONCE")
    
    # Decrypt base archive
    if ! botan cipher --decrypt --cipher=AES-256/GCM --key="$KEY" --nonce="$BASE_NONCE_VALUE" "$BASE_ARCHIVE" > "$TEMP_DIR/base.tar.gz"; then
        log_error "Base snapshot decryption failed."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Extract base snapshot
    tar -xzf "$TEMP_DIR/base.tar.gz" -C "$DIRECTORY"
    
    # Apply patches in order
    for patch_file in "$VAULT_DIR/patches"/*.patch.aes256gcm.enc; do
        if [ -f "$patch_file" ]; then
            patch_name=$(basename "$patch_file" .patch.aes256gcm.enc)
            patch_nonce_file="$VAULT_DIR/patches/${patch_name}.nonce"
            
            if [ -f "$patch_nonce_file" ]; then
                log_info "Applying patch $patch_name..."
                
                # Read patch nonce
                PATCH_NONCE_VALUE=$(cat "$patch_nonce_file")
                
                # Decrypt patch file
                if ! botan cipher --decrypt --cipher=AES-256/GCM --key="$KEY" --nonce="$PATCH_NONCE_VALUE" "$patch_file" > "$TEMP_DIR/changes.txt"; then
                    log_error "Patch $patch_name decryption failed."
                    rm -rf "$TEMP_DIR"
                    exit 1
                fi
                
                # Apply changes using our simple format
                apply_changes "$TEMP_DIR/changes.txt" "$DIRECTORY"
            fi
        fi
    done
    
    # Clean up temp directory
    rm -rf "$TEMP_DIR"
    
    log_info "Restoration complete. Files restored to $DIRECTORY"
}

# Perform the requested operation
case "$OPERATION" in
    lock)
        lock
        ;;
    unlock)
        unlock
        ;;
    *)
        log_error "Invalid operation. Use 'lock' or 'unlock'."
        usage
        exit 1
        ;;
esac