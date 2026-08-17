#!/bin/bash
# Syncs clipboard between this machine (X11) and the remote Wayland machine.
# Uses mDNS hostname so it survives IP changes, and ControlMaster to reuse
# the SSH connection rather than opening a new one every second.

REMOTE_HOST="${1:-john-ASUS-V16.local}"
REMOTE_USER="john"
REMOTE="$REMOTE_USER@$REMOTE_HOST"
CONTROL_SOCKET="/tmp/clipboard-sync-ssh.sock"
LAST_LOCAL=""
LAST_REMOTE=""
CONNECTED=false

ssh_cmd() {
    ssh -o ControlMaster=auto \
        -o ControlPath="$CONTROL_SOCKET" \
        -o ControlPersist=60 \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o ServerAliveInterval=10 \
        -o ServerAliveCountMax=3 \
        "$REMOTE" "$@"
}

ensure_connected() {
    if ssh_cmd true 2>/dev/null; then
        if [ "$CONNECTED" = false ]; then
            echo "[$(date '+%H:%M:%S')] Connected to $REMOTE"
            CONNECTED=true
        fi
        return 0
    else
        if [ "$CONNECTED" = true ]; then
            echo "[$(date '+%H:%M:%S')] Lost connection to $REMOTE — retrying..."
            CONNECTED=false
            rm -f "$CONTROL_SOCKET"
        fi
        return 1
    fi
}

cleanup() {
    echo "Stopping clipboard sync."
    ssh -O exit -o ControlPath="$CONTROL_SOCKET" "$REMOTE" 2>/dev/null
    rm -f "$CONTROL_SOCKET"
    exit 0
}
trap cleanup INT TERM

echo "Syncing clipboard with $REMOTE (Ctrl-C to stop)"

while true; do
    if ! ensure_connected; then
        sleep 5
        continue
    fi

    # Get remote clipboard (Wayland)
    REMOTE_CLIP=$(ssh_cmd "wl-paste 2>/dev/null" 2>/dev/null)

    if [ -n "$REMOTE_CLIP" ] && [ "$REMOTE_CLIP" != "$LAST_REMOTE" ]; then
        echo -n "$REMOTE_CLIP" | xclip -selection clipboard
        LAST_REMOTE="$REMOTE_CLIP"
        LAST_LOCAL="$REMOTE_CLIP"
    fi

    # Get local clipboard (X11)
    LOCAL_CLIP=$(xclip -selection clipboard -o 2>/dev/null)

    if [ -n "$LOCAL_CLIP" ] && [ "$LOCAL_CLIP" != "$LAST_LOCAL" ]; then
        echo -n "$LOCAL_CLIP" | ssh_cmd "wl-copy" 2>/dev/null
        LAST_LOCAL="$LOCAL_CLIP"
        LAST_REMOTE="$LOCAL_CLIP"
    fi

    sleep 1
done
