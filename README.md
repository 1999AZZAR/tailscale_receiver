# Tailscale Auto-File Receiver Service

## Overview

This project provides a robust solution for automatically receiving files sent via Tailscale's file-sharing feature. It runs a script as a background systemd service that actively listens for incoming files, moves them to your desired directory, corrects their ownership, and sends a desktop notification upon successful receipt.

The project includes:
- `tailscale-receive.sh`: The core script that watches for and processes incoming files.
- `setup.sh`: An automated installer that configures and runs the receiver script as a systemd service.
- `uninstall.sh`: A script to completely remove the service and all related files.

This setup is ideal for users who frequently receive files through Tailscale and want a seamless, automated experience without manual intervention.

## Features

- **Automated File Reception**: Runs continuously to accept incoming Tailscale files.
- **Systemd Integration**: Deploys the receiver script as a proper systemd service for reliability and auto-start on boot.
- **Desktop Notifications**: Informs the user of newly received files via `notify-send`.
- **Ownership Correction**: Automatically changes the ownership of received files from `root` to your user.
- **Health Checks**: Ensures an internet connection is active and the Tailscale service is running before checking for files.
- **Automated Setup & Uninstallation**: Scripts handle all installation, configuration, and removal steps.

## Prerequisites

- A Linux system with `systemd` (e.g., Ubuntu, Debian, Fedora, Arch Linux).
- Tailscale installed and configured.
- Root privileges (`sudo`) are required to run the setup and uninstall scripts.
- `notify-send` command-line tool (usually installed by default with most desktop environments).

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
    The service will now be running in the background and will automatically start on boot.

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

## How It Works

### `tailscale-receive.sh`

This is the core worker script. It runs in an infinite loop, checking for files every 15 seconds.
1.  It performs health checks for an internet connection and the Tailscale daemon.
2.  It runs `tailscale file get` to accept any pending files into the specified `TARGET_DIR`.
3.  It compares the directory contents before and after the `get` command to identify new files.
4.  If new files are found, it corrects their ownership using `chown` and sends a desktop notification as your user.

### `setup.sh`

This script automates the installation by:
1.  Copying your configured `tailscale-receive.sh` to `/usr/local/bin`.
2.  Creating a systemd service file (`/etc/systemd/system/tailscale-receive.service`) that defines how to run the script as `root`.
3.  Reloading the systemd daemon, enabling the service to start on boot, and starting it immediately.

## License

This project is licensed under the MIT License.
