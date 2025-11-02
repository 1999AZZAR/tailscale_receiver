#!/bin/bash

# Tailscale Receiver v2.2.1 - Automated file reception service
# Enable strict mode for better error handling
set -Eeuo pipefail
IFS=$'\n\t'
trap 'log_error "Script failed at line $LINENO: $BASH_COMMAND (exit code $?)"' ERR

# --- Configuration ---
# Version information
readonly VERSION="2.2.1"

# Archive management settings
ARCHIVE_ENABLED=${ARCHIVE_ENABLED:-true}
ARCHIVE_DAYS=${ARCHIVE_DAYS:-14}
ARCHIVE_DIR_NAME=${ARCHIVE_DIR_NAME:-archive}

# --- Logging Functions ---
LOG_LEVEL=${LOG_LEVEL:-info}
LOG_TIMESTAMP_FORMAT='%Y-%m-%d %H:%M:%S'

log_debug() {
  [[ "$LOG_LEVEL" == "debug" ]] || return 0
  echo "[$(date +"$LOG_TIMESTAMP_FORMAT")] [DEBUG] $*" >&2
}

log_info() {
  echo "[$(date +"$LOG_TIMESTAMP_FORMAT")] [INFO] $*" >&2
  echo "$*"
}

log_warn() {
  echo "[$(date +"$LOG_TIMESTAMP_FORMAT")] [WARN] $*" >&2
  echo "WARNING: $*"
}

log_error() {
  echo "[$(date +"$LOG_TIMESTAMP_FORMAT")] [ERROR] $*" >&2
  echo "ERROR: $*" >&2
}

# --- Configuration ---
# These values will be automatically configured by the install script
# Can be overridden via environment variables for testing
TARGET_DIR="/home/user/Downloads/tailscale/"
FIX_OWNER="user"

# --- Input Validation Functions ---
validate_config() {
  log_debug "Validating configuration..."

  # Validate target directory
  if [[ -z "$TARGET_DIR" ]]; then
    log_error "TARGET_DIR is not set. Please configure TARGET_DIR in the script or environment."
    exit 2
  fi

  # Remove trailing slash if present
  TARGET_DIR="${TARGET_DIR%/}"

  # Check if directory exists and is writable
  if [[ ! -d "$TARGET_DIR" ]]; then
    log_error "TARGET_DIR '$TARGET_DIR' does not exist. Please ensure the directory exists and is accessible."
    exit 3
  fi

  if [[ ! -w "$TARGET_DIR" ]]; then
    log_error "TARGET_DIR '$TARGET_DIR' is not writable. Check permissions: chmod 755 '$TARGET_DIR'"
    exit 4
  fi

  # Validate target user
  if [[ -z "$FIX_OWNER" ]]; then
    log_error "FIX_OWNER is not set. Please configure FIX_OWNER in the script or environment."
    exit 5
  fi

  if ! id "$FIX_OWNER" &>/dev/null; then
    log_error "User '$FIX_OWNER' does not exist. Please check that the user exists: id '$FIX_OWNER'"
    exit 6
  fi

  # Check if we're running as root (required for chown)
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root to change file ownership. Please run with sudo."
    exit 7
  fi

  log_info "Configuration validation successful - Target: $TARGET_DIR, User: $FIX_OWNER"
}

# Archive management function
manage_archives() {
  [[ "$ARCHIVE_ENABLED" != "true" ]] && return 0

  local archive_dir="$TARGET_DIR/$ARCHIVE_DIR_NAME"
  local days_threshold="$ARCHIVE_DAYS"

  # Create archive directory if it doesn't exist
  if [[ ! -d "$archive_dir" ]]; then
    mkdir -p "$archive_dir" || {
      log_error "Failed to create archive directory: $archive_dir"
      return 1
    }
    log_debug "Created archive directory: $archive_dir"
  fi

  # Find and move old files
  local moved_count=0
  local total_size=0

  # Use find to locate files older than threshold days (excluding the archive directory itself)
  while IFS= read -r -d '' file; do
    # Get file size
    local file_size
    file_size=$(stat -c%s "$file" 2>/dev/null || echo "0")

    # Move file to archive
    local filename
    filename=$(basename "$file")
    local archive_path="$archive_dir/$filename"

    if mv "$file" "$archive_path" 2>/dev/null; then
      log_debug "Archived: $filename (${file_size} bytes)"
      moved_count=$((moved_count + 1))
      total_size=$((total_size + file_size))
    else
      log_warn "Failed to archive: $filename"
    fi
  done < <(find "$TARGET_DIR" -maxdepth 1 -type f -mtime "+$days_threshold" -print0 2>/dev/null)

  # Log summary if files were archived
  if [[ $moved_count -gt 0 ]]; then
    local total_size_mb
    total_size_mb=$((total_size / 1024 / 1024))
    log_info "Archived $moved_count file(s) (${total_size_mb}MB) older than ${days_threshold} days to $ARCHIVE_DIR_NAME/"
  fi

  return 0
}

# --- Script Starts ---

# Handle version flag
if [[ "${1:-}" == "--version" ]] || [[ "${1:-}" == "-v" ]]; then
  echo "Tailscale Receiver v${VERSION}"
  exit 0
fi

log_info "Starting Tailscale receiver service"

# Validate configuration before proceeding
validate_config

mkdir -p "$TARGET_DIR"

# Exponential backoff state
declare -i sleep_interval=15
declare -i max_sleep=300  # 5 minutes max
declare -i consecutive_failures=0
declare -i cycle_count=0
declare -i start_time
start_time=$(date +%s)

log_info "Service initialized - Monitoring directory: $TARGET_DIR, Target user: $FIX_OWNER"

while true; do
  cycle_count=$((cycle_count + 1))
  cycle_start=$(date +%s)

  # 1. Basic health checks (internet, tailscale status)
  if ! ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
    log_warn "Network connectivity check failed (cycle $cycle_count). Backing off for ${sleep_interval}s (failure #$((consecutive_failures + 1)))"
    consecutive_failures=$((consecutive_failures + 1))
    sleep_interval=$((sleep_interval * 2))
    [ "$sleep_interval" -gt "$max_sleep" ] && sleep_interval=$max_sleep
    sleep "$sleep_interval"
    continue
  fi

  if ! tailscale status &>/dev/null; then
    log_error "Tailscale not authenticated (cycle $cycle_count). Please run 'tailscale up' manually or set TS_AUTHKEY environment variable. Backing off for ${sleep_interval}s"
    consecutive_failures=$((consecutive_failures + 1))
    sleep_interval=$((sleep_interval * 2))
    [ "$sleep_interval" -gt "$max_sleep" ] && sleep_interval=$max_sleep
    sleep "$sleep_interval"
    continue
  fi

  # 2. Get a snapshot of files BEFORE receiving (null-safe)
  mapfile -d '' files_before < <(find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -printf '%P\0' 2>/dev/null | sort -z)

  # 3. Attempt to get new files
  log_debug "Attempting to retrieve Taildrop files (cycle $cycle_count)"
  if ! tailscale file get "$TARGET_DIR" 2>/dev/null; then
    log_warn "tailscale file get failed (cycle $cycle_count). This may be normal if no files are pending. Backing off for ${sleep_interval}s"
    consecutive_failures=$((consecutive_failures + 1))
    sleep_interval=$((sleep_interval * 2))
    [ "$sleep_interval" -gt "$max_sleep" ] && sleep_interval=$max_sleep
    sleep "$sleep_interval"
    continue
  fi

  # 4. Get a snapshot of files AFTER receiving (null-safe)
  mapfile -d '' files_after < <(find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -printf '%P\0' 2>/dev/null | sort -z)

  # 5. Compare the snapshots to find new files (null-safe)
  mapfile -d '' new_files < <(comm -z -13 <(printf '%s\0' "${files_before[@]}") <(printf '%s\0' "${files_after[@]}") 2>/dev/null || true)

  # 6. If new files were found, process them
  if [ ${#new_files[@]} -gt 0 ]; then
    cycle_end=$(date +%s)
    cycle_duration=$((cycle_end - cycle_start))

    log_info "New files detected: ${#new_files[@]} file(s) (cycle $cycle_count, ${cycle_duration}s)"

    processed_count=0
    failed_count=0

    # Loop through each new file
    for filename in "${new_files[@]}"; do
      if [[ -z "$filename" ]]; then
        continue
      fi

      file_path="$TARGET_DIR$filename"
      log_debug "Processing file: $filename"

      # Fix ownership of the new file
      if ! chown "$FIX_OWNER:$FIX_OWNER" "$file_path" 2>/dev/null; then
        log_error "Failed to change ownership of '$filename' to $FIX_OWNER. Check file permissions."
        failed_count=$((failed_count + 1))
        continue
      fi

      # Get file size for logging
      file_size=$(stat -c%s "$file_path" 2>/dev/null || echo "unknown")

      log_info "Successfully processed: $filename (${file_size} bytes)"
      processed_count=$((processed_count + 1))

      # Send notification AS YOUR USER using notify-send
      if runuser -l "$FIX_OWNER" -c "notify-send 'Tailscale: File Received' '$filename' -i document-save -a Tailscale" 2>/dev/null; then
        log_debug "Desktop notification sent for: $filename"
      else
        log_warn "Failed to send desktop notification for '$filename'. Desktop environment may not be available."
      fi
    done

    log_info "File processing complete: $processed_count successful, $failed_count failed (total: ${#new_files[@]})"
  else
    log_debug "No new files detected (cycle $cycle_count)"
  fi

  # Reset backoff on successful cycle
  consecutive_failures=0
  sleep_interval=15

  # Periodic status logging (every 10 cycles)
  if [ $(( cycle_count % 10 )) -eq 0 ]; then
    uptime_seconds=$(( $(date +%s) - start_time ))
    uptime_hours=$(( uptime_seconds / 3600 ))
    uptime_minutes=$(( (uptime_seconds % 3600) / 60 ))
    log_info "Service status: ${uptime_hours}h ${uptime_minutes}m uptime, $cycle_count cycles completed, monitoring $TARGET_DIR"
  fi

  # Archive management (runs every cycle, logs only when archiving)
  manage_archives

  log_debug "Cycle $cycle_count completed, sleeping for ${sleep_interval}s"
  sleep "$sleep_interval"
done
