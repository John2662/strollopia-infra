# New Machine Setup — Aug 15-16, 2026

## Overview

Migration of Strollopia development environment from old machine (Ubuntu 22.04) to new machine (Ubuntu 26.04), with both machines configured to work together as a complementary dev setup.

---

## Machines

| | Old Machine | New Machine |
|---|---|---|
| **OS** | Ubuntu 22.04 | Ubuntu 26.04 |
| **IP** | 10.0.0.213 | 10.0.0.76 |
| **CPU** | Intel i7-10710U (6c/12t, 4.7GHz) | Intel Core 7 240H (10c/16t, 5.2GHz) |
| **RAM** | 64 GB | 16 GB (1 free SODIMM slot, max 64GB) |
| **Disk** | 1.8 TB NVMe | 954 GB NVMe |
| **GPU** | Intel UHD (integrated) | Intel + NVIDIA RTX 5060 Mobile |
| **Display** | X11 | Wayland |

### RAM Upgrade Option (new machine)
- 1 free SODIMM slot — supports DDR5 5600 MT/s
- Existing stick: Samsung 16GB DDR5 5600 (M425R2GA3EB0-CWMOL)
- Adding a 32GB DDR5 5600 SODIMM gives 48GB total
- Memory Express price (Aug 2026): $599.98 (on sale, sale ends Aug 21)

---

## How the Two Machines Work Together

| Workload | Machine |
|----------|---------|
| strollopia-api Docker stack | Old machine (64GB RAM) |
| MySQL, databases | Old machine |
| Next.js dev servers (data_logger, strollopia-pwa) | New machine (faster CPU) |
| Android emulator | New machine (RTX 5060 GPU-accelerated) |
| Ollama / local LLMs | New machine (RTX 5060) |
| VS Code, browser, daily dev work | New machine |

New machine's `NEXT_PUBLIC_API_URL` points to `http://10.0.0.213:8000` (old machine's Docker API).

---

## Data Transfer

All repos and config transferred via SSH rsync (no USB — USB had Ubuntu installer ISO):

```bash
rsync -av --progress /home/john/strollopia_git_hub/ john@10.0.0.76:/home/john/strollopia_git_hub/
rsync -av --progress /home/john/.claude/ john@10.0.0.76:/home/john/.claude/
rsync -av /home/john/.agents/ john@10.0.0.76:/home/john/.agents/
rsync -av ~/.ssh/ john@10.0.0.76:/home/john/.ssh/
rsync -av ~/.aws/ john@10.0.0.76:/home/john/.aws/
rsync -av ~/.tmux.conf john@10.0.0.76:/home/john/.tmux.conf
rsync -av ~/.vimrc john@10.0.0.76:/home/john/.vimrc
```

Note: Python venvs (`env/`, `.env/`) were excluded from rsync — rebuilt locally.

---

## Repos Committed and Pushed Before Migration

Several repos had uncommitted changes that were committed before transfer:

| Repo | What was committed |
|------|--------------------|
| `strollopia-scripts` | API URL refactor (centralize via `get_api_base_url()`), `normalise_activity()` fix, acadian org data, org_files collection |
| `data_logger` | Trail features + voice memo implementation plan |
| `feature-registry` | `registry.yaml` (API auto-assigns sandbox slot), scout registration plan docs |
| `strollopia-native` | App assets (favicon) |
| `strollopia-org-setup` | blomidon, langwalk, pictou org configs, sandbox sb0/sb1 configs |
| `strollopia-pwa` | Trail features + voice memo implementation plan |

---

## Dev Tools Installed on New Machine

Run `setup_dev_machine.sh` (in `strollopia_git_hub/`) to install everything:

```bash
bash ~/strollopia_git_hub/setup_dev_machine.sh
```

| Tool | Version | Notes |
|------|---------|-------|
| Docker | 29.6.1 | Run `docker compose up` in strollopia-api |
| Node | 20.20.2 | Via nvm |
| GitHub CLI | 2.96.0 | Run `gh auth login` after setup |
| AWS CLI | 2.35.17 | Credentials copied from old machine |
| Bun | 1.3.14 | |
| Claude Code | 2.1.217 | Log in with `claude` |
| Expo CLI | 6.3.12 | |
| Chrome | 150 | |
| VS Code | 1.133.0 | |
| Android Studio | 2026.1.3 | SDK: Android 16, Emulator: Pixel 6a |
| Ollama | latest | Installed, no models pulled yet |
| KDE Connect | latest | Paired with old machine |
| Meld | latest | Diff/merge GUI |

### Manual installs needed:
- Brave browser — download .deb from brave.com
- Opera browser — download .deb from opera.com
- pCloud — `~/pCloud.AppImage` (log in to link account)
- Dropbox — `~/.dropbox-dist/dropboxd` (follow URL to link account)

---

## Python Virtual Environments

| Repo | Venv location | Status |
|------|--------------|--------|
| `strollopia-api` | runs in Docker | No local venv needed |
| `strollopia-scripts` | `env/` | Rebuilt |
| `strollopia-org-setup` | `.env/` | Rebuilt |
| `strollopia-clean` | `env/` | Created fresh |

---

## Expo / React Native DevTools Fix

DevTools sandbox binary needs root ownership on Linux:

```bash
sudo chown root:root ~/.cache/dotslash/af/5aa55d5d0401a9f3a438c9deb082205f28e353/"React Native DevTools-linux-x64"/chrome-sandbox
sudo chmod 4755 ~/.cache/dotslash/af/5aa55d5d0401a9f3a438c9deb082205f28e353/"React Native DevTools-linux-x64"/chrome-sandbox
```

Or skip DevTools entirely (app still works):
```bash
EXPO_NO_REACT_DEVTOOLS=1 npx expo start
```

Add to `~/.bashrc` to make permanent:
```bash
echo 'export EXPO_NO_REACT_DEVTOOLS=1' >> ~/.bashrc
```

---

## Clipboard Sharing Between Machines

Synergy 3 handles keyboard/mouse sharing but clipboard doesn't work between X11 (old) and Wayland (new).

**Solution:** SSH clipboard bridge script at `~/strollopia_git_hub/sync-clipboard.sh`

Runs on the old machine, polls every second, syncs clipboard both directions using `xclip` (X11) and `wl-paste`/`wl-copy` (Wayland).

Configured to autostart at login via `~/.config/autostart/sync-clipboard.desktop`.

---

## Claude History Sync (Cron)

Cron jobs on old machine sync `~/.claude/` both directions every hour:

```
0 * * * * rsync -a --update /home/john/.claude/ john@10.0.0.76:/home/john/.claude/
5 * * * * rsync -a --update john@10.0.0.76:/home/john/.claude/ /home/john/.claude/
```

---

## File Transfer Between Machines

- **KDE Connect** — drag and drop in Nautilus, right-click → Send to device
- **rsync** — for bulk/directory transfers
- **scp** — quick single files (rsync preferred)

---

## Next Steps

- [ ] Upgrade old machine: Ubuntu 22.04 → 24.04 → 26.04 (once new machine is confirmed working)
- [ ] Pull Ollama models on new machine (`ollama pull llama3.2` etc.)
- [ ] Log out/in on new machine to activate Docker group membership
- [ ] Link pCloud account
- [ ] Link Dropbox account
- [ ] Install Brave and Opera from downloaded .deb files
