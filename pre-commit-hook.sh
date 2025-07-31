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

# Stage all files from .git-vault directory (including data/, state.hash, etc.)
if [ -d "$repo_root/.git-vault" ]; then
    find "$repo_root/.git-vault" -type f 2>/dev/null | while IFS= read -r file; do
        git add "$file" 2>/dev/null
    done
fi

exit 0