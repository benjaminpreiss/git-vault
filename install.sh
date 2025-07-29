#!/bin/bash
# git-vault one-liner installer
#
# Basic installation (recommended):
#   curl -fsSL https://raw.githubusercontent.com/benjaminpreiss/git-vault/main/install.sh | bash
#
# Custom installation directory (advanced):
#   curl -fsSL https://raw.githubusercontent.com/benjaminpreiss/git-vault/main/install.sh | bash -s -- --dir .my-vault
#
# IMPORTANT: The --dir parameter specifies where to install git-vault scripts, NOT which directories to encrypt.
# To configure which directories to encrypt, edit .git-vault-dirs after installation:
#   echo "secrets" >> .git-vault-dirs
#   echo "private" >> .git-vault-dirs

# Download and execute the setup script
TEMP_SETUP=$(mktemp)
curl -fsSL "https://raw.githubusercontent.com/benjaminpreiss/git-vault/main/setup.sh" -o "$TEMP_SETUP"
chmod +x "$TEMP_SETUP"
"$TEMP_SETUP" "$@"
rm -f "$TEMP_SETUP"