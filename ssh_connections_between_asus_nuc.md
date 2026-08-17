# SSH Connections Between NUC and ASUS

## Machines

| Name | Hostname | mDNS | OS | Display |
|---|---|---|---|---|
| Intel NUC | `john-NUC10i7FNK` | `john-NUC10i7FNK.local` | Ubuntu 22.04 LTS | X11 |
| ASUS laptop | `john-ASUS-V16` | `john-ASUS-V16.local` | Ubuntu 26.04 LTS | Wayland |

Both machines use user `john` (UID 1000) with the same SSH key pair (`~/.ssh/id_ed25519`).
mDNS hostnames resolve correctly regardless of IP address changes — no hardcoded IPs anywhere.

---

## What Starts Automatically on Boot

### NUC — autostart entries in `~/.config/autostart/`

| File | What it does |
|---|---|
| `mount-asus.desktop` | Refreshes ASUS host key, waits for ASUS to be reachable, mounts ASUS home at `~/asus` |
| `sync-clipboard.desktop` | Refreshes ASUS host key, starts clipboard sync (auto-reconnects if connection drops) |
| *(Synergy — via GNOME)* | Synergy 3 starts automatically via `synergy.service` + GNOME session management |

### ASUS — autostart entries in `~/.config/autostart/`

| File | What it does |
|---|---|
| `mount-nuc.desktop` | Refreshes NUC host key, waits for NUC to be reachable, mounts NUC home at `~/nuc` |
| `synergy.desktop` | Starts Synergy 3 server minimized to tray |

### Startup Order

The NUC's autostart waits up to 5 minutes for the ASUS to be reachable before mounting.
The ASUS's autostart waits up to 5 minutes for the NUC to be reachable before mounting.
Both can boot in either order — they will find each other once both are up.

---

## File Access

### NUC — access ASUS files

```bash
ls ~/asus                          # Browse ASUS home directory
ls ~/asus/strollopia_git_hub/      # Browse ASUS repos
```

### ASUS — access NUC files

```bash
ls ~/nuc                           # Browse NUC home directory
ls ~/nuc/strollopia_git_hub/       # Browse NUC repos
```

---

## File Transfer

### Copy a file (metadata preserved)

```bash
# NUC → ASUS
cp -p ~/somefile ~/asus/somefile

# ASUS → NUC
cp -p ~/somefile ~/nuc/somefile
```

`cp -p` preserves permissions, timestamps, and ownership. Works correctly because both
machines run the same user (john, UID 1000) with modern OpenSSH sftp-server.

### Sync a directory

```bash
# NUC → ASUS (explicit rsync, not via mount)
rsync -av --progress ~/mydir/ john@john-ASUS-V16.local:~/mydir/

# ASUS → NUC
rsync -av --progress ~/mydir/ john@john-NUC10i7FNK.local:~/mydir/
```

Use `rsync` over SSH (not via the sshfs mount) for large transfers — it's faster and resumable.

### Use the file manager

Both `~/asus` and `~/nuc` appear as normal folders in Nautilus/Files.
Drag and drop works as expected.

---

## Clipboard Sync

Clipboard is synced bidirectionally between the two machines via SSH.

- Copy on NUC → paste on ASUS ✅
- Copy on ASUS → paste on NUC ✅
- Synergy clipboard sharing is disabled (Wayland incompatibility); this SSH script replaces it.

Script location: `~/strollopia_git_hub/sync-clipboard.sh`

To restart manually if clipboard sync stops working:

```bash
pkill -f sync-clipboard.sh; bash ~/strollopia_git_hub/sync-clipboard.sh &
```

---

## Keyboard and Mouse Sharing (Synergy 3)

Synergy shares the ASUS keyboard and mouse with the NUC screen.

| Machine | Role | How it starts |
|---|---|---|
| ASUS | Server (provides keyboard/mouse) | `~/.config/autostart/synergy.desktop` |
| NUC | Client (receives input) | GNOME session + `synergy.service` |

Move the mouse to the edge of the ASUS screen to switch to the NUC screen and back.

Note: Synergy clipboard sync is **disabled** — cross-machine clipboard is handled by
`sync-clipboard.sh` instead (Synergy's clipboard sync does not work on Wayland).

---

## SSH Access

Both machines can SSH to each other without a password.

```bash
# From NUC
ssh john@john-ASUS-V16.local

# From ASUS
ssh john@john-NUC10i7FNK.local
```

Run remote commands:

```bash
# Run a command on ASUS from the NUC
ssh john@john-ASUS-V16.local "df -h"

# Run a command on NUC from the ASUS
ssh john@john-NUC10i7FNK.local "df -h"
```

---

## Troubleshooting

### Mount is not showing files / stale mount

```bash
# On NUC — remount ASUS
fusermount -u ~/asus 2>/dev/null
ssh-keygen -R john-ASUS-V16.local -q
ssh-keyscan -H john-ASUS-V16.local >> ~/.ssh/known_hosts
sshfs -o BatchMode=yes,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 \
  john@john-ASUS-V16.local:/home/john ~/asus

# On ASUS — remount NUC
fusermount -u ~/nuc 2>/dev/null
ssh-keygen -R john-NUC10i7FNK.local -q
ssh-keyscan -H john-NUC10i7FNK.local >> ~/.ssh/known_hosts
sshfs -o BatchMode=yes,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 \
  john@john-NUC10i7FNK.local:/home/john ~/nuc
```

### Clipboard sync not working

```bash
# Check if it's running (run on NUC)
pgrep -a -f sync-clipboard.sh

# Restart it
pkill -f sync-clipboard.sh
bash ~/strollopia_git_hub/sync-clipboard.sh &

# Check the log
cat /tmp/sync-clipboard.log
```

### SSH connection refused / host key error

If a machine reboots, its SSH host key may change (this is automatically handled on
the next login via the autostart scripts, but if you need to fix it manually):

```bash
# Fix ASUS key (run on NUC)
ssh-keygen -R john-ASUS-V16.local -q
ssh-keyscan -H john-ASUS-V16.local >> ~/.ssh/known_hosts

# Fix NUC key (run on ASUS)
ssh-keygen -R john-NUC10i7FNK.local -q
ssh-keyscan -H john-NUC10i7FNK.local >> ~/.ssh/known_hosts
```

### Synergy not connecting

1. Check Synergy is running on the ASUS: look for the Synergy icon in the system tray.
   If missing, open Synergy from the app menu — it should show "Server running."
2. On the NUC, Synergy restarts automatically. Give it 30 seconds after the ASUS is up.
3. If still not working, restart the NUC's Synergy service:
   ```bash
   systemctl --user restart synergy-session.service
   ```

---

## Key Files

### NUC

| Path | Purpose |
|---|---|
| `~/.config/autostart/mount-asus.desktop` | Autostart: mount ASUS at `~/asus` |
| `~/.config/autostart/sync-clipboard.desktop` | Autostart: clipboard sync |
| `~/.config/systemd/user/synergy-session.service` | Synergy client service |
| `~/strollopia_git_hub/sync-clipboard.sh` | Clipboard sync script |
| `~/asus/` | ASUS home directory (mounted) |

### ASUS

| Path | Purpose |
|---|---|
| `~/.config/autostart/mount-nuc.desktop` | Autostart: mount NUC at `~/nuc` |
| `~/.config/autostart/synergy.desktop` | Autostart: Synergy server |
| `~/nuc/` | NUC home directory (mounted) |
