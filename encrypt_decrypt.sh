#!/bin/bash

# Function to show usage
usage() {
    echo "Usage: $0 <directory> <operation> <key> [<file_path>]"
    echo "  <directory>: The directory to process (can be relative to git repo root)"
    echo "  <operation>: Either 'encrypt' or 'decrypt'"
    echo "  <key>: 256-bit key in hexadecimal format (64 characters)"
    echo "  [<file_path>]: Optional path to .nonce and .tar.gz.aes256gcm.enc files (default: ./)"
    echo ""
    echo "Note: This script is typically called by locker.sh which reads directories"
    echo "      from .git-vault-dirs configuration file."
    echo ""
    echo "Tip: To generate a suitable 256-bit key, you can use the following command:"
    echo "  botan rng --format=hex 32"
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

# Ensure FILE_PATH ends with a slash
FILE_PATH="${FILE_PATH%/}/"

# Check if directory exists
if [ ! -d "$DIRECTORY" ]; then
    echo "Error: Directory does not exist."
    exit 1
fi

# Validate the key (hex encoded 256-bit key is 64 characters long)
if ! [[ $KEY =~ ^[0-9A-Fa-f]{64}$ ]]; then
    echo "Error: Invalid key. Please provide a 256-bit key in hexadecimal format (64 characters)."
    echo "Tip: You can generate a suitable key using: botan rng --format=hex 32"
    exit 1
fi

# Get the base name of the directory
BASE_NAME=$(basename "$DIRECTORY")
ENCRYPTED_ARCHIVE="${FILE_PATH}${BASE_NAME}.tar.gz.aes256gcm.enc"
NONCE_FILE="${FILE_PATH}${BASE_NAME}.nonce"

# Function to encrypt
encrypt() {
    echo "Encrypting $DIRECTORY..."
    
    # Create a temporary directory
    TEMP_DIR=$(mktemp -d)
    
    # Create an archive of the source directory
    tar -czf "$TEMP_DIR/$BASE_NAME.tar.gz" -C "$DIRECTORY" .
    
    # Generate a random 96-bit nonce in hex format
    NONCE=$(botan rng --format=hex 12)
    
    # Save the nonce to a file
    echo -n "$NONCE" > "$NONCE_FILE"
    
    # Encrypt the archive using Botan with AES-256/GCM
    botan cipher --cipher=AES-256/GCM --key="$KEY" --nonce="$NONCE" "$TEMP_DIR/$BASE_NAME.tar.gz" > "$ENCRYPTED_ARCHIVE"
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    echo "Encryption complete. Encrypted archive: $ENCRYPTED_ARCHIVE"
    echo "Nonce saved to: $NONCE_FILE"
}

# Function to decrypt
decrypt() {
    echo "Decrypting $ENCRYPTED_ARCHIVE..."
    
    # Check if nonce file exists
    if [ ! -f "$NONCE_FILE" ]; then
        echo "Error: Nonce file $NONCE_FILE not found."
        exit 1
    fi
    
    # Read the nonce from the file
    NONCE=$(cat "$NONCE_FILE")
    
    # Create a temporary directory
    TEMP_DIR=$(mktemp -d)
    
    # Decrypt the archive using Botan
    botan cipher --decrypt --cipher=AES-256/GCM --key="$KEY" --nonce="$NONCE" "$ENCRYPTED_ARCHIVE" > "$TEMP_DIR/$BASE_NAME.tar.gz"
    
    # Check if decryption was successful
    if [ $? -ne 0 ]; then
        echo "Error: Decryption failed. This could be due to an incorrect key or corrupted file."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Unpack the archive, overwriting existing files
    tar -xzf "$TEMP_DIR/$BASE_NAME.tar.gz" -C "$DIRECTORY"
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    echo "Decryption and unpacking complete. Files restored to $DIRECTORY"
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
        echo "Error: Invalid operation. Use 'encrypt' or 'decrypt'."
        usage
        exit 1
        ;;
esac