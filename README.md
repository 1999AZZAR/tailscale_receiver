## Tailscale Taildrop: Auto‑Receive and Send

Automated Taildrop file reception as a reliable systemd service, plus a convenient sender with a device picker and Dolphin context‑menu integration.

### Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Features](#features)
- [Comparison of File Sharing Methods](#comparison-of-file-sharing-methods)
- [Quick Setup Examples](#quick-setup-examples)
  - [NFS](#nfs)
  - [SFTP](#sftp)
  - [SMB](#smb)
- [Requirements](#requirements)
- [Taildrop Setup Requirements](#taildrop-setup-requirements)
- [Install](#install)
  - [What Gets Installed](#what-gets-installed)
  - [Verify Installation](#verify-installation)
  - [Reinstall/Update](#reinstallupdate)
- [Configuration](#configuration)
  - [Receiver Settings](#receiver-settings)
  - [Sender Options](#sender-options)
- [Usage](#usage)
  - [Manage the Service](#manage-the-service)
  - [Send Files](#send-files)
- [Troubleshooting](#troubleshooting)
- [Security Notes](#security-notes)
- [Advanced Configuration](#advanced-configuration)
- [Uninstall](#uninstall)
- [Integration with Other Tools](#integration-with-other-tools)
  - [Contributing](#contributing)
- [How It Works](#how-it-works)
- [License](#license)
- [Changelog](#changelog)

---

### Overview

- Runs a background service that continuously accepts Taildrop files into your `Downloads/tailscale` folder and notifies you.
- Includes a sender script with GUI picker (kdialog/zenity/whiptail/CLI) and Dolphin right‑click integration.
- Designed for Linux systems using systemd.

### Quick Start

```bash
# 1) Make scripts executable
chmod +x install.sh uninstall.sh tailscale-receive.sh tailscale-send.sh

# 2) Install (you will be asked which user should receive files)
sudo ./install.sh

# 3) Check service and logs
sudo systemctl status tailscale-receive.service
sudo journalctl -u tailscale-receive.service -f

# 4) Optional: test sender
/usr/local/bin/tailscale-send.sh --help
```

Notes:

- Taildrop must be enabled in your tailnet admin.
- Tailscale must be installed and logged in on this device.

### Features

- Automated file reception via Taildrop
- Reliable systemd service with auto‑restart and exponential backoff
- Desktop notifications on receipt (notify‑send)
- Automatic ownership correction to your user
- Comprehensive health checks (internet + tailscale authentication)
- Smart sender with device picker and Dolphin integration
- Structured logging with timestamps and configurable levels
- Null-safe file detection handling special characters
- Security hardening with systemd sandboxing (configurable)
- Strict error handling with actionable error messages

### Comparison of File Sharing Methods

| Feature                 | `tailscale_receiver`                                                                                   | NFS (Network File System)                                                                        | FTP (File Transfer Protocol)                                                         | SMB (Server Message Block)                                                  |
|:----------------------- |:------------------------------------------------------------------------------------------------------ |:------------------------------------------------------------------------------------------------ |:------------------------------------------------------------------------------------ |:--------------------------------------------------------------------------- |
| Method Used             | Taildrop (peer‑to‑peer over secure Tailscale network)                                                  | Mounting shares (remote directories appear local)                                                | Client‑server (upload/download to a server)                                          | Network share access (shared folders/resources)                             |
| Ease of Use             | Easy. Designed for simplicity and automation in a Tailscale network.                                   | Moderate–Difficult. Requires server and client config, `/etc/exports`, firewall, automount, etc. | Easy. Many graphical clients; SFTP/FTPS variants common.                             | Easy. Native on Windows; good support via Samba on Linux and macOS.         |
| Security                | High. Tailscale’s end‑to‑end encryption and identity.                                                  | Moderate. Can be complex; often relies on LAN isolation, Kerberos, or TLS extensions.            | Low by default (FTP is plaintext). Use SFTP (over SSH) or FTPS for security.         | Moderate–High. SMBv3 supports encryption/signing; depends on configuration. |
| Performance             | Good. Limited by Tailscale overlay and path between peers.                                             | High. Excellent on LAN; kernel‑level I/O.                                                        | Good. Typically adequate for transfers; latency‑sensitive control channel.           | High. Very fast on LAN; improved with SMBv3 multichannel and modern stacks. |
| Use Case                | Securely and automatically receive files from your Tailnet devices; personal and small team workflows. | Share directories as if local across Unix/Linux systems; POSIX semantics.                        | Simple uploads/downloads; legacy integrations; public file distribution (anonymous). | Windows file/print shares; mixed‑OS LAN environments; AD integration.       |
| Platform Support        | Linux (scripts target `systemd`), works with any Tailnet devices as senders.                           | Primarily Linux/Unix; clients exist for other OSes.                                              | Cross‑platform (FTP/SFTP/FTPS clients abundant).                                     | Primarily Windows; widely supported on Linux (Samba) and macOS.             |
| Setup Complexity        | Low. Install and choose user; no port forwarding or firewall tweaks.                                   | Medium–High. Export lists, uid/gid mapping, firewall rules.                                      | Low–Medium. Stand up an FTP/SFTP server, manage users/keys, open ports.              | Medium. Configure Samba/Windows shares, permissions, and firewall.          |
| NAT/Firewall Traversal  | Excellent. Uses Tailscale’s NAT traversal; no inbound ports.                                           | Poor–Moderate. Usually LAN only or needs VPN/ports.                                              | Moderate. Requires open ports (20/21 for FTP, 22 for SFTP, 990/989 for FTPS).        | Moderate. Requires open ports (e.g., 445), often LAN or VPN.                |
| Identity/Access Control | Tailnet identity; access scoped to your devices.                                                       | OS‑level users/groups; Kerberos/LDAP possible.                                                   | Local server accounts or system users/SSH keys.                                      | AD/LDAP or local users; granular share/file ACLs.                           |
| Offline Behavior        | Queue on sender; receiver processes on next loop when online.                                          | Not applicable; mount must be reachable.                                                         | Server must be reachable; clients retry/reconnect.                                   | Server must be reachable; clients retry/reconnect.                          |
| Best For                | Quick, secure, zero‑exposure transfers within a personal/team Tailnet.                                 | Seamless remote filesystem access and POSIX workflows.                                           | Interop with legacy systems and simple public distribution via hardened variants.    | Windows‑centric networks needing shared folders and permissions.            |

### Quick Setup Examples

These are intentionally minimal to illustrate the moving parts. Harden and tailor for your environment.

#### NFS

Server (Linux):

```bash
sudo apt install nfs-kernel-server
echo "/srv/share 192.168.0.0/24(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
sudo mkdir -p /srv/share && sudo chown $USER:$USER /srv/share
sudo exportfs -ra
sudo systemctl enable --now nfs-server
```

Client (Linux):

```bash
sudo apt install nfs-common
sudo mkdir -p /mnt/share
sudo mount -t nfs4 nfs-server:/srv/share /mnt/share
# Optional persistent mount in /etc/fstab:
# nfs-server:/srv/share  /mnt/share  nfs4  defaults,_netdev  0  0
```

#### SFTP

Server (Linux, OpenSSH):

```bash
sudo apt install openssh-server
sudo systemctl enable --now ssh
# Create a user and directory for uploads
sudo adduser sftpuser
sudo -u sftpuser mkdir -p /home/sftpuser/uploads
# Optional chrooted SFTP subsystem (advanced): edit /etc/ssh/sshd_config and add a Match block
```

Client:

```bash
# Upload
sftp sftpuser@server <<'EOF'
put /path/to/local/file /home/sftpuser/uploads/
EOF
# Or using scp (over SSH)
scp /path/to/local/file sftpuser@server:/home/sftpuser/uploads/
```

#### SMB

Server (Linux via Samba):

```bash
sudo apt install samba
sudo mkdir -p /srv/samba/share && sudo chown $USER:$USER /srv/samba/share
sudo bash -c 'cat >>/etc/samba/smb.conf' <<'SMB'
[public]
   path = /srv/samba/share
   browseable = yes
   read only = no
   guest ok = yes
SMB
sudo systemctl restart smbd nmbd
# Optional user mapping (non-guest):
# sudo smbpasswd -a $USER
```

Client:

```bash
# Linux mount
sudo apt install cifs-utils
sudo mkdir -p /mnt/smb
sudo mount -t cifs //server/public /mnt/smb -o guest,uid=$(id -u),gid=$(id -g)

# Windows
# Use File Explorer → \\server\public
```

### Requirements

- Linux with systemd (Ubuntu/Debian/Fedora/Arch, etc.)
- Tailscale installed and logged in
- Root privileges for install/uninstall
- `notify-send` (usually part of libnotify; optional on headless)
- For sending features:
  - One of: `kdialog`, `zenity`, or `whiptail` (optional; CLI fallback available)
  - `jq` (optional) for robust device detection
  - KDE Plasma + Dolphin (optional) for context menu

### Taildrop Setup Requirements

1) Enable Taildrop in your tailnet admin
   
   ```bash
   # Visit your admin console and enable "Send Files"
   ```

2) Verify Tailscale status
   
   ```bash
   tailscale status
   ```

3) Optional: basic Taildrop smoke test
   
   ```bash
   # List pending receives
   tailscale file get
   
   # Send to another device (replace device-name)
   tailscale file cp /path/to/test/file device-name:
   ```

4) Allow your user to send without sudo (recommended)
   
   ```bash
   sudo tailscale set --operator=$USER
   ```

### Install

1) Obtain the files (clone or download). Place scripts in one directory.
2) Make scripts executable:
   
   ```bash
   chmod +x install.sh uninstall.sh tailscale-receive.sh tailscale-send.sh
   ```
3) Run the installer (asks for your target user and configures automatically):
   
   ```bash
   sudo ./install.sh
   ```

#### One‑Line Install (curl/wget)

Using curl:

```bash
bash -c 'set -euo pipefail; tmp=$(mktemp -d); cd "$tmp"; \
for f in install.sh tailscale-receive.sh tailscale-send.sh; do \
  curl -fsSLO "https://raw.githubusercontent.com/1999AZZAR/tailscale_receiver/master/$f"; \
done; chmod +x install.sh tailscale-receive.sh tailscale-send.sh; sudo ./install.sh'
```

Using wget:

```bash
bash -c 'set -euo pipefail; tmp=$(mktemp -d); cd "$tmp"; \
wget -q https://raw.githubusercontent.com/1999AZZAR/tailscale_receiver/master/install.sh \
         https://raw.githubusercontent.com/1999AZZAR/tailscale_receiver/master/tailscale-receive.sh \
         https://raw.githubusercontent.com/1999AZZAR/tailscale_receiver/master/tailscale-send.sh; \
chmod +x install.sh tailscale-receive.sh tailscale-send.sh; sudo ./install.sh'
```

#### What Gets Installed

| Item               | Path                                                        | Purpose                                      |
| ------------------ | ----------------------------------------------------------- | -------------------------------------------- |
| Receiver script    | `/usr/local/bin/tailscale-receive.sh`                       | Auto‑accept Taildrop files                   |
| Systemd unit       | `/etc/systemd/system/tailscale-receive.service`             | Run service at boot; auto‑restart            |
| Sender script      | `/usr/local/bin/tailscale-send.sh`                          | Interactive Taildrop sender                  |
| Dolphin (KF6) menu | `/usr/share/kio/servicemenus/tailscale-send.desktop`        | Right‑click "Send to device using Tailscale" |
| Dolphin (KF5) menu | `/usr/share/kservices5/ServiceMenus/tailscale-send.desktop` | Same for KF5                                 |

Systemd details:

- Type=simple; runs as root; `Restart=on-failure`; `After=network-online.target tailscale.service`.
- Logs: `journalctl -u tailscale-receive.service`.

#### Verify Installation

```bash
sudo systemctl status tailscale-receive.service
/usr/local/bin/tailscale-send.sh --help
ls /usr/share/kio/servicemenus/tailscale-send.desktop || true
ls /usr/share/kservices5/ServiceMenus/tailscale-send.desktop || true
```

#### Reinstall/Update

Interactive (default):

```bash
sudo ./install.sh
```

Non‑interactive:

```bash
NONINTERACTIVE=true sudo ./install.sh
```

Backups of prior install are saved to `/tmp/tailscale-receiver-backup-YYYYMMDD-HHMMSS/`.

### Configuration

#### Receiver Settings

The installer configures these automatically.

| Variable     | Meaning                                         | Example                             |
| ------------ | ----------------------------------------------- | ----------------------------------- |
| `TARGET_DIR` | Destination directory for received files        | `/home/<user>/Downloads/tailscale/` |
| `FIX_OWNER`  | User to own the files and receive notifications | `<user>`                            |
| `LOG_LEVEL`  | Logging verbosity (debug, info, warn, error)    | `info`                              |

To change later, edit `/usr/local/bin/tailscale-receive.sh` and restart the service.

#### Sender Options

Environment variables that influence the sender:

| Variable         | Purpose                                               | Example              |
| ---------------- | ----------------------------------------------------- | -------------------- |
| `DIALOG_TOOL`    | Force picker (`kdialog`, `zenity`, `whiptail`, `cli`) | `DIALOG_TOOL=zenity` |
| `DEBUG`          | Verbose output                                        | `DEBUG=1`            |
| `NOTIFY_TIMEOUT` | Notification timeout (seconds)                        | `NOTIFY_TIMEOUT=10`  |

### Usage

#### Manage the Service

```bash
# Status
  sudo systemctl status tailscale-receive.service

# Live logs
  sudo journalctl -u tailscale-receive.service -f

# Stop / Start / Restart
  sudo systemctl stop tailscale-receive.service
  sudo systemctl start tailscale-receive.service
  sudo systemctl restart tailscale-receive.service

# Enable/Disable at boot
  sudo systemctl enable tailscale-receive.service
  sudo systemctl disable tailscale-receive.service
```

#### Send Files

##### Via Dolphin Context Menu (recommended)

- Right‑click file(s)/folder in Dolphin → "Send to device using Tailscale" → pick device.

##### Via Command Line

```bash
# Single file
/usr/local/bin/tailscale-send.sh /path/to/file.txt

# Multiple files
/usr/local/bin/tailscale-send.sh file1.txt file2.txt file3.txt

# Directory
/usr/local/bin/tailscale-send.sh /path/to/directory/

# No args → file picker (GUI permitting)
/usr/local/bin/tailscale-send.sh
```

##### Device Selection Interface

Order of preference: `kdialog` → `zenity` → `whiptail` → CLI fallback.

##### Device Detection

- Primary: `tailscale status --json` + `jq`
- Fallback: parse plain `tailscale status` output

### Troubleshooting

| Symptom                                | Likely Cause                                        | Fix                                                                     |
| -------------------------------------- | --------------------------------------------------- | ----------------------------------------------------------------------- |
| Service fails with "Exec format error" | Corrupt/empty `/usr/local/bin/tailscale-receive.sh` | Reinstall: `sudo ./install.sh`                                          |
| Service fails with exit code 3         | TARGET_DIR not accessible due to security sandboxing| Check systemd service security settings; may need to adjust ReadWritePaths |
| Service running but no files received  | Taildrop disabled; device not logged in             | Enable Taildrop; `tailscale status`; ensure sender targeted this device |
| "Access denied" on send                | Operator not set for your user                      | `sudo tailscale set --operator=$USER`                                   |
| No desktop notifications               | Headless/no GUI or `notify-send` missing            | Install `libnotify-bin` (Debian/Ubuntu) or ignore on headless           |
| Dolphin menu missing                   | KDE cache stale or menu files missing               | `kbuildsycoca6`/`kbuildsycoca5`, restart Dolphin                        |
| Files owned by root                    | Ownership fix not applied yet                       | Service chowns post‑receive; check logs for errors                      |
| Service logs not appearing             | Systemd logging configuration                       | Check `journalctl -u tailscale-receive.service` for detailed logs       |

### Security Notes

- The service runs as root to reliably receive and then chown files. Consider sandboxing/hardening.
- See `TODO.md` for recommended hardening: systemd sandboxing, environment file for secrets, capability limits, timers, etc.

### Advanced Configuration

#### Customize the Receiver

```bash
# Edit installed script
sudo nano /usr/local/bin/tailscale-receive.sh
sudo systemctl restart tailscale-receive.service

# Or edit original and reinstall
nano tailscale-receive.sh
sudo ./install.sh
```

Available variables:

- `TARGET_DIR` (destination dir)
- `FIX_OWNER` (user to own files)
- Poll interval (change `sleep 15`)

#### Customize the Sender

```bash
# Force dialog tool
export DIALOG_TOOL=kdialog  # or zenity, whiptail
# Debug output
export DEBUG=1
# Notification timeout
export NOTIFY_TIMEOUT=10
```

#### Systemd Service Customization

```bash
sudo nano /etc/systemd/system/tailscale-receive.service
sudo systemctl daemon-reload
sudo systemctl restart tailscale-receive.service
```

Common tweaks: add env vars, modify restart behavior, dependencies, or apply sandboxing options.

### Uninstall

```bash
sudo ./uninstall.sh
```

#### One‑Line Uninstall (curl/wget)

Using curl:

```bash
bash -c 'set -euo pipefail; tmp=$(mktemp -d); cd "$tmp"; \
curl -fsSLO https://raw.githubusercontent.com/1999AZZAR/tailscale_receiver/master/uninstall.sh; \
chmod +x uninstall.sh; sudo ./uninstall.sh'
```

Using wget:

```bash
bash -c 'set -euo pipefail; tmp=$(mktemp -d); cd "$tmp"; \
wget -q https://raw.githubusercontent.com/1999AZZAR/tailscale_receiver/master/uninstall.sh; \
chmod +x uninstall.sh; sudo ./uninstall.sh'
```

Removes:

- `/usr/local/bin/tailscale-receive.sh`
- `/usr/local/bin/tailscale-send.sh`
- `/etc/systemd/system/tailscale-receive.service`
- Dolphin service menu files (KF5/KF6)

Note: Does not remove your received files or your original project files.

### Integration with Other Tools

- Nautilus: custom script in `~/.local/share/nautilus/scripts/`
- Thunar: custom actions
- Ranger: bind to a key in `~/.config/ranger/rc.conf`
- Automation: use inotify/cron to call the sender on events

### Contributing

- Test changes thoroughly
- Keep docs updated
- Ensure KF5/KF6 compatibility
- Match existing code style and error handling

### How It Works

- `tailscale-receive.sh`: infinite loop; health checks; `tailscale file get`; diff directory; chown; notify.
- `tailscale-send.sh`: find devices (`--json` + `jq`, fallback to text); show picker; `tailscale file cp` per item; notify.
- `install.sh`: copies scripts, creates unit, enables/starts service, installs Dolphin menus, refreshes cache.
- `uninstall.sh`: stops/disables/removes unit; removes scripts and menus; refreshes cache.

### License

[MIT License](./LICENSE)

### Changelog

#### Version 2.2 (Current)

- **Security Hardening**: Removed dangerous `tailscale up` daemon call, added comprehensive input validation
- **Reliability Improvements**: Added strict Bash mode, null-safe file detection, exponential backoff strategy
- **Structured Logging**: Implemented timestamped logging with configurable levels (debug/info/warn/error)
- **Error Handling**: Added proper exit codes with actionable error messages and operational context
- **Systemd Sandboxing**: Configurable security hardening (temporarily reduced for compatibility)
- **Operational Visibility**: Added cycle tracking, uptime reporting, and detailed file processing logs

#### Version 2.1

- Installer now prompts for target user and configures receiver automatically
- Fixed user capture during install (prompts redirected to stderr) for reliable non-interactive usage
- Corrected absolute TARGET_DIR paths and ownership handling
- Added one-line install/uninstall using curl or wget
- Refined README: clickable TOC, Quick Start, configuration tables, troubleshooting matrix, security notes
- Added TODO.md with comprehensive hardening and enhancement roadmap
- Uninstall notes clarify user data is preserved and how to remove it manually

#### Version 2.0

- Added interactive sender with device picker
- Dolphin context menu integration
- Expanded documentation and troubleshooting
- Improved error handling and messaging
- Multi‑tool GUI support and robust device detection

#### Version 1.0

- Automated file receiver and systemd integration
- Desktop notifications
- Basic setup and uninstall scripts
