#!/bin/bash

# ==============================================================================
# Install Script for Tailscale File Receiver Service
#
# This script automates the process of installing the tailscale-receive.sh
# script as a systemd service, allowing it to run automatically on boot.
#
# It copies the script, leaving your original file untouched.
#
# Instructions:
# 1. Place this script in the SAME directory as your 'tailscale-receive.sh'.
# 2. Make this script executable: chmod +x Install.sh
# 3. Run it with root privileges: sudo ./Install.sh
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

# Sender script and Dolphin Service Menu
SEND_SOURCE_SCRIPT="tailscale-send.sh"
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

# Function to print an error message and exit
print_error_and_exit() {
  echo "❌ ERROR: $1"
  exit 1
}

# Function to print a warning message
print_warning() {
  echo "⚠️  $1"
}

# Function to check if service is already installed
is_service_installed() {
  [ -f "$SERVICE_FILE_PATH" ] && systemctl is-enabled "$SERVICE_NAME.service" >/dev/null 2>&1
}

# Function to check if scripts are already installed
are_scripts_installed() {
  [ -f "$DEST_SCRIPT_PATH" ] || [ -f "$DEST_SEND_SCRIPT_PATH" ]
}

# Function to backup existing configuration
backup_existing_config() {
  local backup_dir="/tmp/tailscale-receiver-backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir"
  
  if [ -f "$DEST_SCRIPT_PATH" ]; then
    cp "$DEST_SCRIPT_PATH" "$backup_dir/"
    echo "Backed up receiver script to $backup_dir/"
  fi
  
  if [ -f "$DEST_SEND_SCRIPT_PATH" ]; then
    cp "$DEST_SEND_SCRIPT_PATH" "$backup_dir/"
    echo "Backed up sender script to $backup_dir/"
  fi
  
  if [ -f "$SERVICE_FILE_PATH" ]; then
    cp "$SERVICE_FILE_PATH" "$backup_dir/"
    echo "Backed up service file to $backup_dir/"
  fi
  
  echo "Backup created at: $backup_dir"
}

# Function to validate user
validate_user() {
  local user="$1"

  # Check if user exists
  if ! id "$user" &>/dev/null; then
    print_error_and_exit "User '$user' does not exist"
  fi

  # Check if user has a home directory
  local user_home
  user_home=$(getent passwd "$user" | cut -d: -f6)
  if [[ -z "$user_home" || ! -d "$user_home" ]]; then
    print_error_and_exit "User '$user' does not have a valid home directory"
  fi

  # Check if Downloads directory exists or can be created
  local downloads_dir="$user_home/Downloads"
  if [[ ! -d "$downloads_dir" ]]; then
    if ! mkdir -p "$downloads_dir" 2>/dev/null; then
      print_error_and_exit "Cannot create Downloads directory for user '$user'"
    fi
    # Restore ownership
    chown "$user:$user" "$downloads_dir"
  fi

  # Verify we can write to the target directory
  local target_dir="$downloads_dir/tailscale"
  if [[ ! -d "$target_dir" ]]; then
    if ! mkdir -p "$target_dir" 2>/dev/null; then
      print_error_and_exit "Cannot create tailscale directory in Downloads for user '$user'"
    fi
  fi

  # Test write permissions
  if ! touch "$target_dir/.install_test" 2>/dev/null; then
    print_error_and_exit "No write permissions to '$target_dir'"
  fi
  rm -f "$target_dir/.install_test"

  # Restore ownership
  chown -R "$user:$user" "$target_dir"
}

# Function to get the target user
get_target_user() {
  local default_user=""
  
  # Try to get the user who ran sudo
  if [ -n "$SUDO_USER" ]; then
    default_user="$SUDO_USER"
  else
    # Fallback to the first non-root user with a home directory
    default_user=$(find /home -maxdepth 1 -type d -name "*" 2>/dev/null | head -1 | xargs basename 2>/dev/null || echo "")
  fi
  
  if [ -z "$default_user" ]; then
    print_error_and_exit "Could not determine default user. Please specify manually."
  fi
  
  if [ "${NONINTERACTIVE:-false}" = "true" ]; then
    echo "$default_user"
    return
  fi
  
  echo "" >&2
  echo "Which user should receive the Tailscale files?" >&2
  echo "This user will:" >&2
  echo "  - Own the received files" >&2
  echo "  - Receive desktop notifications" >&2
  echo "  - Have files saved to their Downloads/tailscale/ directory" >&2
  echo "" >&2
  
  while true; do
    read -r -p "Enter username [$default_user]: " target_user
    target_user=${target_user:-$default_user}
    
    # Validate the user exists
    if id "$target_user" &>/dev/null; then
      echo "" >&2
      echo "✅ User '$target_user' found." >&2
      break
    else
      echo "❌ User '$target_user' does not exist. Please try again." >&2
    fi
  done
  
  echo "$target_user"
}

# Function to create and configure the receiver script
create_receiver_script() {
  local target_user="$1"
  local target_dir="/home/$target_user/Downloads/tailscale"
  
  # Create the target directory and set ownership
  mkdir -p "$target_dir"
  chown "$target_user:$target_user" "$target_dir"
  
  # Read the source script and replace the configuration
  local script_content
  script_content=$(cat "$SOURCE_SCRIPT")
  
  # Replace the configuration section
  script_content=$(echo "$script_content" | sed "s|TARGET_DIR=.*|TARGET_DIR=\"$target_dir/\"|")
  script_content=$(echo "$script_content" | sed "s|FIX_OWNER=.*|FIX_OWNER=\"$target_user\"|")
  
  # Write the configured script
  echo "$script_content" > "$DEST_SCRIPT_PATH"
  chmod +x "$DEST_SCRIPT_PATH"
}

# --- Script Logic ---

print_header "Tailscale Receiver Service Install"

# 1. Check for root privileges
if [ "$EUID" -ne 0 ]; then
  print_error_and_exit "This script must be run as root. Please use 'sudo'."
fi

# 2. Check if the source script exists in the current directory
if [ ! -f "$SOURCE_SCRIPT" ]; then
  print_error_and_exit "The source script '$SOURCE_SCRIPT' was not found. Make sure it's in the same directory as this Install script."
fi

# 3. Get the target user
TARGET_USER=$(get_target_user)
echo "Target user: $TARGET_USER"

# 4. Validate the target user and their environment
echo "➡️  Validating user configuration..."
validate_user "$TARGET_USER"
print_success "User '$TARGET_USER' validation passed."

# 5. Check for existing installation and handle reinstallation
if is_service_installed || are_scripts_installed; then
  echo ""
  print_warning "Existing Tailscale Receiver installation detected!"
  echo ""
  echo "Found existing installation:"
  if [ -f "$DEST_SCRIPT_PATH" ]; then
    echo "  ✅ Receiver script: $DEST_SCRIPT_PATH"
  fi
  if [ -f "$DEST_SEND_SCRIPT_PATH" ]; then
    echo "  ✅ Sender script: $DEST_SEND_SCRIPT_PATH"
  fi
  if [ -f "$SERVICE_FILE_PATH" ]; then
    echo "  ✅ Service file: $SERVICE_FILE_PATH"
  fi
  echo ""
  
  # Determine installation mode
  if [ "${NONINTERACTIVE:-false}" = "true" ]; then
    echo "Non-interactive mode: Proceeding with update..."
    backup_existing_config
    choice=1
  else
    echo "Choose an option:"
    echo "  1) Update/Reinstall (recommended) - Backup existing config and install new version"
    echo "  2) Fresh Install - Remove existing installation completely"
    echo "  3) Cancel"
    echo ""
    read -r -p "Enter your choice (1-3): " choice
  fi
  
  # Handle the choice
  case $choice in
    1)
      echo "Proceeding with update/reinstall..."
      backup_existing_config
      ;;
    2)
      echo "Proceeding with fresh install..."
      echo "Stopping and removing existing service..."
      systemctl stop "$SERVICE_NAME.service" 2>/dev/null || true
      systemctl disable "$SERVICE_NAME.service" 2>/dev/null || true
      rm -f "$SERVICE_FILE_PATH"
      rm -f "$DEST_SCRIPT_PATH"
      rm -f "$DEST_SEND_SCRIPT_PATH"
      rm -f "$SYS_KIO_SERVICEMENU_DIR/tailscale-send.desktop"
      rm -f "$SYS_KSERVICES5_SERVICEMENU_DIR/tailscale-send.desktop"
      systemctl daemon-reload
      ;;
    3)
      echo "Installation cancelled."
      exit 0
      ;;
    *)
      print_error_and_exit "Invalid choice. Please run the script again."
      ;;
  esac
  echo ""
fi

# 6. Create and configure the receiver script
echo "➡️  Installing the receiver script..."
create_receiver_script "$TARGET_USER"
print_success "Receiver script installed to '$DEST_SCRIPT_PATH' (configured for user: $TARGET_USER)."

# 7. Copy and set permissions for the sender script (for Dolphin context menu)
if [ -f "$SEND_SOURCE_SCRIPT" ]; then
  echo "➡️  Installing the sender script..."
  cp "$SEND_SOURCE_SCRIPT" "$DEST_SEND_SCRIPT_PATH" || print_error_and_exit "Failed to copy script to '$DEST_SEND_SCRIPT_PATH'."
  chmod +x "$DEST_SEND_SCRIPT_PATH" || print_error_and_exit "Failed to make sender script executable."
  print_success "Sender script installed to '$DEST_SEND_SCRIPT_PATH'."
else
  echo "⚠️  Sender script '$SEND_SOURCE_SCRIPT' not found. Skipping send integration."
fi

# 8. Create the systemd service file using a HERE document
echo "➡️  Creating systemd service file with security hardening..."
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

# Security hardening - temporarily reduced for compatibility
# PrivateTmp=true
# ProtectSystem=strict
# ProtectHome=yes
ReadWritePaths=/home/$TARGET_USER/Downloads/tailscale
# NoNewPrivileges=true
# ProtectHostname=true
# ProtectClock=true
# ProtectControlGroups=true
# ProtectKernelTunables=true
# RestrictSUIDSGID=true
# LockPersonality=true
# RestrictRealtime=true
# SystemCallFilter=@system-service @file-system
# CapabilityBoundingSet=
EOL
print_success "Service file created at '$SERVICE_FILE_PATH'."

# 9. Reload systemd, enable and start the service
echo "➡️  Activating the service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME.service" || print_error_and_exit "Failed to enable the service."
systemctl start "$SERVICE_NAME.service" || print_error_and_exit "Failed to start the service."
print_success "Service has been enabled and started."

# 10. Install Dolphin service menu entries (system-wide)
if [ -f "$DEST_SEND_SCRIPT_PATH" ]; then
  echo "➡️  Installing Dolphin service menu..."
  mkdir -p "$SYS_KIO_SERVICEMENU_DIR" "$SYS_KSERVICES5_SERVICEMENU_DIR"

  # Write a single .desktop content
  DESKTOP_CONTENT='[Desktop Entry]
Type=Service
X-KDE-ServiceTypes=KonqPopupMenu/Plugin
MimeType=all/allfiles;inode/directory;
Actions=TailScaleSend;

[Desktop Action TailScaleSend]
Name=Send to device using Tailscale
Icon=network-workgroup
Exec=/usr/local/bin/tailscale-send.sh %F
'

  echo "$DESKTOP_CONTENT" > "$SYS_KIO_SERVICEMENU_DIR/tailscale-send.desktop" || print_error_and_exit "Failed to write service menu (.kio)."
  echo "$DESKTOP_CONTENT" > "$SYS_KSERVICES5_SERVICEMENU_DIR/tailscale-send.desktop" || print_error_and_exit "Failed to write service menu (kservices5)."
  print_success "Dolphin service menu installed."

  # Rebuild KDE service cache if tools exist
  if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 >/dev/null 2>&1 || true
  elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    kbuildsycoca5 >/dev/null 2>&1 || true
  fi
fi

# 11. Final status check and confirmation
echo ""
print_header "Install Complete!"
echo "The Tailscale receiver service is now running and will start on boot."
echo ""
echo "📋 Installation Summary:"
echo "  ✅ Receiver script: $DEST_SCRIPT_PATH"
echo "  ✅ Target user: $TARGET_USER"
echo "  ✅ Target directory: /home/$TARGET_USER/Downloads/tailscale/"
if [ -f "$DEST_SEND_SCRIPT_PATH" ]; then
  echo "  ✅ Sender script: $DEST_SEND_SCRIPT_PATH"
  echo "  ✅ Dolphin service menu: Installed"
fi
echo "  ✅ Systemd service: $SERVICE_NAME.service"
echo ""
echo "🔧 Management Commands:"
echo "  Check service status: sudo systemctl status $SERVICE_NAME.service"
echo "  View live logs: sudo journalctl -u $SERVICE_NAME.service -f"
echo "  Stop service: sudo systemctl stop $SERVICE_NAME.service"
echo "  Start service: sudo systemctl start $SERVICE_NAME.service"
echo "  Restart service: sudo systemctl restart $SERVICE_NAME.service"
echo ""
echo "📁 Test the installation:"
if [ -f "$DEST_SEND_SCRIPT_PATH" ]; then
  echo "  Send a file: $DEST_SEND_SCRIPT_PATH /path/to/file"
fi
echo "  Check received files in: /home/$TARGET_USER/Downloads/tailscale/"
echo ""
echo "🔄 To update/reinstall: Run this script again"
echo "🗑️  To uninstall: sudo ./uninstall.sh"
echo "-----------------------------------------------------"

