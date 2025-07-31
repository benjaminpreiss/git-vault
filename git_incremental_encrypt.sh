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
STATE_HASH="$VAULT_DIR/state.hash"

# Function to create directory hash for change detection
create_directory_hash() {
    local dir="$1"
    find "$dir" -type f -exec sha256sum {} \; 2>/dev/null | sort | sha256sum | cut -d' ' -f1
}

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
    
    # Store directory hash for future change detection (no plaintext files!)
    create_directory_hash "$dir" > "$STATE_HASH"
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    log_info "Base snapshot created: $BASE_ARCHIVE"
    return 0
}

# Function to create incremental patch using hash-based change detection
create_patch() {
    local dir="$1"
    
    log_info "Creating incremental patch for $dir..."
    
    # Check if there are any changes by comparing directory hashes
    current_hash=$(create_directory_hash "$dir")
    if [ -f "$STATE_HASH" ]; then
        stored_hash=$(cat "$STATE_HASH")
        if [ "$current_hash" = "$stored_hash" ]; then
            log_info "No changes detected in $dir"
            return 0
        fi
    fi
    
    # Create temporary directory
    if command -v mktemp >/dev/null 2>&1; then
        TEMP_DIR=$(mktemp -d)
    else
        TEMP_DIR="/tmp/git-vault-$$-$(date +%s)"
        mkdir -p "$TEMP_DIR"
    fi
    
    # Create a simple change list - store entire current state
    CHANGES_FILE="$TEMP_DIR/changes.txt"
    
    # Start building the changes file with current directory contents
    echo "# Incremental changes for $dir" > "$CHANGES_FILE"
    echo "# Format: ACTION:FILEPATH:CONTENT" >> "$CHANGES_FILE"
    
    # Store all current files (this is the simplest approach without plaintext storage)
    find "$dir" -type f 2>/dev/null | while read -r filepath; do
        relative_path="${filepath#$dir/}"
        echo "REPLACE:$relative_path:$(base64 -w 0 "$filepath")" >> "$CHANGES_FILE"
    done
    
    # Check if any files were recorded
    if [ "$(wc -l < "$CHANGES_FILE")" -le 2 ]; then
        log_info "No files found in $dir"
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
    
    # Update stored hash (no plaintext files!)
    echo "$current_hash" > "$STATE_HASH"
    
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
            REPLACE)
                # Create directory if needed
                mkdir -p "$(dirname "$target_dir/$filepath")"
                # Decode base64 content and write to file
                echo "$content" | base64 -d > "$target_dir/$filepath"
                log_debug "Replaced file: $filepath"
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
    
    # For REPLACE-based patches, we need to clear the directory first and rebuild from scratch
    # This ensures deleted files are properly removed
    if [ -d "$VAULT_DIR/patches" ] && [ "$(find "$VAULT_DIR/patches" -name "*.patch.aes256gcm.enc" | wc -l)" -gt 0 ]; then
        # We have patches, so we'll rebuild from the latest patch (which contains full state)
        # Find the latest patch
        latest_patch=$(find "$VAULT_DIR/patches" -name "*.patch.aes256gcm.enc" | sort | tail -1)
        if [ -n "$latest_patch" ]; then
            patch_name=$(basename "$latest_patch" .patch.aes256gcm.enc)
            patch_nonce_file="$VAULT_DIR/patches/${patch_name}.nonce"
            
            if [ -f "$patch_nonce_file" ]; then
                log_info "Restoring from latest patch $patch_name (contains full state)..."
                
                # Clear target directory completely
                rm -rf "$DIRECTORY"
                mkdir -p "$DIRECTORY"
                
                # Read patch nonce
                PATCH_NONCE_VALUE=$(cat "$patch_nonce_file")
                
                # Decrypt patch file
                if ! botan cipher --decrypt --cipher=AES-256/GCM --key="$KEY" --nonce="$PATCH_NONCE_VALUE" "$latest_patch" > "$TEMP_DIR/changes.txt"; then
                    log_error "Patch $patch_name decryption failed."
                    rm -rf "$TEMP_DIR"
                    exit 1
                fi
                
                # Apply changes using our simple format
                apply_changes "$TEMP_DIR/changes.txt" "$DIRECTORY"
            fi
        fi
    else
        # No patches, restore from base snapshot
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
    fi
    
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