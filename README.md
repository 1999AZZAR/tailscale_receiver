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

#### One-Command Installation (Recommended)

```bash
# Download and install automatically (requires Tailscale to be installed first)
curl -fsSL https://raw.githubusercontent.com/1999AZZAR/tailscale_receiver/main/setup.sh | bash
```

#### Manual Installation

```bash
# 1) Clone or download the repository
git clone https://github.com/1999AZZAR/tailscale_receiver.git
cd tailscale_receiver

# 2) Make scripts executable
chmod +x install.sh uninstall.sh tailscale-receive.sh tailscale-send.sh

# 3) Install (interactive setup wizard will guide you)
sudo ./install.sh

# 4) Check service and logs
sudo systemctl status tailscale-receive.service
sudo journalctl -u tailscale-receive.service -f

# 5) Optional: test sender
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
- Smart sender with device picker and Dolphin/Nautilus integration
- Structured logging with timestamps and configurable levels
- Null-safe file detection handling special characters
- Security hardening with systemd sandboxing (configurable)
- Strict error handling with actionable error messages
- Automatic archive management (configurable, default 14 days)
- **Directory support**: Receive both files and directories with recursive ownership
- **Single-instance protection**: Prevents duplicate service processes
- **Power-efficient timer mode**: Optional systemd timer for battery-powered devices
- **Environment-based configuration**: Secure config via `/etc/default/tailscale-receive`

### Comparison of File Sharing Methods

| Feature                 | `tailscale_receiver`                                                                                 | NFS (Network File System)                                                                          | FTP (File Transfer Protocol)                                                         | SMB (Server Message Block)                                                   |
| :---------------------- | :----------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------- | :--------------------------------------------------------------------------- |
| Method Used             | Taildrop (peer‑to‑peer over secure Tailscale network)                                                | Mounting shares (remote directories appear local)                                                  | Client‑server (upload/download to a server)                                         | Network share access (shared folders/resources)                              |
| Ease of Use             | Easy. Designed for simplicity and automation in a Tailscale network.                                   | Moderate–Difficult. Requires server and client config,`/etc/exports`, firewall, automount, etc. | Easy. Many graphical clients; SFTP/FTPS variants common.                             | Easy. Native on Windows; good support via Samba on Linux and macOS.          |
| Security                | High. Tailscale’s end‑to‑end encryption and identity.                                               | Moderate. Can be complex; often relies on LAN isolation, Kerberos, or TLS extensions.              | Low by default (FTP is plaintext). Use SFTP (over SSH) or FTPS for security.         | Moderate–High. SMBv3 supports encryption/signing; depends on configuration. |
| Performance             | Good. Limited by Tailscale overlay and path between peers.                                             | High. Excellent on LAN; kernel‑level I/O.                                                         | Good. Typically adequate for transfers; latency‑sensitive control channel.          | High. Very fast on LAN; improved with SMBv3 multichannel and modern stacks.  |
| Use Case                | Securely and automatically receive files from your Tailnet devices; personal and small team workflows. | Share directories as if local across Unix/Linux systems; POSIX semantics.                          | Simple uploads/downloads; legacy integrations; public file distribution (anonymous). | Windows file/print shares; mixed‑OS LAN environments; AD integration.       |
| Platform Support        | Linux (scripts target `systemd`), works with any Tailnet devices as senders.                         | Primarily Linux/Unix; clients exist for other OSes.                                                | Cross‑platform (FTP/SFTP/FTPS clients abundant).                                    | Primarily Windows; widely supported on Linux (Samba) and macOS.              |
| Setup Complexity        | Low. Install and choose user; no port forwarding or firewall tweaks.                                   | Medium–High. Export lists, uid/gid mapping, firewall rules.                                       | Low–Medium. Stand up an FTP/SFTP server, manage users/keys, open ports.             | Medium. Configure Samba/Windows shares, permissions, and firewall.           |
| NAT/Firewall Traversal  | Excellent. Uses Tailscale’s NAT traversal; no inbound ports.                                          | Poor–Moderate. Usually LAN only or needs VPN/ports.                                               | Moderate. Requires open ports (20/21 for FTP, 22 for SFTP, 990/989 for FTPS).        | Moderate. Requires open ports (e.g., 445), often LAN or VPN.                 |
| Identity/Access Control | Tailnet identity; access scoped to your devices.                                                       | OS‑level users/groups; Kerberos/LDAP possible.                                                    | Local server accounts or system users/SSH keys.                                      | AD/LDAP or local users; granular share/file ACLs.                            |
| Offline Behavior        | Queue on sender; receiver processes on next loop when online.                                          | Not applicable; mount must be reachable.                                                           | Server must be reachable; clients retry/reconnect.                                   | Server must be reachable; clients retry/reconnect.                           |
| Best For                | Quick, secure, zero‑exposure transfers within a personal/team Tailnet.                                | Seamless remote filesystem access and POSIX workflows.                                             | Interop with legacy systems and simple public distribution via hardened variants.    | Windows‑centric networks needing shared folders and permissions.            |

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

| Item               | Path                                                          | Purpose                                       |
| ------------------ | ------------------------------------------------------------- | --------------------------------------------- |
| Receiver script    | `/usr/local/bin/tailscale-receive.sh`                       | Auto‑accept Taildrop files                   |
| Systemd unit       | `/etc/systemd/system/tailscale-receive.service`             | Run service at boot; auto‑restart            |
| Sender script      | `/usr/local/bin/tailscale-send.sh`                          | Interactive Taildrop sender                   |
| Dolphin (KF6) menu | `/usr/share/kio/servicemenus/tailscale-send.desktop`        | Right‑click "Send to device using Tailscale" |
| Dolphin (KF5) menu | `/usr/share/kservices5/ServiceMenus/tailscale-send.desktop` | Same for KF5                                  |
| Nautilus script    | `~/.local/share/nautilus/scripts/Send to device using Tailscale` | GNOME right‑click integration                |

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

| Variable       | Meaning                                         | Example                               |
| -------------- | ----------------------------------------------- | ------------------------------------- |
| `TARGET_DIR` | Destination directory for received files        | `/home/<user>/Downloads/tailscale/` |
| `FIX_OWNER`  | User to own the files and receive notifications | `<user>`                            |
| `LOG_LEVEL`  | Logging verbosity (debug, info, warn, error)    | `info`                              |

To change later, edit `/usr/local/bin/tailscale-receive.sh` and restart the service.

#### Sender Options

Environment variables that influence the sender:

| Variable           | Purpose                                                       | Example                |
| ------------------ | ------------------------------------------------------------- | ---------------------- |
| `DIALOG_TOOL`    | Force picker (`kdialog`, `zenity`, `whiptail`, `cli`) | `DIALOG_TOOL=zenity` |
| `DEBUG`          | Verbose output                                                | `DEBUG=1`            |
| `NOTIFY_TIMEOUT` | Notification timeout (seconds)                                | `NOTIFY_TIMEOUT=10`  |

#### Archive Management

| Variable            | Purpose                                               | Example                |
|-------------------- | ----------------------------------------------------- | ---------------------- |
| `ARCHIVE_ENABLED`   | Enable/disable automatic archiving                    | `ARCHIVE_ENABLED=true` |
| `ARCHIVE_DAYS`     | Days after which files are archived                   | `ARCHIVE_DAYS=14`     |
| `ARCHIVE_DIR_NAME` | Name of archive subdirectory                          | `ARCHIVE_DIR_NAME=archive` |

#### Polling and Performance

| Variable                | Purpose                                               | Example                    |
|------------------------ | ----------------------------------------------------- | -------------------------- |
| `POLL_INTERVAL`         | Base polling interval between checks (seconds)        | `POLL_INTERVAL=15`        |
| `HEALTH_CHECK_INTERVAL` | How often to perform full health checks (cycles)      | `HEALTH_CHECK_INTERVAL=30` |
| `NETWORK_TIMEOUT`       | Network connectivity check timeout (seconds)          | `NETWORK_TIMEOUT=1`       |
| `TAILSCALE_TIMEOUT`     | Tailscale status check timeout (seconds)              | `TAILSCALE_TIMEOUT=5`     |
| `MAX_BACKOFF`           | Maximum exponential backoff time (seconds)            | `MAX_BACKOFF=300`         |
| `NOTIFICATION_THROTTLE` | Minimum seconds between desktop notifications         | `NOTIFICATION_THROTTLE=5` |

#### File Integrity Verification

| Variable                    | Purpose                                               | Example                          |
|---------------------------- | ----------------------------------------------------- | -------------------------------- |
| `INTEGRITY_CHECK_ENABLED`   | Enable/disable file integrity verification            | `INTEGRITY_CHECK_ENABLED=true`  |
| `INTEGRITY_CHECK_ALGORITHM` | Hash algorithm for verification                       | `INTEGRITY_CHECK_ALGORITHM=sha256` |
| `INTEGRITY_CHECK_TIMEOUT`   | Timeout for integrity checks (seconds)                | `INTEGRITY_CHECK_TIMEOUT=30`    |
| `INTEGRITY_CHECK_MAX_SIZE`  | Maximum file size for integrity checks (bytes)        | `INTEGRITY_CHECK_MAX_SIZE=1073741824` |

#### File Type Filtering

| Variable                    | Purpose                                               | Example                          |
|---------------------------- | ----------------------------------------------------- | -------------------------------- |
| `FILE_FILTER_ENABLED`       | Enable/disable file type filtering                    | `FILE_FILTER_ENABLED=true`      |
| `FILE_FILTER_MODE`          | allow/deny mode for filters                           | `FILE_FILTER_MODE=allow`        |
| `FILE_FILTER_MIME_TYPES`    | Comma-separated allowed/denied MIME types             | `FILE_FILTER_MIME_TYPES=text/plain,image/*` |
| `FILE_FILTER_EXTENSIONS`    | Comma-separated allowed/denied extensions             | `FILE_FILTER_EXTENSIONS=pdf,doc,txt` |
| `FILE_FILTER_MAX_SIZE`      | Maximum file size for filtering (bytes)               | `FILE_FILTER_MAX_SIZE=104857600` |

#### Virus Scanning

| Variable                    | Purpose                                               | Example                          |
|---------------------------- | ----------------------------------------------------- | -------------------------------- |
| `VIRUS_SCAN_ENABLED`        | Enable/disable virus scanning                         | `VIRUS_SCAN_ENABLED=true`       |
| `VIRUS_SCAN_ENGINE`         | Scanning engine                                       | `VIRUS_SCAN_ENGINE=clamav`      |
| `VIRUS_SCAN_TIMEOUT`        | Scan timeout (seconds)                                | `VIRUS_SCAN_TIMEOUT=60`         |
| `VIRUS_SCAN_QUARANTINE`     | Quarantine infected files                             | `VIRUS_SCAN_QUARANTINE=true`    |

#### Rate Limiting & Abuse Protection

| Variable                        | Purpose                                               | Example                          |
|-------------------------------- | ----------------------------------------------------- | -------------------------------- |
| `RATE_LIMIT_ENABLED`            | Enable/disable rate limiting                         | `RATE_LIMIT_ENABLED=true`       |
| `RATE_LIMIT_FILES_PER_MINUTE`   | Maximum files per minute                              | `RATE_LIMIT_FILES_PER_MINUTE=60` |
| `RATE_LIMIT_FILES_PER_HOUR`     | Maximum files per hour                                | `RATE_LIMIT_FILES_PER_HOUR=500` |
| `RATE_LIMIT_SIZE_PER_MINUTE`    | Maximum size per minute (bytes)                       | `RATE_LIMIT_SIZE_PER_MINUTE=104857600` |
| `RATE_LIMIT_SIZE_PER_HOUR`      | Maximum size per hour (bytes)                         | `RATE_LIMIT_SIZE_PER_HOUR=1073741824` |
| `RATE_LIMIT_BLOCK_DURATION`     | Block duration when limits exceeded (seconds)         | `RATE_LIMIT_BLOCK_DURATION=300` |
| `RATE_LIMIT_RESET_INTERVAL`     | Statistics reset interval (seconds)                   | `RATE_LIMIT_RESET_INTERVAL=60`  |

**Security Examples:**
```bash
# Enable integrity checking for all files
INTEGRITY_CHECK_ENABLED=true
INTEGRITY_CHECK_ALGORITHM=sha256

# File type filtering - allow only safe types
FILE_FILTER_ENABLED=true
FILE_FILTER_MODE=allow
FILE_FILTER_MIME_TYPES=text/plain,text/*,image/*,application/pdf
FILE_FILTER_EXTENSIONS=pdf,doc,docx,txt,jpg,png,gif

# File type filtering - deny dangerous types
FILE_FILTER_ENABLED=true
FILE_FILTER_MODE=deny
FILE_FILTER_EXTENSIONS=exe,dll,scr,com,pif,bat,cmd,vbs,js,jar

# Virus scanning with quarantine
VIRUS_SCAN_ENABLED=true
VIRUS_SCAN_QUARANTINE=true
VIRUS_SCAN_TIMEOUT=120

# Rate limiting for abuse protection
RATE_LIMIT_ENABLED=true
RATE_LIMIT_FILES_PER_MINUTE=30      # 30 files/minute
RATE_LIMIT_FILES_PER_HOUR=200       # 200 files/hour
RATE_LIMIT_SIZE_PER_MINUTE=52428800 # 50MB/minute

# Enterprise security stack
INTEGRITY_CHECK_ENABLED=true
FILE_FILTER_ENABLED=true
FILE_FILTER_MODE=allow
VIRUS_SCAN_ENABLED=true
RATE_LIMIT_ENABLED=true
```

#### Health Endpoint

| Variable                    | Purpose                                               | Example                          |
|---------------------------- | ----------------------------------------------------- | -------------------------------- |
| `HEALTH_ENDPOINT_ENABLED`   | Enable/disable HTTP health endpoint                   | `HEALTH_ENDPOINT_ENABLED=true`  |
| `HEALTH_ENDPOINT_PORT`      | Port for health endpoint server                       | `HEALTH_ENDPOINT_PORT=8080`     |
| `HEALTH_ENDPOINT_PATH`      | HTTP path for health checks                           | `HEALTH_ENDPOINT_PATH=/health`  |

**Monitoring Examples:**
```bash
# Enable health monitoring
HEALTH_ENDPOINT_ENABLED=true
HEALTH_ENDPOINT_PORT=8080

# Custom endpoint path
HEALTH_ENDPOINT_PATH=/api/health

# Integrate with monitoring systems
curl http://localhost:8080/health
```

**Health Response Example:**
```json
{
  "status": "healthy",
  "timestamp": 1703123456,
  "uptime": 3600,
  "last_successful_cycle": 1703123450,
  "cycles_completed": 120,
  "files_processed": 15,
  "files_failed": 0,
  "consecutive_failures": 0
}
```

#### Configuration Migration

The service automatically migrates configuration files when upgrading between versions:

- **Automatic Detection**: Detects configuration version and applies necessary migrations
- **Backup Creation**: Creates timestamped backups before migration
- **Version Tracking**: Uses `CONFIG_VERSION` to track configuration schema versions
- **Backward Compatibility**: Maintains compatibility with older configuration formats

**Migration Examples:**
```bash
# Pre-2.3.0 configurations are automatically migrated on first run
# Backups are created: /etc/default/tailscale-receive.backup.YYYYMMDD_HHMMSS

# Check migration logs
sudo journalctl -u tailscale-receive.service | grep -i migrat
```

## 📦 **Package Installation**

### Debian/Ubuntu (.deb)

**Install from repository:**
```bash
# Download the .deb package and install
sudo dpkg -i tailscale-receiver_2.3.0-1_all.deb
sudo apt install -f  # Fix any missing dependencies

# The package will automatically:
# - Install scripts to /usr/local/bin/
# - Configure systemd service
# - Set up desktop integration
# - Create initial configuration
```

**Post-installation:**
```bash
# Enable and start the service
sudo systemctl enable tailscale-receive
sudo systemctl start tailscale-receive

# Check status
sudo systemctl status tailscale-receive
```

### Red Hat/Fedora/CentOS (.rpm)

**Install from repository:**
```bash
# Download the .rpm package and install
sudo rpm -i tailscale-receiver-2.3.0-1.noarch.rpm

# Or using dnf/yum
sudo dnf install tailscale-receiver-2.3.0-1.noarch.rpm
```

**Post-installation:**
```bash
# Enable and start the service
sudo systemctl enable tailscale-receive
sudo systemctl start tailscale-receive

# Check status
sudo systemctl status tailscale-receive
```

### Building Packages

**Build Debian package:**
```bash
# Install build dependencies
sudo apt install build-essential devscripts debhelper

# Build the package
make deb
```

**Build RPM package:**
```bash
# Install build dependencies
sudo dnf install rpm-build

# Build the package
make rpm
```

**Build both packages:**
```bash
make packages
```

**Manual Migration (if needed):**
```bash
# Force migration check
sudo systemctl restart tailscale-receive.service
```

**Security Examples:**
```bash
# Enable integrity checking for all files
INTEGRITY_CHECK_ENABLED=true

# Use SHA512 for maximum security
INTEGRITY_CHECK_ALGORITHM=sha512

# Allow larger files for integrity checking
INTEGRITY_CHECK_MAX_SIZE=5368709120  # 5GB

# Quick checks for fast networks
INTEGRITY_CHECK_TIMEOUT=10
```

**Performance Tuning Examples:**
```bash
# Fast polling for responsive file reception
POLL_INTERVAL=5 HEALTH_CHECK_INTERVAL=10

# Battery-friendly for laptops
POLL_INTERVAL=30 HEALTH_CHECK_INTERVAL=60 MAX_BACKOFF=600

# High-reliability for unstable networks
NETWORK_TIMEOUT=3 TAILSCALE_TIMEOUT=10 MAX_BACKOFF=600

# Quiet notifications (reduce spam)
NOTIFICATION_THROTTLE=10
```

#### Directory Support

The receiver now supports receiving both individual files and entire directories:

- **Recursive ownership**: Directories and all contents are properly chown'd to your user
- **Size calculation**: Directory sizes include all nested files and subdirectories
- **Smart notifications**: Separate counting and display for files vs directories
- **Full preservation**: Directory structure and permissions are maintained

```bash
# Send a directory (from another device)
tailscale file cp -r /path/to/directory/ receiver-device:

# The receiver will:
# - Create the directory structure
# - Set ownership recursively
# - Show notification with file/directory counts
# - Calculate total size including all contents
```

### Operational Modes

The service supports two operational modes:

#### Continuous Service Mode (Default)
- Runs as a persistent systemd service
- Continuously monitors for new files
- Immediate response to incoming Taildrop files
- Higher CPU usage but instant notifications
- Suitable for always-on desktop systems

#### Timer Mode (Power Efficient)
- Uses systemd timer for periodic execution
- Runs every 30 seconds when active
- Significantly reduced CPU usage
- Delayed notifications (up to 30s)
- Perfect for laptops, servers, and battery-powered devices

To enable timer mode:
```bash
export USE_TIMER=true
sudo ./install.sh
```

#### Manual/Scripted Operation
```bash
# Single execution cycle (useful for testing/cron)
sudo /usr/local/bin/tailscale-receive.sh --once
```

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

#### Archive Management

The service automatically archives old files to keep your main folder tidy. By default:

- Files older than **14 days** are moved to an `archive/` subdirectory
- Archive management runs continuously in the background
- Archived files maintain their original timestamps and permissions

```bash
# Check archived files
ls -la ~/Downloads/tailscale/archive/

# Disable archiving (set before installing)
export ARCHIVE_ENABLED=false

# Change archive threshold to 30 days
export ARCHIVE_DAYS=30

# Use custom archive folder name
export ARCHIVE_DIR_NAME=old_files
```

#### Send Files

##### Via Dolphin Context Menu (KDE, recommended)

- Right‑click file(s)/folder in Dolphin → "Send to device using Tailscale" → pick device.

#### Via Nautilus Context Menu (GNOME)

- Right‑click file(s)/folder in Nautilus → Scripts → "Send to device using Tailscale" → pick device.

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

| Symptom                                | Likely Cause                                          | Fix                                                                        |
| -------------------------------------- | ----------------------------------------------------- | -------------------------------------------------------------------------- |
| Service fails with "Exec format error" | Corrupt/empty `/usr/local/bin/tailscale-receive.sh` | Reinstall:`sudo ./install.sh`                                            |
| Service fails with exit code 3         | TARGET_DIR not accessible due to security sandboxing  | Check systemd service security settings; may need to adjust ReadWritePaths |
| Service running but no files received  | Taildrop disabled; device not logged in               | Enable Taildrop;`tailscale status`; ensure sender targeted this device   |
| "Access denied" on send                | Operator not set for your user                        | `sudo tailscale set --operator=$USER`                                    |
| No desktop notifications               | Headless/no GUI or `notify-send` missing            | Install `libnotify-bin` (Debian/Ubuntu) or ignore on headless            |
| Dolphin menu missing                   | KDE cache stale or menu files missing                 | `kbuildsycoca6`/`kbuildsycoca5`, restart Dolphin                       |
| Files owned by root                    | Ownership fix not applied yet                         | Service chowns post‑receive; check logs for errors                        |
| Service logs not appearing             | Systemd logging configuration                         | Check `journalctl -u tailscale-receive.service` for detailed logs        |

## Development

### Code Quality Tools

This project uses several tools to maintain code quality and prevent bugs:

#### Linting and Formatting
- **ShellCheck**: Static analysis for shell scripts
- **shfmt**: Code formatter for shell scripts
- **Git hooks**: Automatic linting and formatting on commit

#### Testing
- **Bats**: Bash Automated Testing System for unit tests
- **GitHub Actions**: CI/CD pipeline with automated checks

#### Development Setup

```bash
# Install development dependencies
make dev-setup

# Run all checks locally
make ci

# Format code
make format

# Run linting
make lint

# Run tests
make test
```

#### Git Hooks

The project includes pre-commit hooks that automatically:
- Check syntax
- Run ShellCheck
- Format code with shfmt
- Run tests (if available)

To enable hooks:
```bash
git config core.hooksPath .githooks
```

#### Makefile Commands

| Command | Description |
|---------|-------------|
| `make help` | Show available commands |
| `make dev-setup` | Install development tools |
| `make check-deps` | Check if dependencies are installed |
| `make lint` | Run shellcheck on all scripts |
| `make format` | Format shell scripts |
| `make test` | Run test suite |
| `make install` | Install the service |
| `make uninstall` | Uninstall the service |
| `make status` | Show service status |
| `make logs` | Show service logs |
| `make clean` | Clean temporary files |
| `make validate` | Validate all scripts |

## 🧪 **Testing & CI/CD**

### Running Tests

```bash
# Run all tests
make test

# Run unit tests only
make test-unit

# Run integration tests
make test-integration

# Run security checks
make test-security

# Run complete CI pipeline locally
make ci
```

### Test Types

- **Unit Tests**: Individual function testing with Bats
- **Integration Tests**: End-to-end system testing
- **Security Tests**: ShellCheck linting and vulnerability scanning
- **Packaging Tests**: Debian/RPM build validation

### CI/CD Pipeline

The project uses GitHub Actions for automated testing:

- **On Push/PR**: Full test suite + security scanning
- **Packaging Validation**: Debian/RPM build testing
- **Deployment Checks**: Production readiness validation

### Test Coverage

- ✅ **47 unit tests** covering all functions
- ✅ **8 integration tests** for end-to-end scenarios
- ✅ **Security scanning** with Trivy
- ✅ **Code quality** with ShellCheck and shfmt
- ✅ **Packaging validation** for Debian/RPM

### Writing Tests

Tests use the Bats framework. Add new tests to:
- `test/*.bats` - Unit tests
- `test/integration.bats` - Integration tests

Example test:
```bash
@test "my feature works" {
    # Setup
    export TEST_VAR="value"

    # Execute
    run my_command

    # Assert
    [[ $status -eq 0 ]]
    [[ "$output" == "expected" ]]
}
```

## 🤝 **Contributing**

### Development Setup

1. **Clone and setup**:
   ```bash
   git clone https://github.com/your-repo/tailscale-receiver.git
   cd tailscale-receiver
   make setup  # Install development dependencies
   ```

2. **Run tests**:
   ```bash
   make test   # Run full test suite
   make ci     # Run CI pipeline locally
   ```

3. **Code quality**:
   ```bash
   make lint   # Check code style
   make format # Format code
   ```

### Contribution Guidelines

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run `make ci` to ensure all checks pass
5. Commit your changes (hooks will run automatically)
6. Push and create a pull request

### Code Standards

- **ShellCheck compliant** - No linting errors
- **Bats tested** - Unit test coverage for new features
- **Documentation updated** - README reflects changes
- **Security reviewed** - No hardcoded secrets or vulnerabilities

### Release Process

1. Update version in `tailscale-receive.sh`
2. Update `README.md` changelog
3. Run full test suite: `make test-all`
4. Create git tag: `git tag v2.3.0`
5. Push tag: `git push origin v2.3.0`
6. CI/CD handles packaging and deployment

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
- Nautilus script (`~/.local/share/nautilus/scripts/Send to device using Tailscale`)

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

#### Version 2.3.0 (Current)

- **Directory Support**: Full support for receiving directories with recursive ownership correction
- **Single-Instance Protection**: PID and lock file mechanism prevents duplicate service processes
- **Systemd Timer Mode**: Power-efficient timer alternative for battery-powered devices
- **GNOME/Nautilus Integration**: Right-click context menu support for GNOME users
- **Configurable Polling**: Customizable intervals, timeouts, and health check frequencies
- **File Integrity Verification**: SHA256/SHA512/MD5 checksum validation for received files
- **File Type Filtering**: MIME type and extension-based allow/deny filtering
- **Virus Scanning**: ClamAV integration with automatic quarantine
- **Health Endpoint**: HTTP monitoring endpoint with JSON status and metrics
- **Configuration Migration**: Automatic config upgrades with backup and version tracking
- **Professional Packaging**: Debian/RPM packages for enterprise deployment
- **Environment Configuration**: Secure configuration via `/etc/default/tailscale-receive`
- **Enhanced Notifications**: Aggregated notifications with file/directory breakdown and throttling
- **Full Path Resolution**: Binary path resolution for improved security and reliability
- **Rate Limiting**: Configurable abuse protection with file and size limits
- **CI/CD Pipeline**: GitHub Actions with comprehensive testing and security scanning
- **Integration Testing**: End-to-end testing framework with Bats
- **Enterprise Packaging**: Production-ready Debian/RPM packages

#### Version 2.2.1

- **Archive Management**: Automatic archiving of files older than configurable threshold (default 14 days)
- **Code Quality Infrastructure**: Added comprehensive linting, testing, CI/CD pipeline, and development tools
- **Preflight Checks**: Enhanced installer with comprehensive system validation before installation
- **Improved UX**: Interactive setup wizard, better error messages, and safer uninstallation

#### Version 2.2

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
