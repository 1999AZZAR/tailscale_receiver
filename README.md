# Tailscale Auto-File Receiver Service

## Overview

This project provides a comprehensive solution for automated file sharing via Tailscale's Taildrop feature. It includes both receiving and sending capabilities:

- **Automatic File Reception**: A background systemd service that continuously monitors for incoming Taildrop files, processes them automatically, and notifies you of new arrivals.
- **Interactive File Sending**: A smart sender with device picker that integrates with Dolphin file manager for seamless right-click sending.

The project includes:
- `tailscale-receive.sh`: The core script that watches for and processes incoming files.
- `setup.sh`: An automated installer that configures and runs the receiver script as a systemd service.
- `uninstall.sh`: A script to completely remove the service and all related files.
- `tailscale-send.sh`: A helper to send files via Taildrop with an interactive device picker and Dolphin right-click integration.

This setup is ideal for users who frequently share files through Tailscale and want a seamless, automated experience for both receiving and sending files.

## Features

- **Automated File Reception**: Runs continuously to accept incoming Tailscale files.
- **Systemd Integration**: Deploys the receiver script as a proper systemd service for reliability and auto-start on boot.
- **Desktop Notifications**: Informs the user of newly received files via `notify-send`.
- **Ownership Correction**: Automatically changes the ownership of received files from `root` to your user.
- **Health Checks**: Ensures an internet connection is active and the Tailscale service is running before checking for files.
- **Automated Setup & Uninstallation**: Scripts handle all installation, configuration, and removal steps.
- **Send via Taildrop**: `tailscale-send.sh` lets you pick a device and send selected files. Installed as a Dolphin context menu item "Send to device using Tailscale".
- **Smart Device Detection**: Automatically discovers online Tailscale devices using JSON parsing (with `jq`) or text parsing fallback.
- **Multiple UI Options**: Supports `kdialog`, `zenity`, `whiptail`, or CLI for device selection.
- **Dolphin Integration**: Seamless right-click context menu integration for sending files and folders.
- **Error Handling**: Robust error handling with user-friendly notifications and fallback mechanisms.

## Prerequisites

- A Linux system with `systemd` (e.g., Ubuntu, Debian, Fedora, Arch Linux).
- Tailscale installed and configured.
- Root privileges (`sudo`) are required to run the setup and uninstall scripts.
- `notify-send` command-line tool (usually installed by default with most desktop environments).
- **For sending features**:
  - At least one of: `kdialog`, `zenity`, or `whiptail` for GUI device selection (optional, CLI fallback available).
  - `jq` for enhanced device detection (optional, text parsing fallback available).
  - KDE Plasma with Dolphin file manager for context menu integration.
- **Taildrop must be enabled** in your Tailscale admin console (General settings → Send Files feature).

## ⚠️ Important: Configuration

Before you begin the installation, you **must** configure the receiver script to match your system.

Open the `tailscale-receive.sh` file and edit the following variables at the top:

```sh
# --- Configuration ---
# IMPORTANT: Set this to the directory where you want files to be saved.
# The script will create this directory if it doesn't exist.
# Example: TARGET_DIR="/home/your_username/Downloads/Tailscale/"
TARGET_DIR="home/azzar/Downloads/tailscale/"

# IMPORTANT: Set this to your Linux username.
# This ensures you own the files, not root.
# Example: FIX_OWNER="your_username"
FIX_OWNER="azzar"
```

1.  **`TARGET_DIR`**: Change this to the absolute path of the folder where you want received files to be saved.
2.  **`FIX_OWNER`**: Change this to your Linux username to ensure the script assigns the correct file permissions.

**Save the file before proceeding to the installation.**

## Taildrop Setup Requirements

Before using the send/receive features, ensure Taildrop is properly configured:

1. **Enable Taildrop in Admin Console**:
   - Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/general)
   - Navigate to **General** settings
   - Enable the **Send Files** feature
   - Save changes

2. **Verify Tailscale Status**:
   ```bash
   tailscale status
   ```
   Ensure your device shows as "active" and you can see other devices in your tailnet.

3. **Test Basic Taildrop**:
   ```bash
   # Test receiving (should show available files)
   tailscale file get
   
   # Test sending (replace 'device-name' with an actual device)
   tailscale file cp /path/to/test/file device-name:
   ```

## Installation

1.  **Clone or Download**:
    Get the script files on your machine.
    ```bash
    git clone <repository_url>
    cd tailscale-auto-receiver
    ```
    Or download `setup.sh`, `tailscale-receive.sh`, and `uninstall.sh` into the same directory.

2.  **Configure the Script**:
    As mentioned in the configuration section, **edit `tailscale-receive.sh`** to set your `TARGET_DIR` and `FIX_OWNER`.

3.  **Make Scripts Executable**:
    ```bash
    chmod +x setup.sh tailscale-receive.sh uninstall.sh
    ```

4.  **Run the Installer**:
    Execute the setup script with `sudo`. It will copy the configured receiver script to a system directory, create the systemd service, and start it.
    ```bash
    sudo ./setup.sh
    ```
    The service will now be running in the background and will automatically start on boot. The installer also installs `tailscale-send.sh` and a Dolphin service menu.

### What the Installer Does

The setup script performs the following actions:

1. **Installs Receiver Script**: Copies `tailscale-receive.sh` to `/usr/local/bin/` and makes it executable
2. **Creates Systemd Service**: Creates `/etc/systemd/system/tailscale-receive.service` with proper dependencies
3. **Enables Service**: Starts the service immediately and configures it to start on boot
4. **Installs Sender Script**: Copies `tailscale-send.sh` to `/usr/local/bin/` (if present)
5. **Creates Dolphin Integration**: Installs service menu files for both KF5 and KF6:
   - `/usr/share/kio/servicemenus/tailscale-send.desktop`
   - `/usr/share/kservices5/ServiceMenus/tailscale-send.desktop`
6. **Updates KDE Cache**: Runs `kbuildsycoca6` or `kbuildsycoca5` to refresh Dolphin's service menu cache

### Installation Verification

After installation, verify everything is working:

```bash
# Check receiver service status
sudo systemctl status tailscale-receive.service

# Test sender script
/usr/local/bin/tailscale-send.sh --help

# Check if Dolphin service menu is installed
ls /usr/share/kio/servicemenus/tailscale-send.desktop
ls /usr/share/kservices5/ServiceMenus/tailscale-send.desktop
```

## Usage: Managing the Service

You can manage the service using standard `systemctl` commands.

-   **Check Status**: See if the service is active and running.
    ```bash
    sudo systemctl status tailscale-receive.service
    ```

-   **View Live Logs**: Watch the real-time output for debugging.
    ```bash
    sudo journalctl -u tailscale-receive.service -f
    ```

-   **Stop/Start**: Manually stop or start the service.
    ```bash
    sudo systemctl stop tailscale-receive.service
    sudo systemctl start tailscale-receive.service
    ```

-   **Enable/Disable**: Control whether the service starts on boot.
    ```bash
    sudo systemctl disable tailscale-receive.service
    sudo systemctl enable tailscale-receive.service
    ```

## Usage: Sending Files

### Via Dolphin Context Menu (Recommended)

1. **Right-click** on any file or folder in Dolphin
2. Select **"Send to device using Tailscale"** from the context menu
3. Choose the destination device from the popup dialog
4. Wait for the transfer to complete (desktop notification will appear)

### Via Command Line

```bash
# Send a single file
/usr/local/bin/tailscale-send.sh /path/to/file.txt

# Send multiple files
/usr/local/bin/tailscale-send.sh file1.txt file2.txt file3.txt

# Send a directory
/usr/local/bin/tailscale-send.sh /path/to/directory/

# Send with file picker (if no arguments provided)
/usr/local/bin/tailscale-send.sh
```

### Device Selection Interface

The sender script automatically detects available GUI tools and uses the best available:

1. **kdialog** (KDE) - Radio button dialog with device list
2. **zenity** (GNOME) - List dialog with device selection
3. **whiptail** (Terminal) - Text-based menu interface
4. **CLI Fallback** - Simple numbered list with text input

### Device Detection

The script uses two methods to detect online Tailscale devices:

1. **JSON Parsing** (with `jq`): More robust, handles special characters in device names
2. **Text Parsing** (fallback): Parses `tailscale status` output directly

## Troubleshooting

### Receiver Service Issues

**Service not starting:**
```bash
# Check service status
sudo systemctl status tailscale-receive.service

# View detailed logs
sudo journalctl -u tailscale-receive.service -f

# Check if Tailscale is running
tailscale status
```

**Files not being received:**
- Verify Taildrop is enabled in your Tailscale admin console
- Check if files are being sent to the correct device
- Ensure the target directory exists and is writable
- Check file permissions in the target directory

### Sender Issues

**"No online Tailscale devices found":**
```bash
# Check Tailscale status
tailscale status

# Ensure other devices are online and accessible
tailscale ping <device-name>
```

**Dolphin context menu not appearing:**
```bash
# Check if service menu files exist
ls -la /usr/share/kio/servicemenus/tailscale-send.desktop
ls -la /usr/share/kservices5/ServiceMenus/tailscale-send.desktop

# Rebuild KDE service cache
kbuildsycoca6  # or kbuildsycoca5

# Restart Dolphin
dolphin &
```

**GUI dialogs not working:**
```bash
# Install missing dialog tools
sudo apt install kdialog zenity whiptail  # Ubuntu/Debian
sudo dnf install kdialog zenity newt      # Fedora
sudo pacman -S kdialog zenity newt        # Arch
```

### General Issues

**Tailscale not connecting:**
```bash
# Bring up Tailscale
tailscale up

# Check connection status
tailscale status

# Test connectivity
tailscale ping <device-name>
```

**Permission denied errors:**
```bash
# Check script permissions
ls -la /usr/local/bin/tailscale-*.sh

# Fix permissions if needed
sudo chmod +x /usr/local/bin/tailscale-*.sh
```

## Advanced Configuration

### Customizing the Receiver

You can modify the receiver behavior by editing `/usr/local/bin/tailscale-receive.sh`:

```bash
# Edit the installed script
sudo nano /usr/local/bin/tailscale-receive.sh

# Or edit the original and reinstall
nano tailscale-receive.sh
sudo ./setup.sh
```

**Available configuration variables:**
- `TARGET_DIR`: Directory where received files are saved
- `FIX_OWNER`: Username to assign ownership of received files
- Check interval: Currently 15 seconds (modify the `sleep 15` line)

### Customizing the Sender

The sender script supports several environment variables:

```bash
# Force a specific dialog tool
export DIALOG_TOOL=kdialog  # or zenity, whiptail

# Enable debug output
export DEBUG=1

# Custom notification timeout (seconds)
export NOTIFY_TIMEOUT=10
```

### Systemd Service Customization

You can customize the systemd service by editing `/etc/systemd/system/tailscale-receive.service`:

```bash
sudo nano /etc/systemd/system/tailscale-receive.service
sudo systemctl daemon-reload
sudo systemctl restart tailscale-receive.service
```

**Common customizations:**
- Add environment variables
- Modify restart behavior
- Change user/group
- Add dependencies

## Uninstallation

To completely remove the service and the installed script file, run the uninstaller with `sudo`.

```bash
sudo ./uninstall.sh
```

This script will:
1.  Stop the `tailscale-receive` service.
2.  Disable it from starting on boot.
3.  Remove the systemd service file.
4.  Delete the `tailscale-receive.sh` script from `/usr/local/bin`.
5.  Delete the `tailscale-send.sh` script and Dolphin service menu entries.

### What the Uninstaller Removes

- `/usr/local/bin/tailscale-receive.sh`
- `/usr/local/bin/tailscale-send.sh`
- `/etc/systemd/system/tailscale-receive.service`
- `/usr/share/kio/servicemenus/tailscale-send.desktop`
- `/usr/share/kservices5/ServiceMenus/tailscale-send.desktop`
- KDE service cache is refreshed

**Note**: The uninstaller does NOT remove:
- Your original script files in the project directory
- Received files in your target directory
- Tailscale installation or configuration

## Security Considerations

### File Permissions
- Received files are automatically assigned to your user account
- The receiver service runs as root to handle file operations
- Sender script runs with your user permissions

### Network Security
- All file transfers use Tailscale's encrypted peer-to-peer connections
- No files are stored on Tailscale servers during transfer
- Device authentication is handled by Tailscale's security model

### Privacy
- File transfer logs are minimal and local only
- No telemetry or data collection
- Device lists are retrieved locally via Tailscale CLI

## Performance Notes

### Transfer Speed
- File transfers use the fastest available path between devices
- Speed depends on your network conditions and device locations
- Large files may take time; the sender shows progress notifications

### Resource Usage
- Receiver service uses minimal CPU (checks every 15 seconds)
- Memory usage is negligible
- Network usage only when files are being transferred

### Monitoring
```bash
# Monitor service resource usage
sudo systemctl status tailscale-receive.service

# Check recent transfers
tailscale file get  # Shows pending files

# Monitor system resources
htop  # or top, glances, etc.
```

## Integration with Other Tools

### Alternative File Managers

While the service menu is designed for Dolphin, you can use the sender script with other file managers:

**Nautilus (GNOME):**
- Create a custom action in `~/.local/share/nautilus/scripts/`
- Or use the command line interface directly

**Thunar (Xfce):**
- Add custom actions in Thunar's preferences
- Or use the command line interface

**Ranger:**
- Bind the sender script to a key in `~/.config/ranger/rc.conf`

### Automation

You can integrate the sender script into your workflow:

```bash
# Send files from a watched directory
inotifywait -m -e moved_to /path/to/watch | while read path action file; do
    /usr/local/bin/tailscale-send.sh "$path$file"
done

# Send files via cron
0 */6 * * * /usr/local/bin/tailscale-send.sh /path/to/backup/file
```

## Development and Contributing

### Project Structure
```
tailscale_receiver/
├── README.md              # This documentation
├── setup.sh               # Installation script
├── uninstall.sh           # Removal script
├── tailscale-receive.sh   # Receiver service script
└── tailscale-send.sh      # Sender script with GUI
```

### Testing

Before installing, you can test the scripts locally:

```bash
# Test receiver script
./tailscale-receive.sh

# Test sender script
./tailscale-send.sh /path/to/test/file
```

### Debugging

Enable debug output for troubleshooting:

```bash
# For receiver service
sudo journalctl -u tailscale-receive.service -f

# For sender script
DEBUG=1 /usr/local/bin/tailscale-send.sh /path/to/file
```

### Contributing

When contributing to this project:
1. Test your changes thoroughly
2. Update documentation for any new features
3. Ensure compatibility with both KF5 and KF6
4. Follow the existing code style and error handling patterns

## How It Works

### `tailscale-receive.sh`

This is the core worker script. It runs in an infinite loop, checking for files every 15 seconds.
1.  It performs health checks for an internet connection and the Tailscale daemon.
2.  It runs `tailscale file get` to accept any pending files into the specified `TARGET_DIR`.
3.  It compares the directory contents before and after the `get` command to identify new files.
4.  If new files are found, it corrects their ownership using `chown` and sends a desktop notification as your user.

### `tailscale-send.sh`

An interactive sender for Taildrop:

- Lists online devices using `tailscale status --json` (falls back to parsing text if `jq` not present).
- Prompts you to pick the destination using `kdialog`/`zenity`/`whiptail` when available, otherwise a simple CLI menu.
- Sends one or more files using `tailscale file cp <file> <device>:` and shows a desktop notification on completion.

It is wired into Dolphin as a context menu action named "Send to device using Tailscale" for files and folders.

**Device Detection Process:**
1. Calls `tailscale status --json` to get device list
2. If `jq` is available, parses JSON for online devices
3. Falls back to parsing text output if JSON parsing fails
4. Filters for devices with "active" or "idle" status
5. Extracts device names (DNSName, HostName, or Hostinfo.Hostname)

**GUI Selection Process:**
1. Tries `kdialog` first (best KDE integration)
2. Falls back to `zenity` (GNOME compatibility)
3. Falls back to `whiptail` (terminal-based)
4. Final fallback to simple CLI numbered menu

**File Transfer Process:**
1. Validates file existence and permissions
2. Calls `tailscale file cp` for each file
3. Tracks success/failure counts
4. Shows desktop notification with results
5. Returns appropriate exit code

### `setup.sh`

This script automates the installation by:
1.  Copying your configured `tailscale-receive.sh` to `/usr/local/bin`.
2.  Creating a systemd service file (`/etc/systemd/system/tailscale-receive.service`) that defines how to run the script as `root`.
3.  Reloading the systemd daemon, enabling the service to start on boot, and starting it immediately.
4.  Installing `tailscale-send.sh` to `/usr/local/bin` and a Dolphin service menu at `/usr/share/kio/servicemenus/tailscale-send.desktop` and `/usr/share/kservices5/ServiceMenus/tailscale-send.desktop`.

**Service Menu Creation:**
- Creates `.desktop` files with proper MIME type associations
- Supports both KF5 and KF6 service menu paths
- Includes proper icon and action definitions
- Refreshes KDE service cache after installation

### `uninstall.sh`

This script performs a complete cleanup:
1. Stops and disables the systemd service
2. Removes the service file from systemd
3. Deletes both receiver and sender scripts
4. Removes Dolphin service menu entries
5. Refreshes KDE service cache
6. Provides detailed feedback on each step

**Safety Features:**
- Checks for file existence before attempting removal
- Provides warnings for missing files
- Handles errors gracefully with informative messages
- Does not remove user data or original project files

## Frequently Asked Questions

**Q: Why do I need to run the installer as root?**
A: The installer needs to create systemd services and install files to system directories (`/usr/local/bin`, `/etc/systemd/system`, `/usr/share/`).

**Q: Can I use this without KDE/Dolphin?**
A: Yes! The sender script works from command line. Only the right-click context menu requires Dolphin.

**Q: What if I don't have `jq` installed?**
A: The script will automatically fall back to parsing `tailscale status` text output. `jq` just provides more robust device name handling.

**Q: Can I send files to devices owned by other users?**
A: No, Taildrop only works between your own devices. You cannot send files to devices owned by other users in your tailnet.

**Q: How do I change the target directory for received files?**
A: Edit the `TARGET_DIR` variable in `/usr/local/bin/tailscale-receive.sh` and restart the service.

**Q: The Dolphin context menu doesn't appear. What should I do?**
A: Try running `kbuildsycoca6` (or `kbuildsycoca5`) to refresh the service menu cache, then restart Dolphin.

**Q: Can I send folders/directories?**
A: Yes! The sender script supports both files and directories. Folders will be sent as-is to the destination device.

**Q: What happens if a transfer fails?**
A: The sender script will show an error notification and continue with other files. Failed transfers don't affect successful ones.

**Q: How do I monitor transfer progress?**
A: Currently, the script shows start and completion notifications. For detailed progress, you can monitor the Tailscale logs or use `tailscale status`.

**Q: Can I customize the notification messages?**
A: Yes, you can modify the notification calls in the sender script. The script uses `notify-send` for desktop notifications.

**Q: Is this compatible with all Linux distributions?**
A: The scripts are designed to work with any systemd-based Linux distribution. Some features (like GUI dialogs) may require additional packages.

**Q: What's the difference between KF5 and KF6 service menu paths?**
A: KF5 uses `/usr/share/kservices5/ServiceMenus/` while KF6 uses `/usr/share/kio/servicemenus/`. The installer creates both for maximum compatibility.

## License

This project is licensed under the MIT License.

## Changelog

### Version 2.0 (Current)
- Added `tailscale-send.sh` with interactive device picker
- Integrated Dolphin context menu for seamless file sending
- Enhanced documentation with comprehensive usage guide
- Added troubleshooting section and FAQ
- Improved error handling and user feedback
- Added support for multiple GUI dialog tools
- Enhanced device detection with JSON parsing

### Version 1.0
- Initial release with automated file receiver
- Systemd service integration
- Desktop notifications
- Basic setup and uninstall scripts