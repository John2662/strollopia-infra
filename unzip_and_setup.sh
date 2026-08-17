#!/usr/bin/env bash
# Run on the NEW machine after copying the backup zip.
# Usage: bash unzip_and_setup.sh ~/strollopia_backup_YYYY-MM-DD.zip
#
# What this does:
#   1. Extracts everything back into /home/john  (same paths, different machine)
#   2. Fixes SSH key permissions
#   3. Invokes setup_dev_machine.sh to install all required software

set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m'
ok() { echo -e "${GREEN}✓ $1${NC}"; }

ZIP="${1:-}"
if [ -z "$ZIP" ] || [ ! -f "$ZIP" ]; then
    echo "Usage: bash unzip_and_setup.sh <path-to-backup-zip>"
    exit 1
fi

# ── 1. Extract ─────────────────────────────────────────────────────────────────
echo "Extracting $ZIP into $HOME ..."
unzip -o -q "$ZIP" -d "$HOME"   # -o = overwrite existing files without prompting
ok "Extracted"

# ── 2. SSH permissions ────────────────────────────────────────────────────────
if [ -d "$HOME/.ssh" ]; then
    chmod 700 "$HOME/.ssh"
    find "$HOME/.ssh" -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
    find "$HOME/.ssh" -type f -name "*.pub"                 -exec chmod 644 {} \;
    [ -f "$HOME/.ssh/authorized_keys" ] && chmod 600 "$HOME/.ssh/authorized_keys"
    [ -f "$HOME/.ssh/known_hosts" ]     && chmod 644 "$HOME/.ssh/known_hosts"
    [ -f "$HOME/.ssh/config" ]          && chmod 600 "$HOME/.ssh/config"
    ok "SSH permissions fixed"
fi

# ── 3. Install dev tools ──────────────────────────────────────────────────────
SETUP="$HOME/strollopia_git_hub/setup_dev_machine.sh"
if [ -f "$SETUP" ]; then
    echo ""
    echo "Running setup_dev_machine.sh ..."
    bash "$SETUP"
else
    echo "setup_dev_machine.sh not found at $SETUP — run it manually."
fi
