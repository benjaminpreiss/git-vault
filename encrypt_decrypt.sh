#!/bin/bash

# Check for quiet mode
QUIET_MODE=false
if [ "$4" = "--quiet" ] || [ "$5" = "--quiet" ]; then
    QUIET_MODE=true
fi

# Function to show usage
usage() {
    echo "Usage: $0 <directory> <operation> <key> [<file_path>] [--quiet]"
    echo "  <directory>: The directory to process (can be relative to git repo root)"
    echo "  <operation>: Either 'encrypt' or 'decrypt'"
    echo "  <key>: 256-bit key in hexadecimal format (64 characters)"
    echo "  [<file_path>]: Optional path to .nonce and .tar.gz.aes256gcm.enc files (default: ./)"
    echo "  [--quiet]: Suppress non-error output"
    echo ""
    echo "Note: This script is typically called by locker.sh which reads directories"
    echo "      from .git-vault-dirs configuration file."
    echo ""
    echo "Tip: To generate a suitable 256-bit key, you can use the following command:"
    echo "  botan rng --format=hex 32"
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

# Check if directory exists (for encrypt) or if we can create it (for decrypt)
if [ "$OPERATION" = "encrypt" ]; then
    if [ ! -d "$DIRECTORY" ]; then
        log_error "Directory $DIRECTORY does not exist for encryption."
        exit 1
    fi
elif [ "$OPERATION" = "decrypt" ]; then
    # For decrypt, create the directory if it doesn't exist
    if [ ! -d "$DIRECTORY" ]; then
        log_info "Creating directory $DIRECTORY for decryption..."
        mkdir -p "$DIRECTORY"
    fi
fi

# Validate the key (hex encoded 256-bit key is 64 characters long)
# Cross-platform regex check
if ! echo "$KEY" | grep -E '^[0-9A-Fa-f]{64}$' >/dev/null 2>&1; then
    log_error "Invalid key. Please provide a 256-bit key in hexadecimal format (64 characters)."
    log_error "Tip: You can generate a suitable key using: botan rng --format=hex 32"
    exit 1
fi

# Create the exact directory structure within .git-vault/data/
# Store files at the same path as they appear in the root
BASE_NAME=$(basename "$DIRECTORY")
DATA_SUBDIR="${FILE_PATH}$(dirname "$DIRECTORY")"

# Create the directory structure within .git-vault/data/ to mirror the original
if [ "$DATA_SUBDIR" != "${FILE_PATH}." ] && [ ! -d "$DATA_SUBDIR" ]; then
    mkdir -p "$DATA_SUBDIR"
fi

ENCRYPTED_ARCHIVE="${DATA_SUBDIR}/${BASE_NAME}.tar.gz.aes256gcm.enc"
NONCE_FILE="${DATA_SUBDIR}/${BASE_NAME}.nonce"

# Handle root-level directories (no subdirectory)
if [ "$(dirname "$DIRECTORY")" = "." ]; then
    ENCRYPTED_ARCHIVE="${FILE_PATH}${BASE_NAME}.tar.gz.aes256gcm.enc"
    NONCE_FILE="${FILE_PATH}${BASE_NAME}.nonce"
fi

# Cross-platform file size function
get_file_size() {
    local file="$1"
    if [ -f "$file" ]; then
        if command -v stat >/dev/null 2>&1; then
            # Try Linux/GNU stat first
            if stat -c%s "$file" 2>/dev/null; then
                return 0
            # Fall back to macOS/BSD stat
            elif stat -f%z "$file" 2>/dev/null; then
                return 0
            fi
        fi
        # Fallback using wc if stat fails
        wc -c < "$file" 2>/dev/null || echo "unknown"
    else
        echo "0"
    fi
}

# Function to encrypt
encrypt() {
    log_info "Encrypting $DIRECTORY..."
    
    # Create a temporary directory (cross-platform)
    if command -v mktemp >/dev/null 2>&1; then
        TEMP_DIR=$(mktemp -d)
    else
        # Fallback for systems without mktemp
        TEMP_DIR="/tmp/git-vault-$$-$(date +%s)"
        mkdir -p "$TEMP_DIR"
    fi
    
    # Create an archive of the source directory
    tar -czf "$TEMP_DIR/$BASE_NAME.tar.gz" -C "$DIRECTORY" .
    
    # Generate a random 96-bit nonce in hex format
    NONCE=$(botan rng --format=hex 12)
    
    # Save the nonce to a file
    echo -n "$NONCE" > "$NONCE_FILE"
    
    log_debug "Debug: Archive size before encryption: $(get_file_size "$TEMP_DIR/$BASE_NAME.tar.gz")"
    
    # Encrypt the archive using Botan 3 with AES-256/GCM
    if ! botan cipher --cipher=AES-256/GCM --key="$KEY" --nonce="$NONCE" "$TEMP_DIR/$BASE_NAME.tar.gz" > "$ENCRYPTED_ARCHIVE"; then
        log_error "Botan 3 encryption failed."
        log_debug "Debug: Temp archive exists: $([ -f "$TEMP_DIR/$BASE_NAME.tar.gz" ] && echo "yes" || echo "no")"
        log_debug "Debug: Key length: ${#KEY}"
        log_debug "Debug: Nonce: $NONCE"
        log_debug "Debug: Nonce length: ${#NONCE}"
        log_debug "Debug: Botan version: $(botan version 2>&1)"
        
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    log_info "Encryption complete. Encrypted archive: $ENCRYPTED_ARCHIVE"
    log_info "Nonce saved to: $NONCE_FILE"
    log_debug "Debug: Encrypted file size: $(get_file_size "$ENCRYPTED_ARCHIVE")"
}

# Function to decrypt
decrypt() {
    log_info "Decrypting $ENCRYPTED_ARCHIVE..."
    
    # Check if encrypted archive exists
    if [ ! -f "$ENCRYPTED_ARCHIVE" ]; then
        log_error "Encrypted archive $ENCRYPTED_ARCHIVE not found."
        if [ "$QUIET_MODE" = false ]; then
            echo "Available files in $DATA_DIR:"
            ls -la "$DATA_DIR"/*.enc "$DATA_DIR"/*.nonce 2>/dev/null || echo "No encrypted files found"
        fi
        exit 1
    fi
    
    # Check if nonce file exists
    if [ ! -f "$NONCE_FILE" ]; then
        log_error "Nonce file $NONCE_FILE not found."
        if [ "$QUIET_MODE" = false ]; then
            echo "Available files in $DATA_DIR:"
            ls -la "$DATA_DIR"/*.nonce 2>/dev/null || echo "No nonce files found"
        fi
        exit 1
    fi
    
    # Read the nonce from the file
    NONCE=$(cat "$NONCE_FILE")
    log_debug "Debug: Using nonce: $NONCE"
    log_debug "Debug: Nonce length: ${#NONCE}"
    
    # Validate nonce format (should be 24 hex characters for 96-bit nonce) - cross-platform
    if ! echo "$NONCE" | grep -E '^[0-9A-Fa-f]{24}$' >/dev/null 2>&1; then
        log_error "Invalid nonce format. Expected 24 hex characters, got: $NONCE"
        exit 1
    fi
    
    # Create a temporary directory (cross-platform)
    if command -v mktemp >/dev/null 2>&1; then
        TEMP_DIR=$(mktemp -d)
    else
        # Fallback for systems without mktemp
        TEMP_DIR="/tmp/git-vault-$$-$(date +%s)"
        mkdir -p "$TEMP_DIR"
    fi
    log_debug "Debug: Using temp directory: $TEMP_DIR"
    
    # Decrypt the archive using Botan 3 with AES-256/GCM
    log_debug "Debug: Running decryption command..."
    if ! botan cipher --decrypt --cipher=AES-256/GCM --key="$KEY" --nonce="$NONCE" "$ENCRYPTED_ARCHIVE" > "$TEMP_DIR/$BASE_NAME.tar.gz"; then
        log_error "Botan 3 decryption failed."
        log_debug "Debug: Encrypted file size: $(get_file_size "$ENCRYPTED_ARCHIVE")"
        log_debug "Debug: Key length: ${#KEY}"
        log_debug "Debug: Nonce: $NONCE"
        log_debug "Debug: Botan version: $(botan version 2>&1)"
        
        # Try to examine the encrypted file
        if [ "$QUIET_MODE" = false ]; then
            echo "Debug: First 50 bytes of encrypted file (hex):"
            xxd -l 50 "$ENCRYPTED_ARCHIVE" 2>/dev/null || echo "Could not examine encrypted file"
        fi
        
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Check if the decrypted file was created and has content
    if [ ! -f "$TEMP_DIR/$BASE_NAME.tar.gz" ] || [ ! -s "$TEMP_DIR/$BASE_NAME.tar.gz" ]; then
        log_error "Decrypted archive was not created or is empty."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    log_debug "Debug: Decrypted archive size: $(get_file_size "$TEMP_DIR/$BASE_NAME.tar.gz")"
    
    # Unpack the archive, overwriting existing files
    log_debug "Debug: Extracting archive to $DIRECTORY"
    if ! tar -xzf "$TEMP_DIR/$BASE_NAME.tar.gz" -C "$DIRECTORY"; then
        log_error "Failed to extract archive."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    log_info "Decryption and unpacking complete. Files restored to $DIRECTORY"
}

# Perform the requested operation
case "$OPERATION" in
    encrypt)
        encrypt
        ;;
    decrypt)
        decrypt
        ;;
    *)
        log_error "Invalid operation. Use 'encrypt' or 'decrypt'."
        usage
        exit 1
        ;;
esac