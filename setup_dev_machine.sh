#!/usr/bin/env bash
# Dev machine setup for strollopia projects on Ubuntu 26.04
# Run as your normal user (not root) — sudo is called where needed
# Usage: bash setup_dev_machine.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓ $1${NC}"; }
skip() { echo -e "${YELLOW}→ $1 already installed, skipping${NC}"; }
step() { echo -e "\n=== $1 ==="; }

# ── 0. SSH keys ───────────────────────────────────────────────────────────────
#
# If you copied keys from your old machine (via the backup zip), permissions
# are fixed below. If not, a new key pair is generated.
#
# After generation, add your public key to ALL of these:
#   1. GitHub.com        → Settings → SSH and GPG keys → New SSH key
#   2. dev.strollopia.com  → ssh-copy-id john@dev.strollopia.com
#   3. prod.strollopia.com → ssh-copy-id john@prod.strollopia.com
#   4. Any AWS EC2 instances you SSH into directly
#      (add via EC2 console → Key Pairs, or paste into ~/.ssh/authorized_keys
#       on the instance if you still have access via the old key)

step "SSH keys"
mkdir -p ~/.ssh
chmod 700 ~/.ssh

if [ -f "$HOME/.ssh/id_ed25519" ]; then
    chmod 600 ~/.ssh/id_ed25519
    chmod 644 ~/.ssh/id_ed25519.pub
    [ -f ~/.ssh/id_rsa ] && chmod 600 ~/.ssh/id_rsa
    [ -f ~/.ssh/id_rsa.pub ] && chmod 644 ~/.ssh/id_rsa.pub
    ok "SSH keys found — permissions fixed"
    echo ""
    echo "  Your public key (add to GitHub + servers if not already there):"
    echo "  ────────────────────────────────────────────────────────────────"
    cat ~/.ssh/id_ed25519.pub
    echo "  ────────────────────────────────────────────────────────────────"
else
    read -rp "  No SSH keys found. Generate a new ed25519 key? [y/N] " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        read -rp "  Email for key comment: " ssh_email
        ssh-keygen -t ed25519 -C "$ssh_email" -f ~/.ssh/id_ed25519 -N ""
        ok "New SSH key generated"
        echo ""
        echo "  Your public key — add it to ALL of the following:"
        echo "  ────────────────────────────────────────────────────────────────"
        cat ~/.ssh/id_ed25519.pub
        echo "  ────────────────────────────────────────────────────────────────"
        echo ""
        echo "  1. GitHub.com: Settings → SSH and GPG keys → New SSH key"
        echo "  2. dev.strollopia.com:  ssh-copy-id john@dev.strollopia.com"
        echo "  3. prod.strollopia.com: ssh-copy-id john@prod.strollopia.com"
        echo "  4. Any AWS EC2 instances you SSH into directly"
        echo ""
        echo "  Press Enter to continue once you've added it to GitHub..."
        read -r
    else
        echo "  Skipping — add SSH keys manually before using git"
    fi
fi

# ── 1. Core apt packages ──────────────────────────────────────────────────────

step "Core packages"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    unzip \
    build-essential \
    python3-pip \
    python3-venv \
    ca-certificates \
    gnupg
ok "Core packages installed"

# ── 2. Docker ─────────────────────────────────────────────────────────────────

step "Docker"
if command -v docker &>/dev/null; then
    skip "Docker ($(docker --version))"
else
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    sudo usermod -aG docker "$USER"
    ok "Docker installed — log out and back in for group membership to take effect"
fi

# ── 3. GitHub CLI ─────────────────────────────────────────────────────────────

step "GitHub CLI (gh)"
if command -v gh &>/dev/null && [[ "$(gh --version | head -1)" != *"2.4"* ]]; then
    skip "gh ($(gh --version | head -1))"
else
    sudo mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y gh
    ok "gh installed — run 'gh auth login' after setup"
fi

# ── 4. AWS CLI v2 ─────────────────────────────────────────────────────────────

step "AWS CLI v2"
if aws --version 2>/dev/null | grep -q "aws-cli/2"; then
    skip "AWS CLI v2 ($(aws --version 2>&1 | head -1))"
else
    TMP=$(mktemp -d)
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
        -o "$TMP/awscliv2.zip"
    unzip -q "$TMP/awscliv2.zip" -d "$TMP"
    sudo "$TMP/aws/install" --update
    rm -rf "$TMP"
    ok "AWS CLI v2 installed"
fi

# ── 5. nvm + Node 20 ─────────────────────────────────────────────────────────

step "nvm + Node 20"
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"
    skip "nvm ($(nvm --version))"
else
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    source "$NVM_DIR/nvm.sh"
    ok "nvm installed"
fi

if node --version 2>/dev/null | grep -q "v20"; then
    skip "Node $(node --version)"
else
    nvm install 20
    nvm use 20
    nvm alias default 20
    ok "Node $(node --version) installed and set as default"
fi

# ── 6. Claude Code ───────────────────────────────────────────────────────────

step "Claude Code"
if command -v claude &>/dev/null; then
    skip "Claude Code ($(claude --version 2>/dev/null | head -1))"
else
    npm install -g @anthropic-ai/claude-code
    ok "Claude Code installed"
fi

# ── 7. Expo CLI ───────────────────────────────────────────────────────────────

step "Expo CLI"
if command -v expo &>/dev/null; then
    skip "Expo ($(expo --version 2>/dev/null))"
else
    npm install -g expo-cli
    ok "Expo CLI installed"
fi

# ── 8. Bun ───────────────────────────────────────────────────────────────────

step "Bun"
if command -v bun &>/dev/null; then
    skip "Bun ($(bun --version))"
else
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
    ok "Bun installed"
fi

# ── 9. Snap apps ─────────────────────────────────────────────────────────────

step "Snap apps"
sudo apt-get install -y snapd

declare -A SNAPS=(
    ["android-studio"]="android-studio --classic"
    ["code"]="code --classic"
    ["dbeaver-ce"]="dbeaver-ce --classic"
    ["postman"]="postman"
    ["slack"]="slack"
    ["ngrok"]="ngrok"
)

for cmd in "${!SNAPS[@]}"; do
    if snap list "$cmd" &>/dev/null 2>&1; then
        skip "$cmd"
    else
        # shellcheck disable=SC2086
        if sudo snap install ${SNAPS[$cmd]}; then
            ok "$cmd installed"
        else
            echo "  ✗ snap install $cmd failed — skipping"
        fi
    fi
done

# flameshot via apt — snap version has broken KDE deps on Ubuntu 26.04
if command -v flameshot &>/dev/null; then
    skip "flameshot ($(flameshot --version 2>/dev/null | head -1))"
else
    sudo apt-get install -y flameshot
    ok "flameshot installed"
fi

# ── 10. Android SDK environment ──────────────────────────────────────────────

step "Android SDK environment variables"
BASHRC="$HOME/.bashrc"
if grep -q "ANDROID_HOME" "$BASHRC"; then
    skip "Android env vars already in ~/.bashrc"
else
    cat >> "$BASHRC" <<'EOF'

# Android SDK (set by setup_dev_machine.sh)
export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools
EOF
    ok "Android env vars added to ~/.bashrc"
    echo "  ↳ Open Android Studio, run the setup wizard, then reload your shell"
fi

# ── 11. Chrome ───────────────────────────────────────────────────────────────

step "Google Chrome"
if command -v google-chrome &>/dev/null; then
    skip "Chrome ($(google-chrome --version))"
else
    TMP=$(mktemp -d)
    wget -q "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" \
        -O "$TMP/chrome.deb"
    sudo dpkg -i "$TMP/chrome.deb" || sudo apt-get install -f -y
    rm -rf "$TMP"
    ok "Chrome installed"
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════"
echo " Setup complete. Next steps:"
echo "════════════════════════════════════════"
echo " 1. Log out and back in (Docker group)"
echo " 2. SSH key — add ~/.ssh/id_ed25519.pub to:"
echo "      • GitHub.com → Settings → SSH and GPG keys"
echo "      • ssh-copy-id john@dev.strollopia.com"
echo "      • ssh-copy-id john@prod.strollopia.com"
echo "      • Any AWS EC2 instances you SSH into directly"
echo " 3. Verify GitHub SSH: ssh -T git@github.com"
echo " 4. gh auth login"
echo " 5. aws configure"
echo " 6. Open Android Studio → run setup wizard → install SDK + emulator"
echo " 7. source ~/.bashrc  (or open a new terminal)"
echo " 8. claude  # log in to Claude Code"
echo ""
