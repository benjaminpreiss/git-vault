#!/bin/bash

# git-vault setup script
# This script downloads and sets up git-vault in a user's repository

set -e

# Default installation directory
DEFAULT_INSTALL_DIR=".git-vault"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -d, --dir DIR    Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  -h, --help       Show this help message"
    exit 1
}

# Parse command line arguments
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if we're in a git repository
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    print_error "This script must be run from within a git repository."
    exit 1
fi

GIT_ROOT=$(git rev-parse --show-toplevel)
print_info "Git repository root: $GIT_ROOT"

# Create installation directory
FULL_INSTALL_PATH="$GIT_ROOT/$INSTALL_DIR"
print_info "Installing git-vault to: $FULL_INSTALL_PATH"

if [ -d "$FULL_INSTALL_PATH" ]; then
    print_warning "Directory $FULL_INSTALL_PATH already exists. Contents may be overwritten."
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled."
        exit 0
    fi
fi

mkdir -p "$FULL_INSTALL_PATH"

# Download git-vault files
print_info "Downloading git-vault files..."

# Base URL for raw files (adjust this to your actual repository)
BASE_URL="https://raw.githubusercontent.com/benjaminpreiss/git-vault/main"

# Download core files
files_to_download=(
    "locker.sh"
    "encrypt_decrypt.sh"
)

for file in "${files_to_download[@]}"; do
    print_info "Downloading $file..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$BASE_URL/$file" -o "$FULL_INSTALL_PATH/$file"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$BASE_URL/$file" -O "$FULL_INSTALL_PATH/$file"
    else
        print_error "Neither curl nor wget is available. Please install one of them."
        exit 1
    fi
    chmod +x "$FULL_INSTALL_PATH/$file"
done

# Create .git-vault-dirs if it doesn't exist
CONFIG_FILE="$GIT_ROOT/.git-vault-dirs"
if [ ! -f "$CONFIG_FILE" ]; then
    print_info "Creating .git-vault-dirs configuration file..."
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
    print_success "Created .git-vault-dirs with example configuration."
    print_info "Edit .git-vault-dirs to add directory paths you want to encrypt (one per line)."
fi

# Update .gitignore
GITIGNORE_FILE="$GIT_ROOT/.gitignore"
print_info "Updating .gitignore..."

# Add .git-vault.env to .gitignore (but not the encrypted files)
if [ ! -f "$GITIGNORE_FILE" ] || ! grep -q "^\.git-vault\.env$" "$GITIGNORE_FILE"; then
    echo ".git-vault.env" >> "$GITIGNORE_FILE"
    print_info "Added .git-vault.env to .gitignore"
fi

# Add secret directories from .git-vault-dirs to .gitignore
if [ -f "$CONFIG_FILE" ]; then
    print_info "Adding secret directories to .gitignore..."
    
    # Read directories from plain text file using only bash built-ins
    read_directories() {
        local config_file="$1"
        
        if [ ! -f "$config_file" ]; then
            return 1
        fi
        
        while IFS= read -r line || [ -n "$line" ]; do
            # Trim leading and trailing whitespace using bash parameter expansion
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            
            # Skip empty lines and comments (lines starting with #)
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            
            echo "$line"
        done < "$config_file"
    }
    
    read_directories "$CONFIG_FILE" | while IFS= read -r dir; do
        if [ -n "$dir" ]; then
            # Add directory to .gitignore with encrypted file exceptions if not already present
            if ! grep -q "^$dir/\*$" "$GITIGNORE_FILE" 2>/dev/null && ! grep -q "^$dir$" "$GITIGNORE_FILE" 2>/dev/null; then
                echo "" >> "$GITIGNORE_FILE"
                echo "# Added by git-vault for $dir" >> "$GITIGNORE_FILE"
                echo "$dir/*" >> "$GITIGNORE_FILE"
                echo "!$dir/*.nonce" >> "$GITIGNORE_FILE"
                echo "!$dir/*.tar.gz.aes256gcm.enc" >> "$GITIGNORE_FILE"
                print_info "Added $dir/ to .gitignore with encrypted file exceptions"
            fi
        fi
    done
fi

# Create or update pre-commit hook
HOOKS_DIR="$GIT_ROOT/.git/hooks"
PRE_COMMIT_HOOK="$HOOKS_DIR/pre-commit"

print_info "Setting up pre-commit hook..."

# Create hooks directory if it doesn't exist
mkdir -p "$HOOKS_DIR"

# Git-vault hook content
GIT_VAULT_HOOK_CONTENT='
# === git-vault pre-commit hook START ===
# Automatically encrypts directories before commit

# Get the git repo root directory
repo_root=$(git rev-parse --show-toplevel)

# Run the locker.sh script
"${repo_root}/'$INSTALL_DIR'/locker.sh" lock

# Check the exit status of the script
if [ $? -ne 0 ]; then
    echo "Error: git-vault lock failed"
    exit 1
fi

# Stage encrypted files
find "$repo_root" -name "*.nonce" -o -name "*.tar.gz.aes256gcm.enc" | while read file; do
    if [ -f "$file" ]; then
        git add "$file"
    fi
done

# Check if any files were staged
if ! git diff --cached --quiet; then
    echo "Staged encrypted files for commit"
fi
# === git-vault pre-commit hook END ===
'

if [ -f "$PRE_COMMIT_HOOK" ]; then
    # Check if git-vault hook is already present
    if grep -q "git-vault pre-commit hook" "$PRE_COMMIT_HOOK"; then
        print_info "git-vault pre-commit hook already exists, skipping installation."
    else
        print_info "Existing pre-commit hook found. Appending git-vault functionality..."
        # Backup existing hook
        cp "$PRE_COMMIT_HOOK" "$PRE_COMMIT_HOOK.backup"
        print_info "Backed up existing pre-commit hook to pre-commit.backup"
        
        # Append git-vault hook to existing hook
        echo "$GIT_VAULT_HOOK_CONTENT" >> "$PRE_COMMIT_HOOK"
        print_success "git-vault functionality added to existing pre-commit hook."
    fi
else
    # Create new pre-commit hook
    cat > "$PRE_COMMIT_HOOK" << EOF
#!/bin/sh
$GIT_VAULT_HOOK_CONTENT

# If everything is successful, allow the commit
exit 0
EOF
    chmod +x "$PRE_COMMIT_HOOK"
    print_success "New pre-commit hook with git-vault functionality installed."
fi

# Create wrapper script in git root for easy access
WRAPPER_SCRIPT="$GIT_ROOT/git-vault"
cat > "$WRAPPER_SCRIPT" << EOF
#!/bin/bash
# git-vault wrapper script
exec "\$(git rev-parse --show-toplevel)/$INSTALL_DIR/locker.sh" "\$@"
EOF
chmod +x "$WRAPPER_SCRIPT"

print_success "git-vault installation completed!"
echo
print_info "Next steps:"
echo "1. Edit .git-vault-dirs to specify directories to encrypt"
echo "2. Run './git-vault lock' to encrypt directories"
echo "3. Commit your changes - encryption will happen automatically via pre-commit hook"
echo
print_info "Commands:"
echo "  ./git-vault lock    - Encrypt directories"
echo "  ./git-vault unlock  - Decrypt directories"
echo
print_warning "Keep your .git-vault.env file secure and backed up separately!"