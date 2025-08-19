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
}

list_online_devices_json() {
  # Outputs a newline-separated list of online peer device names (best-effort DNSName/HostName)
  if has_cmd jq; then
    tailscale status --json 2>/dev/null \
      | jq -r '
        (.Peer // {})
        | to_entries
        | map(.value)
        | map(select(.Online == true))
        | map(.DNSName // .HostName // .Hostinfo.Hostname // .Name)
        | map(sub("\\.$"; ""))
        | .[]
      ' | sed '/^$/d' | sort -u
  else
    # Fallback: parse text table from `tailscale status`
    # Columns: 1=TS IP, 2=machine, 3=user, 4=os, 5=status
    tailscale status 2>/dev/null \
      | awk 'NR>1 { if ($5 ~ /active|idle/) print $2 }' \
      | sed '/^$/d' | sort -u
  fi
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

  for file in "$@"; do
    if [ ! -e "$file" ]; then
      echo "Skipping non-existent path: $file" >&2
      failed_count=$((failed_count+1))
      continue
    fi

    if tailscale file cp "$file" "$device:"; then
      sent_count=$((sent_count+1))
    else
      failed_count=$((failed_count+1))
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


