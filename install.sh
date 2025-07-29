#!/bin/bash
# git-vault one-liner installer
# Usage: curl -fsSL https://raw.githubusercontent.com/benjaminpreiss/git-vault/main/install.sh | bash
# Or: curl -fsSL https://raw.githubusercontent.com/benjaminpreiss/git-vault/main/install.sh | bash -s -- --dir custom-dir

# Download and execute the setup script
TEMP_SETUP=$(mktemp)
curl -fsSL "https://raw.githubusercontent.com/benjaminpreiss/git-vault/main/setup.sh" -o "$TEMP_SETUP"
chmod +x "$TEMP_SETUP"
"$TEMP_SETUP" "$@"
rm -f "$TEMP_SETUP"