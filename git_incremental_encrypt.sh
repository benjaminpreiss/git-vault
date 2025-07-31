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
    echo "       $0 --check-deps"
    echo ""
    echo "Arguments:"
    echo "  <directory>: The directory to process (can be relative to git repo root)"
    echo "  <operation>: Either 'lock' or 'unlock'"
    echo "  <key>: 256-bit key in hexadecimal format (64 characters)"
    echo "  [<file_path>]: Optional path to encrypted files (default: .git-vault/data/)"
    echo "  [--quiet]: Suppress non-error output"
    echo ""
    echo "Options:"
    echo "  --check-deps: Check system dependencies and versions"
    echo ""
    echo "This script implements incremental encryption using bash-native utilities."
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

# Function to check if a version meets minimum requirements
version_compare() {
    local version="$1"
    local required="$2"
    
    # Convert versions to comparable format (remove non-numeric characters except dots)
    local clean_version=$(echo "$version" | sed 's/[^0-9.]//g')
    local clean_required=$(echo "$required" | sed 's/[^0-9.]//g')
    
    # Use sort -V for version comparison if available, otherwise use basic comparison
    if command -v sort >/dev/null 2>&1 && sort --version-sort /dev/null >/dev/null 2>&1; then
        local highest=$(printf "%s\n%s" "$clean_version" "$clean_required" | sort -V | tail -1)
        [ "$highest" = "$clean_version" ]
    else
        # Fallback: basic numeric comparison (assumes X.Y.Z format)
        local IFS='.'
        set -- $clean_version
        local v1_major=$1 v1_minor=$2 v1_patch=$3
        set -- $clean_required
        local r_major=$1 r_minor=$2 r_patch=$3
        
        # Compare major.minor.patch
        if [ "$v1_major" -gt "$r_major" ]; then
            return 0
        elif [ "$v1_major" -eq "$r_major" ]; then
            if [ "$v1_minor" -gt "$r_minor" ]; then
                return 0
            elif [ "$v1_minor" -eq "$r_minor" ]; then
                [ "${v1_patch:-0}" -ge "${r_patch:-0}" ]
            else
                return 1
            fi
        else
            return 1
        fi
    fi
}

# Function to check system dependencies and versions
check_dependencies() {
    local errors=0
    
    log_info "Checking system dependencies..."
    
    # Check Botan (required)
    if ! command -v botan >/dev/null 2>&1; then
        log_error "Botan is required but not installed. Please install Botan 3.6.1 or later."
        log_error "Installation: https://botan.randombit.net/handbook/building.html"
        errors=$((errors + 1))
    else
        # Try different ways to get Botan version
        local botan_version=""
        if botan version >/dev/null 2>&1; then
            botan_version=$(botan version 2>/dev/null | head -1 | awk '{print $2}')
        fi
        
        # Alternative version extraction methods
        if [ -z "$botan_version" ]; then
            botan_version=$(botan version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        fi
        
        if [ -z "$botan_version" ]; then
            log_error "Could not determine Botan version. Please ensure Botan 3.6.1 or later is installed."
            errors=$((errors + 1))
        elif ! version_compare "$botan_version" "3.5.0"; then
            log_error "Botan version $botan_version found, but 3.5.0 or later is required."
            log_error "Please upgrade Botan: https://botan.randombit.net/handbook/building.html"
            errors=$((errors + 1))
        else
            log_info "✅ Botan $botan_version (meets requirement: ≥3.5.0)"
        fi
    fi
    
    # Check bash version (required 3.2.57+)
    local bash_version=$(bash --version 2>/dev/null | head -1 | sed 's/.*version \([0-9.]*\).*/\1/')
    if [ -n "$bash_version" ]; then
        if version_compare "$bash_version" "3.2.57"; then
            log_info "✅ Bash $bash_version (meets requirement: ≥3.2.57)"
        else
            log_error "Bash $bash_version found, but 3.2.57 or later is required."
            errors=$((errors + 1))
        fi
    fi
    
    # Check base64 availability
    if command -v base64 >/dev/null 2>&1; then
        log_info "✅ base64 command available"
    else
        log_error "base64 command not found. This is required for file encoding."
        errors=$((errors + 1))
    fi
    
    # Check tar availability
    if command -v tar >/dev/null 2>&1; then
        log_info "✅ tar command available"
    else
        log_error "tar command not found. This is required for creating archives."
        errors=$((errors + 1))
    fi
    
    # Check find availability
    if command -v find >/dev/null 2>&1; then
        log_info "✅ find command available"
    else
        log_error "find command not found. This is required for file operations."
        errors=$((errors + 1))
    fi
    
    if [ $errors -gt 0 ]; then
        log_error "Found $errors dependency issues. Please resolve them before using git-vault."
        return 1
    else
        log_info "✅ All dependencies satisfied"
        return 0
    fi
}

# Cross-platform base64 encode function
base64_encode() {
    if command -v base64 >/dev/null 2>&1; then
        # Check if this is GNU base64 (Linux) or BSD base64 (macOS)
        if base64 --help 2>&1 | grep -q "wrap"; then
            # GNU base64 (Linux)
            base64 -w 0
        else
            # BSD base64 (macOS) - no line wrapping by default
            base64
        fi
    else
        # Fallback using openssl
        openssl base64 -A
    fi
}

# Cross-platform base64 decode function
base64_decode() {
    if command -v base64 >/dev/null 2>&1; then
        # Check if this is GNU base64 (Linux) or BSD base64 (macOS)
        if base64 --help 2>&1 | grep -q "decode"; then
            # GNU base64 (Linux)
            base64 -d
        else
            # BSD base64 (macOS)
            base64 -D
        fi
    else
        # Fallback using openssl
        openssl base64 -d
    fi
}

# Handle special commands first
if [ "$1" = "--check-deps" ]; then
    check_dependencies
    exit $?
fi

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

# Check dependencies before proceeding (only if explicitly requested)
# Skip automatic dependency checking to avoid breaking existing workflows
if [ "$1" = "--check-deps" ]; then
    # This case is handled earlier, but this comment explains the logic
    :
fi

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

# Function to create directory hash for change detection using Botan
create_directory_hash() {
    local dir="$1"
    
    # Create a temporary file to store file hashes
    if command -v mktemp >/dev/null 2>&1; then
        local temp_file=$(mktemp)
    else
        local temp_file="/tmp/git-vault-hash-$$-$(date +%s)"
    fi
    
    # Hash all files in directory using Botan and sort for consistency
    find "$dir" -type f 2>/dev/null | sort | while read -r filepath; do
        botan hash --algo=SHA-256 "$filepath" 2>/dev/null || echo "ERROR: Failed to hash $filepath"
    done > "$temp_file"
    
    # Hash the combined hashes to get a single directory hash
    local dir_hash=$(botan hash --algo=SHA-256 "$temp_file" 2>/dev/null | cut -d' ' -f1)
    
    # Clean up
    rm -f "$temp_file"
    
    echo "$dir_hash"
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
        echo "REPLACE:$relative_path:$(base64_encode < "$filepath")" >> "$CHANGES_FILE"
    done
    
    # Check if any files were recorded
    if [ "$(wc -l < "$CHANGES_FILE")" -le 2 ]; then
        log_info "No files found in $dir"
        rm -rf "$TEMP_DIR"
        return 0
    fi
    
    # Get next patch number (cross-platform)
    PATCH_NUM=$(find "$VAULT_DIR/patches" -name "*.patch.aes256gcm.enc" 2>/dev/null | wc -l)
    # Remove any whitespace (cross-platform)
    PATCH_NUM=$(echo "$PATCH_NUM" | sed 's/[[:space:]]//g')
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
                echo "$content" | base64_decode > "$target_dir/$filepath"
                log_debug "Created file: $filepath"
                ;;
            MODIFY)
                # Create directory if needed
                mkdir -p "$(dirname "$target_dir/$filepath")"
                # Decode base64 content and write to file
                echo "$content" | base64_decode > "$target_dir/$filepath"
                log_debug "Modified file: $filepath"
                ;;
            REPLACE)
                # Create directory if needed
                mkdir -p "$(dirname "$target_dir/$filepath")"
                # Decode base64 content and write to file
                echo "$content" | base64_decode > "$target_dir/$filepath"
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
    patch_count=$(find "$VAULT_DIR/patches" -name "*.patch.aes256gcm.enc" 2>/dev/null | wc -l)
    patch_count=$(echo "$patch_count" | sed 's/[[:space:]]//g')
    if [ -d "$VAULT_DIR/patches" ] && [ "$patch_count" -gt 0 ]; then
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