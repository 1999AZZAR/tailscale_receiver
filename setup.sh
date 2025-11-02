#!/bin/bash

# Tailscale Receiver Setup Script v2.2.1
# This script provides automated installation for Tailscale Receiver

set -euo pipefail

# Version information
readonly VERSION="2.2.1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_error "Please do not run this script as root. It will ask for sudo when needed."
    exit 1
fi

log_info "🚀 Tailscale Receiver - Automated Setup"
echo ""

# Handle version flag
if [[ "${1:-}" == "--version" ]] || [[ "${1:-}" == "-v" ]]; then
  echo "Tailscale Receiver Setup Script v${VERSION}"
  exit 0
fi

# Check if Tailscale is installed
if ! command -v tailscale >/dev/null 2>&1; then
    log_error "Tailscale is not installed."
    echo ""
    echo "Please install Tailscale first:"
    echo "  Ubuntu/Debian: curl -fsSL https://tailscale.com/install.sh | sh"
    echo "  Other systems: Visit https://tailscale.com/download"
    echo ""
    echo "Then run this setup script again."
    exit 1
fi

log_success "Tailscale is installed"

# Check if Tailscale is authenticated
if ! tailscale status >/dev/null 2>&1; then
    log_warn "Tailscale is not authenticated."
    echo ""
    echo "Please authenticate Tailscale first:"
    echo "  sudo tailscale up"
    echo ""
    echo "Then run this setup script again."
    exit 1
fi

log_success "Tailscale is authenticated"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
log_info "Using temporary directory: $TEMP_DIR"

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

# Change to temp directory
cd "$TEMP_DIR"

# Download the repository
log_info "Downloading Tailscale Receiver..."
if command -v git >/dev/null 2>&1; then
    git clone https://github.com/1999AZZAR/tailscale_receiver.git .
else
    # Fallback to downloading individual files
    log_warn "git not found, downloading files individually..."

    BASE_URL="https://raw.githubusercontent.com/1999AZZAR/tailscale_receiver/main"

    for file in install.sh tailscale-receive.sh tailscale-send.sh; do
        log_info "Downloading $file..."
        curl -fsSLO "$BASE_URL/$file" || wget -q "$BASE_URL/$file" || {
            log_error "Failed to download $file"
            exit 1
        }
    done
fi

# Make scripts executable
log_info "Setting up permissions..."
chmod +x install.sh tailscale-receive.sh tailscale-send.sh

# Run installation
log_info "Starting installation..."
echo ""
echo "The installation will now begin. You may be prompted for your sudo password."
echo ""

sudo ./install.sh

echo ""
log_success "🎉 Tailscale Receiver has been successfully installed!"
echo ""
echo "📋 What you can do now:"
echo "  • Send files from your phone to this computer"
echo "  • Use the sender script: /usr/local/bin/tailscale-send.sh <file>"
echo "  • Right-click files in Dolphin to send them"
echo "  • Check service status: sudo systemctl status tailscale-receive.service"
echo "  • View logs: sudo journalctl -u tailscale-receive.service -f"
echo ""
echo "📁 Received files will be saved to: ~/Downloads/tailscale/"
echo ""
echo "Happy file sharing! 📱💻"
