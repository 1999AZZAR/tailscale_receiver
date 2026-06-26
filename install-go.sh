#!/bin/bash
set -euo pipefail

BINARY="tailscale-receiver-go"
DEST="/usr/local/bin/${BINARY}"
SERVICE_FILE="tailscale-receive-go.service"
SEND_SCRIPT="tailscale-send.sh"
SEND_DEST="/usr/local/bin/${SEND_SCRIPT}"
NAUTILUS_SCRIPT="nautilus-send-to-tailscale"
DESKTOP_FILE="tailscale-send.desktop"
CONFIG_FILE="/etc/default/tailscale-receive"

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

detect_user() {
	local u
	u=$(logname 2>/dev/null || true)
	[ -z "$u" ] && u=$(who am i | awk '{print $1}' 2>/dev/null || true)
	[ -z "$u" ] && u=$(getent passwd 1000 | cut -d: -f1 2>/dev/null || true)
	[ -z "$u" ] && u="youruser"
	echo "$u"
}

install_send_script() {
	echo ""
	echo "Installing send script to $SEND_DEST..."
	install -m 0755 "$SEND_SCRIPT" "$SEND_DEST"
}

install_nautilus_integration() {
	local user home nautilus_dir
	user="$1"
	home=$(getent passwd "$user" | cut -d: -f6)

	[ -z "$home" ] && return
	nautilus_dir="$home/.local/share/nautilus/scripts"
	[ ! -d "$nautilus_dir" ] && return

	echo "Installing Nautilus script for user '$user'..."
	mkdir -p "$nautilus_dir"
	install -m 0755 "$NAUTILUS_SCRIPT" "$nautilus_dir/Send via Tailscale"
	# chown to the user so Nautilus can find it
	chown "$user:" "$nautilus_dir/Send via Tailscale" 2>/dev/null || true
}

install_dolphin_integration() {
	local kde_paths=(
		"/usr/share/kio/servicemenus"
		"/usr/share/kservices5/ServiceMenus"
	)
	local installed=0
	for dir in "${kde_paths[@]}"; do
		if [ -d "$dir" ]; then
			echo "Installing Dolphin service menu to $dir..."
			install -m 0644 "$DESKTOP_FILE" "$dir/"
			installed=1
		fi
	done

	if [ "$installed" -eq 1 ] && command -v kbuildsycoca5 &>/dev/null; then
		kbuildsycoca5 --noincremental 2>/dev/null || true
	elif [ "$installed" -eq 1 ] && command -v kbuildsycoca6 &>/dev/null; then
		kbuildsycoca6 --noincremental 2>/dev/null || true
	fi
}

# === MAIN ===

echo "=== Tailscale Receiver Go Installer ==="
echo ""

preflight
echo "Preflight checks passed."

TARGET_USER="${TARGET_USER:-$(detect_user)}"
TARGET_DIR="${TARGET_DIR:-/home/${TARGET_USER}/Downloads/tailscale}"

# Build receiver
echo ""
echo "Building receiver binary..."
go build -ldflags="-s -w" -o "$BINARY" ./cmd/receiver/
echo "Build OK."

if [ -f "$DEST" ]; then
	echo "Backing up $DEST to ${DEST}.bak"
	cp "$DEST" "${DEST}.bak"
fi

install -m 0755 "$BINARY" "$DEST"
install -m 0644 "$SERVICE_FILE" /etc/systemd/system/tailscale-receive-go.service

# Send-side components
install_send_script
install_nautilus_integration "$TARGET_USER"
install_dolphin_integration

# Config
echo ""
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

systemctl daemon-reload

echo ""
echo "=== Done ==="
echo ""
echo "Receiver service:"
echo "  sudo systemctl enable --now tailscale-receive-go"
echo "  sudo journalctl -u tailscale-receive-go -f"
echo ""
echo "Send files from CLI:"
echo "  tailscale-send.sh <file>..."
echo ""
echo "Send from file manager:"
echo "  Nautilus: right-click file -> Scripts -> Send via Tailscale"
echo "  Dolphin:  right-click file -> Actions -> Send to device using Tailscale"
echo ""
echo "Config:  sudoedit $CONFIG_FILE"
