#!/bin/bash

# ==============================================================================
# Uninstall Script for Tailscale File Receiver Service
#
# This script completely removes the Tailscale receiver service and all
# associated files created by the setup.sh script.
#
# Instructions:
# 1. Make this script executable: chmod +x uninstall.sh
# 2. Run it with root privileges: sudo ./uninstall.sh
# ==============================================================================

# --- Configuration ---
# These variables must match the ones in the setup script to ensure
# the correct files and services are targeted for removal.
DEST_SCRIPT_PATH="/usr/local/bin/tailscale-receive.sh"
SERVICE_NAME="tailscale-receive"
SERVICE_FILE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
DEST_SEND_SCRIPT_PATH="/usr/local/bin/tailscale-send.sh"
SYS_KIO_SERVICEMENU_DIR="/usr/share/kio/servicemenus"
SYS_KSERVICES5_SERVICEMENU_DIR="/usr/share/kservices5/ServiceMenus"

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

# Function to print a warning message
print_warning() {
  echo "⚠️  $1"
}

# Function to print an error message and exit
print_error_and_exit() {
  echo "❌ ERROR: $1"
  exit 1
}


# --- Script Logic ---

print_header "Tailscale Receiver Service Uninstaller"

# 1. Check for root privileges
if [ "$EUID" -ne 0 ]; then
  print_error_and_exit "This script must be run as root. Please use 'sudo'."
fi

# 2. Stop and disable the systemd service
echo "➡️  Disabling the systemd service..."
# Check if the service is active before trying to stop it
if systemctl is-active --quiet "$SERVICE_NAME.service"; then
  systemctl stop "$SERVICE_NAME.service" || print_error_and_exit "Failed to stop the service."
  print_success "Service stopped."
else
  print_warning "Service was not running."
fi

# Check if the service is enabled before trying to disable it
if systemctl is-enabled --quiet "$SERVICE_NAME.service"; then
  systemctl disable "$SERVICE_NAME.service" || print_error_and_exit "Failed to disable the service."
  print_success "Service disabled."
else
  print_warning "Service was not enabled."
fi

# 3. Remove the systemd service file
echo "➡️  Removing service file..."
if [ -f "$SERVICE_FILE_PATH" ]; then
  rm "$SERVICE_FILE_PATH" || print_error_and_exit "Failed to remove service file."
  print_success "Service file removed."
else
  print_warning "Service file not found at '$SERVICE_FILE_PATH'."
fi

# 4. Reload the systemd daemon to apply changes
echo "➡️  Reloading systemd daemon..."
systemctl daemon-reload
print_success "Systemd daemon reloaded."

# 5. Remove the receiver script from /usr/local/bin
echo "➡️  Removing receiver script..."
if [ -f "$DEST_SCRIPT_PATH" ]; then
  rm "$DEST_SCRIPT_PATH" || print_error_and_exit "Failed to remove the script."
  print_success "Receiver script removed from '$DEST_SCRIPT_PATH'."
else
  print_warning "Receiver script not found at '$DEST_SCRIPT_PATH'."
fi

# 6. Remove the sender script and Dolphin service menus
echo "➡️  Removing sender script and Dolphin service menus..."
if [ -f "$DEST_SEND_SCRIPT_PATH" ]; then
  rm "$DEST_SEND_SCRIPT_PATH" || print_error_and_exit "Failed to remove the sender script."
  print_success "Sender script removed from '$DEST_SEND_SCRIPT_PATH'."
else
  print_warning "Sender script not found at '$DEST_SEND_SCRIPT_PATH'."
fi

if [ -f "$SYS_KIO_SERVICEMENU_DIR/tailscale-send.desktop" ]; then
  rm "$SYS_KIO_SERVICEMENU_DIR/tailscale-send.desktop" || print_error_and_exit "Failed to remove service menu (.kio)."
  print_success "Removed $SYS_KIO_SERVICEMENU_DIR/tailscale-send.desktop."
fi
if [ -f "$SYS_KSERVICES5_SERVICEMENU_DIR/tailscale-send.desktop" ]; then
  rm "$SYS_KSERVICES5_SERVICEMENU_DIR/tailscale-send.desktop" || print_error_and_exit "Failed to remove service menu (kservices5)."
  print_success "Removed $SYS_KSERVICES5_SERVICEMENU_DIR/tailscale-send.desktop."
fi

if command -v kbuildsycoca6 >/dev/null 2>&1; then
  kbuildsycoca6 >/dev/null 2>&1 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
  kbuildsycoca5 >/dev/null 2>&1 || true
fi

# 7. Final confirmation
echo ""
print_header "Uninstall Complete!"
echo "The Tailscale receiver service and all related files have been removed."
echo "-----------------------------------------------------"

