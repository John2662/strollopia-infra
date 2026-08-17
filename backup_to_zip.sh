#!/usr/bin/env bash
# Creates a portable backup zip of the strollopia dev environment.
# Run from your home directory on the OLD machine:
#   bash ~/strollopia_git_hub/backup_to_zip.sh
#
# Output: ~/strollopia_backup_YYYY-MM-DD.zip (~300-500 MB typical)
# Copy that single file to your new machine, then run unzip_and_setup.sh there.

set -euo pipefail

BACKUP="$HOME/strollopia_backup_$(date +%F).zip"

echo "Building $BACKUP ..."

# ── dot-files ──────────────────────────────────────────────────────────────────
FILES_TO_ZIP=()

for f in .gitconfig .bashrc .bash_aliases .profile; do
    [ -f "$HOME/$f" ] && FILES_TO_ZIP+=("$f")
done

# ── directories zipped flat (cd to ~ first so paths inside zip are relative) ──
cd "$HOME"

# Collect directory targets (only those that exist)
DIRS_TO_ZIP=()
[ -d strollopia_git_hub ]       && DIRS_TO_ZIP+=(strollopia_git_hub)
[ -d .aws ]                      && DIRS_TO_ZIP+=(.aws)
[ -d .ssh ]                      && DIRS_TO_ZIP+=(.ssh)

# .claude — include but skip the large re-downloadable/ephemeral subdirs
# We include projects/, context-mode/, file-history/, and small top-level files.
if [ -d .claude ]; then
    DIRS_TO_ZIP+=(.claude)
fi

zip -r "$BACKUP" \
    "${FILES_TO_ZIP[@]}" \
    "${DIRS_TO_ZIP[@]}" \
    --exclude "*/node_modules/*" \
    --exclude "*/__pycache__/*" \
    --exclude "*/.mypy_cache/*" \
    --exclude "*/.pytest_cache/*" \
    --exclude "*/venv/*" \
    --exclude "*/.venv/*" \
    --exclude "*/dist/*" \
    --exclude "*/.git/objects/pack/*" \
    --exclude "*.pyc" \
    --exclude ".claude/plugins/*" \
    --exclude ".claude/debug/*" \
    -q

SIZE=$(du -sh "$BACKUP" | cut -f1)
echo "Done. $BACKUP  ($SIZE)"
echo ""
echo "Copy this file to your new machine, then run:"
echo "  bash ~/strollopia_git_hub/unzip_and_setup.sh ~/strollopia_backup_*.zip"
