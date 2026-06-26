#!/bin/bash
set -euo pipefail

VERSION="3.1.0"

die() { echo "ERROR: $*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

ensure_tailscale() {
  has tailscale || die "tailscale CLI not found in PATH"
  tailscale status >/dev/null 2>&1 || {
    echo "Tailscale is not connected. Run 'tailscale up' first." >&2
    exit 1
  }
}

list_devices() {
  tailscale file cp --targets 2>/dev/null \
    | awk -F'\t' '$2 != "" && $3 == "" { print $2 }' \
    | sed '/^$/d' | sort -u
}

pick_device() {
  local devices=("$@")
  case ${#devices[@]} in
    0) die "no online Tailscale devices found" ;;
    1) echo "${devices[0]}"; return 0 ;;
  esac

  if has kdialog; then
    local args=()
    for d in "${devices[@]}"; do args+=("$d" "$d" off); done
    args[2]=on
    kdialog --radiolist "Send via Tailscale — select device" "${args[@]}" || exit 1
    return 0
  fi

  if has zenity; then
    printf '%s\n' "${devices[@]}" \
      | zenity --list --title "Send via Tailscale" --column "Device" \
        --height=400 --width=420 || exit 1
    return 0
  fi

  if has whiptail; then
    local items=()
    for d in "${devices[@]}"; do items+=("$d" "$d"); done
    whiptail --title "Send via Tailscale" --menu "Choose device" \
      20 78 12 "${items[@]}" 3>&1 1>&2 2>&3 || exit 1
    return 0
  fi

  echo "Devices:" >&2
  local i=1
  for d in "${devices[@]}"; do echo "  $i) $d" >&2; ((i++)); done
  read -r -p "Select device [1-${#devices[@]}]: " choice
  [[ "$choice" =~ ^[0-9]+$ ]] || die "invalid selection"
  ((choice < 1 || choice > ${#devices[@]})) && die "selection out of range"
  echo "${devices[$((choice-1))]}"
}

send_files() {
  local device=$1; shift
  local ok=0 fail=0 f pid

  for f in "$@"; do
    [[ -e "$f" ]] || { echo "skipping (not found): $f" >&2; ((fail++)); continue; }
    echo "sending: $f -> $device" >&2

    # tailscale file cp can hang waiting for the peer;
    # background it and check after 2s whether it's still running
    tailscale file cp "$f" "$device:" 2>/dev/null &
    pid=$!
    sleep 2

    if kill -0 "$pid" 2>/dev/null; then
      # still running — transfer initiated, detach
      disown "$pid" 2>/dev/null || true
      echo "transfer started: $f" >&2
      ((ok++))
    else
      wait "$pid" 2>/dev/null || true
      local rc=$?
      if [ "$rc" -eq 0 ]; then
        echo "transfer complete: $f" >&2
        ((ok++))
      else
        echo "FAILED: $f (exit $rc)" >&2
        ((fail++))
      fi
    fi
  done

  if has notify-send; then
    local msg
    if ((fail == 0)); then
      msg="Sent $ok file(s) to $device"
    else
      msg="Sent $ok, failed $fail file(s) to $device"
    fi
    notify-send "Tailscale" "$msg" -i dialog-information -a Tailscale
  fi

  return "$fail"
}

main() {
  case "${1:-}" in
    --version|-v) echo "tailscale-send v$VERSION"; exit 0 ;;
    --help|-h)
      echo "Usage: tailscale-send.sh [file...]"
      echo "Send files to a Tailscale device."
      echo "If no files given, a file picker opens (KDE only)."
      exit 0 ;;
  esac

  ensure_tailscale

  local files=("$@")
  if ((${#files[@]} == 0)); then
    if has kdialog; then
      mapfile -t files < <(
        kdialog --getopenfilename "$PWD" "*" --multiple --separate-output 2>/dev/null || true
      )
      ((${#files[@]} == 0)) && die "no files selected"
    else
      die "no files provided (drop files onto the script, or pass them as arguments)"
    fi
  fi

  mapfile -t devices < <(list_devices)
  local device
  device=$(pick_device "${devices[@]}") || exit 1
  send_files "$device" "${files[@]}"
}

main "$@"
