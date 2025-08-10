#!/bin/bash

# ==============================================================================
# Setup Script for Tailscale File Receiver Service
#
# This script automates the process of installing the tailscale-receive.sh
# script as a systemd service, allowing it to run automatically on boot.
#
# It copies the script, leaving your original file untouched.
#
# Instructions:
# 1. Place this script in the SAME directory as your 'tailscale-receive.sh'.
# 2. Make this script executable: chmod +x setup.sh
# 3. Run it with root privileges: sudo ./setup.sh
# ==============================================================================

# --- Configuration ---
# The original script that needs to be turned into a service.
SOURCE_SCRIPT="tailscale-receive.sh"
# Where the script will be copied to for system-wide access.
DEST_SCRIPT_PATH="/usr/local/bin/tailscale-receive.sh"
# The name of the systemd service we are creating.
SERVICE_NAME="tailscale-receive"
# The full path to the systemd service file.
SERVICE_FILE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# --- Functions ---

# Function to print a formatted header
print_header() {
  echo "-----------------------------------------------------"
  echo "  $1"
  echo "-----------------------------------------------------"
}

# Function to print a success message
print_success() {
  echo "✅ $1"
}

# Function to print an error message and exit
print_error_and_exit() {
  echo "❌ ERROR: $1"
  exit 1
}


# --- Script Logic ---

print_header "Tailscale Receiver Service Setup"

# 1. Check for root privileges
if [ "$EUID" -ne 0 ]; then
  print_error_and_exit "This script must be run as root. Please use 'sudo'."
fi

# 2. Check if the source script exists in the current directory
if [ ! -f "$SOURCE_SCRIPT" ]; then
  print_error_and_exit "The source script '$SOURCE_SCRIPT' was not found. Make sure it's in the same directory as this setup script."
fi

# 3. Copy and set permissions for the receiver script
echo "➡️  Installing the receiver script..."
cp "$SOURCE_SCRIPT" "$DEST_SCRIPT_PATH" || print_error_and_exit "Failed to copy script to '$DEST_SCRIPT_PATH'."
chmod +x "$DEST_SCRIPT_PATH" || print_error_and_exit "Failed to make script executable."
print_success "Receiver script installed to '$DEST_SCRIPT_PATH'."

# 4. Create the systemd service file using a HERE document
echo "➡️  Creating systemd service file..."
cat > "$SERVICE_FILE_PATH" << EOL
[Unit]
Description=Tailscale File Receiver Service
Documentation=https://github.com/your-repo (optional)
After=network-online.target tailscale.service
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=$DEST_SCRIPT_PATH
Restart=on-failure
RestartSec=15s

[Install]
WantedBy=multi-user.target
EOL
print_success "Service file created at '$SERVICE_FILE_PATH'."

# 5. Reload systemd, enable and start the service
echo "➡️  Activating the service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME.service" || print_error_and_exit "Failed to enable the service."
systemctl start "$SERVICE_NAME.service" || print_error_and_exit "Failed to start the service."
print_success "Service has been enabled and started."

# 6. Final status check and confirmation
echo ""
print_header "Setup Complete!"
echo "The Tailscale receiver service is now running and will start on boot."
echo ""
echo "You can check its status anytime with:"
echo "   sudo systemctl status $SERVICE_NAME.service"
echo ""
echo "You can view its live logs with:"
echo "   sudo journalctl -u $SERVICE_NAME.service -f"
echo "-----------------------------------------------------"

