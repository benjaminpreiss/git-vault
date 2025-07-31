#!/bin/bash

# git-vault pre-commit hook script
# This script is called by the git pre-commit hook to automatically encrypt directories

# Get the git repo root directory
repo_root=$(git rev-parse --show-toplevel)

# Get the directory where this script is located
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run the locker.sh script in quiet mode
"${script_dir}/locker.sh" --quiet lock

# Check the exit status
if [ $? -ne 0 ]; then
    echo "git-vault: encryption failed" >&2
    exit 1
fi

# Stage encrypted files silently from .git-vault/data/
if [ -d "$repo_root/.git-vault/data" ]; then
    find "$repo_root/.git-vault/data" -name "*.nonce" -o -name "*.aes256gcm.enc" 2>/dev/null | while IFS= read -r file; do
        if [ -f "$file" ]; then
            git add "$file" 2>/dev/null
        fi
    done
fi

exit 0