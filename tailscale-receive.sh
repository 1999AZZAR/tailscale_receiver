#!/bin/bash

# --- Configuration ---
TARGET_DIR="home/azzar/Downloads/tailscale/"
FIX_OWNER="azzar"

# --- Script Starts ---
echo "✅ Starting Tailscale receiver script with notifications."
mkdir -p "$TARGET_DIR"

while true; do
  # 1. Basic health checks (internet, tailscale status)
  if ! ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
    sleep 15
    continue
  fi
  if ! tailscale status &>/dev/null; then
    tailscale up
    sleep 5
    continue
  fi

  # 2. Get a snapshot of files BEFORE receiving
  files_before=$(ls -A "$TARGET_DIR")

  # 3. Attempt to get new files
  tailscale file get "$TARGET_DIR"

  # 4. Get a snapshot of files AFTER receiving
  files_after=$(ls -A "$TARGET_DIR")

  # 5. Compare the snapshots to find new files
  new_files=$(comm -13 <(echo "$files_before" | sort) <(echo "$files_after" | sort))

  # 6. If new files were found, process them
  if [ -n "$new_files" ]; then
    echo "📬 New files detected: $new_files"
    # Loop through each new file
    while IFS= read -r filename; do
      # Fix ownership of the new file
      sudo chown "$FIX_OWNER:$FIX_OWNER" "$TARGET_DIR$filename"

      # Send notification AS YOUR USER using notify-send
      runuser -l "$FIX_OWNER" -c "notify-send 'Tailscale: File Received' '$filename' -i document-save -a Tailscale"
    done <<< "$new_files"
  fi

  sleep 15
done
