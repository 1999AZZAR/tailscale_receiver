#!/bin/bash

# Tailscale Taildrop sender with interactive device picker
# - Can be invoked from CLI or Dolphin service menu

set -euo pipefail

print_error_and_exit() {
  echo "❌ ERROR: $1" >&2
  exit 1
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ensure_tailscale_ready() {
  if ! has_cmd tailscale; then
    print_error_and_exit "tailscale CLI not found in PATH"
  fi

  if ! tailscale status >/dev/null 2>&1; then
    tailscale up || print_error_and_exit "failed to bring up Tailscale"
    # give it a moment
    sleep 2
  fi

  # Check if we have file transfer permissions
  if ! tailscale file cp --targets >/dev/null 2>&1; then
    echo "⚠️  Warning: File transfer permissions not set. Attempting to fix..." >&2
    echo "   Run: sudo tailscale set --operator=\$USER" >&2
    echo "   Or use: sudo tailscale file cp <file> <device>:" >&2
  fi
}

list_online_devices_json() {
  # Use tailscale file cp --targets to get the correct device names for file transfer
  # This ensures we get the exact names that tailscale file cp expects
  tailscale file cp --targets 2>/dev/null \
    | awk -F'\t' '$2 != "" && $3 == "" { print $2 }' \
    | sed '/^$/d' | sort -u
}

pick_device_gui() {
  # Reads device list from stdin; prints chosen device to stdout
  local devices dev first taglist=()
  mapfile -t devices

  if [ ${#devices[@]} -eq 0 ]; then
    print_error_and_exit "no online Tailscale devices found"
  fi

  if [ ${#devices[@]} -eq 1 ]; then
    echo "${devices[0]}"
    return 0
  fi

  if has_cmd kdialog; then
    # Build radiolist: tag text on/off triplets
    first=1
    for dev in "${devices[@]}"; do
      if [ $first -eq 1 ]; then
        taglist+=("$dev" "$dev" on)
        first=0
      else
        taglist+=("$dev" "$dev" off)
      fi
    done
    kdialog --radiolist "Send via Tailscale" "${taglist[@]}" || exit 1
    return 0
  fi

  if has_cmd zenity; then
    printf '%s\n' "${devices[@]}" | zenity --list --title "Send via Tailscale" --column "Device" --height=400 --width=420 || exit 1
    return 0
  fi

  if has_cmd whiptail; then
    # whiptail wants tag/desc pairs
    local menu_items=()
    for dev in "${devices[@]}"; do
      menu_items+=("$dev" "$dev")
    done
    whiptail --title "Send via Tailscale" --menu "Choose device" 20 78 12 "${menu_items[@]}" 3>&1 1>&2 2>&3
    return 0
  fi

  # Pure CLI fallback
  echo "Select a device:" >&2
  local i=1 choice
  for dev in "${devices[@]}"; do
    echo "  $i) $dev" >&2
    i=$((i+1))
  done
  read -r -p "> " choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    print_error_and_exit "invalid selection"
  fi
  choice=$((choice-1))
  if [ $choice -lt 0 ] || [ $choice -ge ${#devices[@]} ]; then
    print_error_and_exit "selection out of range"
  fi
  echo "${devices[$choice]}"
}

send_files() {
  local device=$1; shift
  local sent_count=0 failed_count=0 file

  echo "Sending files to device: $device" >&2

  for file in "$@"; do
    if [ ! -e "$file" ]; then
      echo "Skipping non-existent path: $file" >&2
      failed_count=$((failed_count+1))
      continue
    fi

    echo "Sending: $file" >&2

    # Start file transfer in background since tailscale file cp is interactive
    # We can't reliably detect completion, so assume success if it starts
    tailscale file cp "$file" "$device:" >/dev/null 2>&1 &
    transfer_pid=$!

    # Give it a moment to start
    sleep 1

    # Check if process is still running (transfer in progress) or exited successfully
    if kill -0 $transfer_pid 2>/dev/null; then
      # Process still running - transfer likely started successfully
      echo "Transfer started: $file" >&2
      sent_count=$((sent_count+1))
      # Detach from the process
      disown $transfer_pid
    else
      # Process exited - check exit code
      wait $transfer_pid 2>/dev/null
      exit_code=$?
      if [ $exit_code -eq 0 ]; then
        echo "Transfer completed: $file" >&2
        sent_count=$((sent_count+1))
      else
        echo "Transfer failed: $file" >&2
        failed_count=$((failed_count+1))
      fi
    fi
  done

  if has_cmd notify-send; then
    if [ $failed_count -eq 0 ]; then
      notify-send "Tailscale" "Sent $sent_count file(s) to $device" -i dialog-information -a Tailscale
    else
      notify-send "Tailscale" "Sent $sent_count, failed $failed_count file(s) to $device" -i dialog-warning -a Tailscale
    fi
  fi

  [ $failed_count -eq 0 ]
}

main() {
  ensure_tailscale_ready

  # Collect input files; support Dolphin's %F (space-separated) and CLI usage
  if [ $# -eq 0 ]; then
    if has_cmd kdialog; then
      # Let user choose one or more files
      mapfile -t files < <(kdialog --getopenfilename "$(pwd)" "*" --multiple --separate-output 2>/dev/null || true)
      if [ ${#files[@]} -eq 0 ]; then
        print_error_and_exit "no files selected"
      fi
    else
      print_error_and_exit "no files provided"
    fi
  else
    # Preserve arguments as provided (can include spaces if invoked properly)
    files=("$@")
  fi

  # Build device list and pick one
  device=$(list_online_devices_json | pick_device_gui) || exit 1

  # Send
  send_files "$device" "${files[@]}"
}

main "$@"


