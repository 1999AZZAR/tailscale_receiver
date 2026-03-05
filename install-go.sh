#!/bin/bash
set -e

DEST="/usr/local/bin/tailscale-receiver-go"
SERVICE_FILE="tailscale-receive-go.service"

echo "Building Tailscale Receiver (Go)..."
go build -o tailscale-receiver-go cmd/receiver/main.go

echo "Installing binary to $DEST..."
sudo cp tailscale-receiver-go "$DEST"
sudo chmod +x "$DEST"

echo "Installing systemd service..."
sudo cp "$SERVICE_FILE" /etc/systemd/system/

echo "Reloading systemd..."
sudo systemctl daemon-reload

echo "Done! You can start the service with: sudo systemctl enable --now tailscale-receive-go"
