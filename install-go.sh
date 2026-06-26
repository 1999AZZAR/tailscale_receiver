#!/bin/bash
set -euo pipefail

DEST="/usr/local/bin/tailscale-receiver-go"
SERVICE_FILE="tailscale-receive-go.service"
CONFIG_FILE="/etc/default/tailscale-receive"
BINARY="tailscale-receiver-go"

preflight() {
	local missing=0
	if ! command -v go &>/dev/null; then
		echo "ERROR: Go compiler not found. Install Go >= 1.24 first." >&2
		missing=1
	fi
	if ! command -v systemctl &>/dev/null; then
		echo "ERROR: systemctl not found. systemd is required." >&2
		missing=1
	fi
	if ! command -v tailscale &>/dev/null; then
		echo "WARNING: tailscale CLI not found. Install tailscale first." >&2
	fi
	return "$missing"
}

echo "=== Tailscale Receiver Go Installer ==="
echo ""

preflight
echo "Preflight checks passed."
echo ""

echo "Building binary..."
go build -ldflags="-s -w" -o "$BINARY" ./cmd/receiver/
echo "Build OK."
echo ""

if [ -f "$DEST" ]; then
	echo "Backing up existing binary to ${DEST}.bak"
	cp "$DEST" "${DEST}.bak"
fi

echo "Installing binary to $DEST..."
install -m 0755 "$BINARY" "$DEST"

echo "Installing systemd service..."
install -m 0644 "$SERVICE_FILE" /etc/systemd/system/tailscale-receive-go.service

detect_user() {
	local u
	u=$(logname 2>/dev/null || true)
	[ -z "$u" ] && u=$(who am i | awk '{print $1}' 2>/dev/null || true)
	[ -z "$u" ] && u=$(getent passwd 1000 | cut -d: -f1 2>/dev/null || true)
	[ -z "$u" ] && u="youruser"
	echo "$u"
}

TARGET_USER="${TARGET_USER:-$(detect_user)}"
TARGET_DIR="${TARGET_DIR:-/home/${TARGET_USER}/Downloads/tailscale}"

echo "Writing config to $CONFIG_FILE for user '$TARGET_USER'..."
install -m 600 /dev/null "$CONFIG_FILE"
cat > "$CONFIG_FILE" <<- CFG
	# Tailscale Receiver configuration
	TARGET_USER=${TARGET_USER}
	TARGET_DIR=${TARGET_DIR}
	# LOG_LEVEL=info
	# POLL_INTERVAL=15s
	# ARCHIVE_DAYS=14
CFG

echo "Reloading systemd..."
systemctl daemon-reload

echo ""
echo "=== Done ==="
echo ""
echo "Start service:   sudo systemctl enable --now tailscale-receive-go"
echo "Check status:    sudo systemctl status tailscale-receive-go"
echo "View logs:       sudo journalctl -u tailscale-receive-go -f"
echo "Edit config:     sudoedit $CONFIG_FILE"
