#!/bin/bash
# Creates a GNOME desktop launcher for strollopia_git_hub/todo.html.
# Run once after cloning the repo on a new machine.
# Usage: bash install_todo_launcher.sh

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TODO_FILE="$REPO_DIR/todo.html"
DESKTOP_FILE="$HOME/Desktop/strollopia_todo.desktop"

# Pick firefox if available, fall back to google-chrome, then xdg-open
if command -v firefox &>/dev/null; then
  BROWSER="firefox"
elif command -v google-chrome &>/dev/null; then
  BROWSER="google-chrome"
else
  BROWSER="xdg-open"
fi

cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=strollopia_todo.html
Exec=$BROWSER $TODO_FILE
Icon=text-html
Terminal=false
EOF

chmod +x "$DESKTOP_FILE"
echo "Launcher created at $DESKTOP_FILE (using $BROWSER)"
echo "If GNOME marks it untrusted, right-click → Allow Launching"
