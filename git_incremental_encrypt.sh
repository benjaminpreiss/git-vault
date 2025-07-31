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

# Function to create incremental patch using proper diff-based change detection
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
    
    # Create a temporary directory to store previous state for comparison
    PREV_STATE_DIR="$TEMP_DIR/prev_state"
    mkdir -p "$PREV_STATE_DIR"
    
    # Restore previous state from the latest patch or base snapshot
    restore_previous_state "$PREV_STATE_DIR"
    
    # Create changes file
    CHANGES_FILE="$TEMP_DIR/changes.txt"
    echo "# Incremental changes for $dir" > "$CHANGES_FILE"
    echo "# Format: ACTION:FILEPATH:CONTENT" >> "$CHANGES_FILE"
    
    # Compare current state with previous state to find changes
    create_incremental_changes "$dir" "$PREV_STATE_DIR" "$CHANGES_FILE"
    
    # Check if any changes were recorded
    if [ "$(wc -l < "$CHANGES_FILE")" -le 2 ]; then
        log_info "No changes found in $dir"
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

# Function to restore previous state for comparison
restore_previous_state() {
    local target_dir="$1"
    
    # Check if we have any patches - if so, restore from the latest patch
    if [ -d "$VAULT_DIR/patches" ]; then
        latest_patch=$(find "$VAULT_DIR/patches" -name "*.patch.aes256gcm.enc" 2>/dev/null | sort | tail -1)
        if [ -n "$latest_patch" ]; then
            patch_name=$(basename "$latest_patch" .patch.aes256gcm.enc)
            patch_nonce_file="$VAULT_DIR/patches/${patch_name}.nonce"
            
            if [ -f "$patch_nonce_file" ]; then
                log_debug "Restoring previous state from latest patch $patch_name"
                
                # Read patch nonce
                PATCH_NONCE_VALUE=$(cat "$patch_nonce_file")
                
                # Create temporary file for decrypted patch
                if command -v mktemp >/dev/null 2>&1; then
                    temp_patch_file=$(mktemp)
                else
                    temp_patch_file="/tmp/git-vault-patch-$$-$(date +%s)"
                fi
                
                # Decrypt patch file
                if botan cipher --decrypt --cipher=AES-256/GCM --key="$KEY" --nonce="$PATCH_NONCE_VALUE" "$latest_patch" > "$temp_patch_file"; then
                    # Apply changes to get previous state
                    apply_changes "$temp_patch_file" "$target_dir"
                fi
                
                rm -f "$temp_patch_file"
                return 0
            fi
        fi
    fi
    
    # No patches exist, restore from base snapshot
    if [ -f "$BASE_ARCHIVE" ] && [ -f "$BASE_NONCE" ]; then
        log_debug "Restoring previous state from base snapshot"
        
        # Read base nonce
        BASE_NONCE_VALUE=$(cat "$BASE_NONCE")
        
        # Create temporary file for decrypted base
        if command -v mktemp >/dev/null 2>&1; then
            temp_base_file=$(mktemp)
        else
            temp_base_file="/tmp/git-vault-base-$$-$(date +%s)"
        fi
        
        # Decrypt base archive
        if botan cipher --decrypt --cipher=AES-256/GCM --key="$KEY" --nonce="$BASE_NONCE_VALUE" "$BASE_ARCHIVE" > "$temp_base_file"; then
            # Extract base snapshot
            tar -xzf "$temp_base_file" -C "$target_dir" 2>/dev/null || true
        fi
        
        rm -f "$temp_base_file"
    fi
}

# Function to create incremental changes by comparing current and previous states
create_incremental_changes() {
    local current_dir="$1"
    local prev_dir="$2"
    local changes_file="$3"
    
    # Create temporary files for file lists
    if command -v mktemp >/dev/null 2>&1; then
        current_files=$(mktemp)
        prev_files=$(mktemp)
    else
        current_files="/tmp/git-vault-current-$$-$(date +%s)"
        prev_files="/tmp/git-vault-prev-$$-$(date +%s)"
    fi
    
    # Get sorted lists of files
    if [ -d "$current_dir" ]; then
        find "$current_dir" -type f 2>/dev/null | sed "s|^$current_dir/||" | sort > "$current_files"
    else
        touch "$current_files"
    fi
    
    if [ -d "$prev_dir" ]; then
        find "$prev_dir" -type f 2>/dev/null | sed "s|^$prev_dir/||" | sort > "$prev_files"
    else
        touch "$prev_files"
    fi
    
    # Find new files (in current but not in previous)
    comm -23 "$current_files" "$prev_files" | while IFS= read -r filepath; do
        if [ -n "$filepath" ] && [ -f "$current_dir/$filepath" ]; then
            # Ensure base64 output is on a single line
            content_b64=$(base64_encode < "$current_dir/$filepath" | tr -d '\n\r')
            echo "CREATE:$filepath:$content_b64" >> "$changes_file"
            log_debug "New file: $filepath"
        fi
    done
    
    # Find deleted files (in previous but not in current)
    comm -13 "$current_files" "$prev_files" | while IFS= read -r filepath; do
        if [ -n "$filepath" ]; then
            echo "DELETE:$filepath:" >> "$changes_file"
            log_debug "Deleted file: $filepath"
        fi
    done
    
    # Find potentially modified files (in both)
    comm -12 "$current_files" "$prev_files" | while IFS= read -r filepath; do
        if [ -n "$filepath" ] && [ -f "$current_dir/$filepath" ] && [ -f "$prev_dir/$filepath" ]; then
            # Compare file contents using hash
            current_hash=$(botan hash --algo=SHA-256 "$current_dir/$filepath" 2>/dev/null | cut -d' ' -f1)
            prev_hash=$(botan hash --algo=SHA-256 "$prev_dir/$filepath" 2>/dev/null | cut -d' ' -f1)
            
            if [ "$current_hash" != "$prev_hash" ]; then
                # Check file size to determine if we should use binary diff
                current_size=$(wc -c < "$current_dir/$filepath")
                prev_size=$(wc -c < "$prev_dir/$filepath")
                
                # Use binary diff for files larger than 1KB to save space
                if [ "$current_size" -gt 1024 ] || [ "$prev_size" -gt 1024 ]; then
                    # Create binary diff using a simple approach
                    create_binary_diff "$current_dir/$filepath" "$prev_dir/$filepath" "$changes_file" "$filepath"
                else
                    # For small files, store entire content
                    content_b64=$(base64_encode < "$current_dir/$filepath" | tr -d '\n\r')
                    echo "MODIFY:$filepath:$content_b64" >> "$changes_file"
                fi
                log_debug "Modified file: $filepath"
            fi
        fi
    done
    
    # Clean up temporary files
    rm -f "$current_files" "$prev_files"
}

# Function to create binary diff using byte-level comparison
create_binary_diff() {
    local current_file="$1"
    local prev_file="$2"
    local changes_file="$3"
    local filepath="$4"
    
    # Create temporary files for diff processing
    if command -v mktemp >/dev/null 2>&1; then
        temp_diff=$(mktemp)
        temp_chunks=$(mktemp)
    else
        temp_diff="/tmp/git-vault-diff-$$-$(date +%s)"
        temp_chunks="/tmp/git-vault-chunks-$$-$(date +%s)"
    fi
    
    # Use cmp to find byte differences
    if cmp -l "$prev_file" "$current_file" 2>/dev/null > "$temp_diff"; then
        # Files are identical (shouldn't happen as we already checked hashes)
        rm -f "$temp_diff" "$temp_chunks"
        return 0
    fi
    
    # Process cmp output to create efficient diff chunks
    # cmp -l output format: byte_position old_byte new_byte
    local chunk_start=""
    local chunk_data=""
    local prev_pos=0
    local chunk_size=0
    local max_chunk_size=1024  # Maximum chunk size in bytes
    
    # Read cmp output and group consecutive changes into chunks
    while read -r pos old_byte new_byte; do
        if [ -n "$pos" ]; then
            # Convert to 0-based indexing
            pos=$((pos - 1))
            
            # If this is the start of a new chunk or gap is too large
            if [ -z "$chunk_start" ] || [ $((pos - prev_pos)) -gt 64 ] || [ $chunk_size -gt $max_chunk_size ]; then
                # Save previous chunk if it exists
                if [ -n "$chunk_start" ] && [ -n "$chunk_data" ]; then
                    chunk_data_b64=$(echo -n "$chunk_data" | base64_encode | tr -d '\n\r')
                    echo "BINDIFF:$filepath:$chunk_start:$chunk_data_b64" >> "$changes_file"
                fi
                
                # Start new chunk
                chunk_start="$pos"
                chunk_data=""
                chunk_size=0
            fi
            
            # Add padding bytes if there's a gap
            while [ $((chunk_start + chunk_size)) -lt $pos ]; do
                # Read the byte from current file at this position
                byte_val=$(dd if="$current_file" bs=1 skip=$((chunk_start + chunk_size)) count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
                if [ -n "$byte_val" ]; then
                    chunk_data="$chunk_data$(printf "\\x$byte_val")"
                fi
                chunk_size=$((chunk_size + 1))
            done
            
            # Add the changed byte
            new_byte_hex=$(printf "%02x" "$new_byte")
            chunk_data="$chunk_data$(printf "\\x$new_byte_hex")"
            chunk_size=$((chunk_size + 1))
            prev_pos=$pos
        fi
    done < "$temp_diff"
    
    # Save final chunk
    if [ -n "$chunk_start" ] && [ -n "$chunk_data" ]; then
        chunk_data_b64=$(echo -n "$chunk_data" | base64_encode | tr -d '\n\r')
        echo "BINDIFF:$filepath:$chunk_start:$chunk_data_b64" >> "$changes_file"
    fi
    
    # If no chunks were created, fall back to storing entire file
    if [ ! -s "$changes_file" ] || ! grep -q "BINDIFF:$filepath:" "$changes_file"; then
        content_b64=$(base64_encode < "$current_file" | tr -d '\n\r')
        echo "MODIFY:$filepath:$content_b64" >> "$changes_file"
    fi
    
    # Clean up
    rm -f "$temp_diff" "$temp_chunks"
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
        # Handle base64 content that may contain colons by only splitting on first two colons
        action=$(echo "$line" | cut -d':' -f1)
        filepath=$(echo "$line" | cut -d':' -f2)
        content=$(echo "$line" | cut -d':' -f3-)
        
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
            BINDIFF)
                # Apply binary diff patch
                # Format: BINDIFF:filepath:position:base64_data
                # The content field contains "position:base64_data"
                local position=$(echo "$content" | cut -d':' -f1)
                local patch_data=$(echo "$content" | cut -d':' -f2-)
                
                # Create directory if needed
                mkdir -p "$(dirname "$target_dir/$filepath")"
                
                # Decode patch data and apply at specified position
                if [ -f "$target_dir/$filepath" ]; then
                    # Create temporary file for patching
                    if command -v mktemp >/dev/null 2>&1; then
                        temp_patch_file=$(mktemp)
                    else
                        temp_patch_file="/tmp/git-vault-patch-$$-$(date +%s)"
                    fi
                    
                    # Copy original file
                    cp "$target_dir/$filepath" "$temp_patch_file"
                    
                    # Apply patch at position
                    echo "$patch_data" | base64_decode | dd of="$temp_patch_file" bs=1 seek="$position" conv=notrunc 2>/dev/null
                    
                    # Replace original with patched version
                    mv "$temp_patch_file" "$target_dir/$filepath"
                    
                    log_debug "Applied binary diff to file: $filepath at position $position"
                else
                    log_debug "Warning: Cannot apply binary diff to non-existent file: $filepath"
                fi
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
    
    # Clear target directory completely to ensure clean restoration
    rm -rf "$DIRECTORY"
    mkdir -p "$DIRECTORY"
    
    # Step 1: Restore base snapshot
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
    
    # Step 2: Apply patches sequentially if they exist
    if [ -d "$VAULT_DIR/patches" ]; then
        patch_count=$(find "$VAULT_DIR/patches" -name "*.patch.aes256gcm.enc" 2>/dev/null | wc -l)
        patch_count=$(echo "$patch_count" | sed 's/[[:space:]]//g')
        
        if [ "$patch_count" -gt 0 ]; then
            log_info "Applying $patch_count incremental patches..."
            
            # Apply patches in order
            find "$VAULT_DIR/patches" -name "*.patch.aes256gcm.enc" | sort | while IFS= read -r patch_file; do
                if [ -n "$patch_file" ]; then
                    patch_name=$(basename "$patch_file" .patch.aes256gcm.enc)
                    patch_nonce_file="$VAULT_DIR/patches/${patch_name}.nonce"
                    
                    if [ -f "$patch_nonce_file" ]; then
                        log_debug "Applying patch $patch_name..."
                        
                        # Read patch nonce
                        PATCH_NONCE_VALUE=$(cat "$patch_nonce_file")
                        
                        # Decrypt patch file
                        if botan cipher --decrypt --cipher=AES-256/GCM --key="$KEY" --nonce="$PATCH_NONCE_VALUE" "$patch_file" > "$TEMP_DIR/patch_${patch_name}.txt"; then
                            # Apply changes using our incremental format
                            apply_changes "$TEMP_DIR/patch_${patch_name}.txt" "$DIRECTORY"
                        else
                            log_error "Failed to decrypt patch $patch_name"
                            rm -rf "$TEMP_DIR"
                            exit 1
                        fi
                    else
                        log_error "Nonce file missing for patch $patch_name"
                        rm -rf "$TEMP_DIR"
                        exit 1
                    fi
                fi
            done
        fi
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