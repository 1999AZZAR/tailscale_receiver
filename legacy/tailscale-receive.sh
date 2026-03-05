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
# These values are configured via environment file (/etc/default/tailscale-receive)
# Can be overridden via environment variables for testing

# Target directory for received files (required)
TARGET_DIR="${TARGET_DIR:-/home/${TARGET_USER:-user}/Downloads/tailscale}"

# Target user for file ownership correction (required)
FIX_OWNER="${FIX_OWNER:-${TARGET_USER:-user}}"

# Logging level (optional, default: info)
LOG_LEVEL="${LOG_LEVEL:-info}"

# Archive management (optional)
ARCHIVE_ENABLED="${ARCHIVE_ENABLED:-true}"
ARCHIVE_DAYS="${ARCHIVE_DAYS:-14}"
ARCHIVE_DIR_NAME="${ARCHIVE_DIR_NAME:-archive}"

# Polling and health check configuration (optional)
POLL_INTERVAL="${POLL_INTERVAL:-15}"           # Base polling interval in seconds
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-30}"  # Health check frequency in cycles
NETWORK_TIMEOUT="${NETWORK_TIMEOUT:-1}"        # Network connectivity timeout in seconds
TAILSCALE_TIMEOUT="${TAILSCALE_TIMEOUT:-5}"    # Tailscale status timeout in seconds
MAX_BACKOFF="${MAX_BACKOFF:-300}"              # Maximum backoff time in seconds (5 minutes)
NOTIFICATION_THROTTLE="${NOTIFICATION_THROTTLE:-5}"  # Minimum seconds between notifications

# File integrity verification (optional)
INTEGRITY_CHECK_ENABLED="${INTEGRITY_CHECK_ENABLED:-false}"  # Enable/disable integrity checking
INTEGRITY_CHECK_ALGORITHM="${INTEGRITY_CHECK_ALGORITHM:-sha256}"  # Hash algorithm (sha256, sha512, md5)
INTEGRITY_CHECK_TIMEOUT="${INTEGRITY_CHECK_TIMEOUT:-30}"     # Timeout for integrity checks in seconds
INTEGRITY_CHECK_MAX_SIZE="${INTEGRITY_CHECK_MAX_SIZE:-1073741824}"  # Max file size for integrity checks (1GB)

# Health endpoint (optional)
HEALTH_ENDPOINT_ENABLED="${HEALTH_ENDPOINT_ENABLED:-false}"  # Enable/disable health endpoint
HEALTH_ENDPOINT_PORT="${HEALTH_ENDPOINT_PORT:-8080}"         # Port for health endpoint
HEALTH_ENDPOINT_PATH="${HEALTH_ENDPOINT_PATH:-/health}"      # Path for health endpoint

# File type filtering (optional)
FILE_FILTER_ENABLED="${FILE_FILTER_ENABLED:-false}"              # Enable/disable file type filtering
FILE_FILTER_MODE="${FILE_FILTER_MODE:-allow}"                    # allow/deny mode
FILE_FILTER_MIME_TYPES="${FILE_FILTER_MIME_TYPES:-}"             # Comma-separated MIME types
FILE_FILTER_EXTENSIONS="${FILE_FILTER_EXTENSIONS:-}"             # Comma-separated file extensions
FILE_FILTER_MAX_SIZE="${FILE_FILTER_MAX_SIZE:-104857600}"       # Max file size for filtering (100MB)

# Virus scanning (optional)
VIRUS_SCAN_ENABLED="${VIRUS_SCAN_ENABLED:-false}"               # Enable/disable virus scanning
VIRUS_SCAN_ENGINE="${VIRUS_SCAN_ENGINE:-clamav}"                # Scanning engine (clamav)
VIRUS_SCAN_TIMEOUT="${VIRUS_SCAN_TIMEOUT:-60}"                  # Scan timeout in seconds
VIRUS_SCAN_QUARANTINE="${VIRUS_SCAN_QUARANTINE:-false}"         # Move infected files to quarantine

# Rate limiting and abuse protection (optional)
RATE_LIMIT_ENABLED="${RATE_LIMIT_ENABLED:-false}"               # Enable/disable rate limiting
RATE_LIMIT_FILES_PER_MINUTE="${RATE_LIMIT_FILES_PER_MINUTE:-60}" # Max files per minute
RATE_LIMIT_FILES_PER_HOUR="${RATE_LIMIT_FILES_PER_HOUR:-500}"   # Max files per hour
RATE_LIMIT_SIZE_PER_MINUTE="${RATE_LIMIT_SIZE_PER_MINUTE:-104857600}" # Max size per minute (100MB)
RATE_LIMIT_SIZE_PER_HOUR="${RATE_LIMIT_SIZE_PER_HOUR:-1073741824}"    # Max size per hour (1GB)
RATE_LIMIT_BLOCK_DURATION="${RATE_LIMIT_BLOCK_DURATION:-300}"   # Block duration in seconds (5 min)
RATE_LIMIT_RESET_INTERVAL="${RATE_LIMIT_RESET_INTERVAL:-60}"    # Statistics reset interval (seconds)

# Configuration versioning
CONFIG_VERSION="${CONFIG_VERSION:-2.3.0}"                    # Current configuration version

# --- Binary Resolution ---
# Resolve full paths to executables for security and reliability
resolve_binaries() {
  log_debug "Resolving binary paths..."

  # Required binaries
  TS_BIN=$(command -v tailscale 2>/dev/null) || {
    log_error "tailscale binary not found in PATH. Please install Tailscale."
    exit 8
  }

  PING_BIN=$(command -v ping 2>/dev/null) || {
    log_error "ping binary not found in PATH. This is required for network checks."
    exit 9
  }

  CHOWN_BIN=$(command -v chown 2>/dev/null) || {
    log_error "chown binary not found in PATH. This is required for ownership correction."
    exit 10
  }

  RUNUSER_BIN=$(command -v runuser 2>/dev/null) || {
    log_error "runuser binary not found in PATH. This is required for user notifications."
    exit 11
  }

  # Optional binaries (warnings only)
  NOTIFY_SEND_BIN=$(command -v notify-send 2>/dev/null) || {
    log_warn "notify-send not found. Desktop notifications will be disabled."
    NOTIFY_SEND_BIN=""
  }

  # Integrity check binaries (optional, only resolved if integrity checking enabled)
  SHA256SUM_BIN=""
  SHA512SUM_BIN=""
  MD5SUM_BIN=""

  if [[ "$INTEGRITY_CHECK_ENABLED" == "true" ]]; then
    SHA256SUM_BIN=$(command -v sha256sum 2>/dev/null) || {
      log_warn "sha256sum not found. SHA256 integrity checks will be disabled."
    }

    SHA512SUM_BIN=$(command -v sha512sum 2>/dev/null) || {
      log_warn "sha512sum not found. SHA512 integrity checks will be disabled."
    }

    MD5SUM_BIN=$(command -v md5sum 2>/dev/null) || {
      log_warn "md5sum not found. MD5 integrity checks will be disabled."
    }
  fi

  # Health endpoint binaries (optional, only resolved if health endpoint enabled)
  NC_BIN=""
  SOCAT_BIN=""

  if [[ "$HEALTH_ENDPOINT_ENABLED" == "true" ]]; then
    NC_BIN=$(command -v nc 2>/dev/null) || {
      log_warn "nc (netcat) not found. Trying socat for health endpoint..."
    }

    if [[ -z "$NC_BIN" ]]; then
      SOCAT_BIN=$(command -v socat 2>/dev/null) || {
        log_warn "socat not found either. Health endpoint will not be available."
      }
    fi
  fi

  # File filtering binaries (optional, only resolved if filtering enabled)
  FILE_BIN=""
  CLAMSCAN_BIN=""

  if [[ "$FILE_FILTER_ENABLED" == "true" ]]; then
    FILE_BIN=$(command -v file 2>/dev/null) || {
      log_warn "file command not found. MIME type detection will be unavailable."
    }
  fi

  if [[ "$VIRUS_SCAN_ENABLED" == "true" ]]; then
    CLAMSCAN_BIN=$(command -v clamscan 2>/dev/null) || {
      log_warn "clamscan not found. Install clamav for virus scanning: sudo apt install clamav"
    }
  fi

  log_debug "Binary resolution complete:"
  log_debug "  tailscale: $TS_BIN"
  log_debug "  ping: $PING_BIN"
  log_debug "  chown: $CHOWN_BIN"
  log_debug "  runuser: $RUNUSER_BIN"
  log_debug "  notify-send: ${NOTIFY_SEND_BIN:-not found}"
  if [[ "$INTEGRITY_CHECK_ENABLED" == "true" ]]; then
    log_debug "  sha256sum: ${SHA256SUM_BIN:-not found}"
    log_debug "  sha512sum: ${SHA512SUM_BIN:-not found}"
    log_debug "  md5sum: ${MD5SUM_BIN:-not found}"
  fi
}

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

# Function to check file integrity
check_file_integrity() {
  local file_path="$1"
  local expected_hash="${2:-}"

  # Skip if integrity checking is disabled
  if [[ "$INTEGRITY_CHECK_ENABLED" != "true" ]]; then
    return 0
  fi

  # Skip if no hash tool available for selected algorithm
  local hash_bin=""
  case "$INTEGRITY_CHECK_ALGORITHM" in
    sha256)
      hash_bin="$SHA256SUM_BIN"
      ;;
    sha512)
      hash_bin="$SHA512SUM_BIN"
      ;;
    md5)
      hash_bin="$MD5SUM_BIN"
      ;;
    *)
      log_warn "Unsupported integrity check algorithm: $INTEGRITY_CHECK_ALGORITHM"
      return 1
      ;;
  esac

  if [[ -z "$hash_bin" ]]; then
    log_warn "Hash tool for $INTEGRITY_CHECK_ALGORITHM not available, skipping integrity check"
    return 1
  fi

  # Check file size limit
  local file_size
  file_size=$(stat -c%s "$file_path" 2>/dev/null || echo "0")
  if [[ $file_size -gt $INTEGRITY_CHECK_MAX_SIZE ]]; then
    log_debug "File too large for integrity check (${file_size} > ${INTEGRITY_CHECK_MAX_SIZE}), skipping"
    return 0
  fi

  log_debug "Checking integrity of $file_path using $INTEGRITY_CHECK_ALGORITHM"

  # Calculate hash with timeout
  local calculated_hash=""
  if ! calculated_hash=$(timeout "$INTEGRITY_CHECK_TIMEOUT" "$hash_bin" "$file_path" 2>/dev/null | cut -d' ' -f1); then
    log_warn "Integrity check timed out for $file_path"
    return 1
  fi

  if [[ -z "$calculated_hash" ]]; then
    log_warn "Failed to calculate hash for $file_path"
    return 1
  fi

  # If expected hash provided, compare
  if [[ -n "$expected_hash" ]]; then
    if [[ "$calculated_hash" != "$expected_hash" ]]; then
      log_error "Integrity check FAILED for $file_path"
      log_error "  Expected: $expected_hash"
      log_error "  Calculated: $calculated_hash"
      return 1
    else
      log_debug "Integrity check PASSED for $file_path"
      return 0
    fi
  else
    # No expected hash, just log the calculated hash
    log_info "Calculated ${INTEGRITY_CHECK_ALGORITHM} for $file_path: $calculated_hash"
    return 0
  fi
}

# Function to get health status
get_health_status() {
  local current_time
  current_time=$(date +%s)

  local uptime=$((current_time - service_start_time))
  local last_success_age=$((current_time - last_successful_cycle))

  # Determine overall health
  local status="healthy"
  local issues=()

  # Check if we've had recent successful cycles
  if [[ $last_success_age -gt 300 ]]; then  # 5 minutes
    status="unhealthy"
    issues+=("No successful cycles in last 5 minutes")
  fi

  # Check for high failure rate
  if [[ $total_files_processed -gt 0 ]]; then
    local failure_rate=$((total_files_failed * 100 / total_files_processed))
    if [[ $failure_rate -gt 50 ]]; then
      status="degraded"
      issues+=("High failure rate: ${failure_rate}%")
    fi
  fi

  # Check consecutive failures
  if [[ $consecutive_failures -gt 10 ]]; then
    status="unhealthy"
    issues+=("High consecutive failures: $consecutive_failures")
  fi

  # Build JSON response
  local json="{"
  json+="\"status\":\"$status\","
  json+="\"timestamp\":$current_time,"
  json+="\"uptime\":$uptime,"
  json+="\"last_successful_cycle\":$last_successful_cycle,"
  json+="\"cycles_completed\":$cycle_count,"
  json+="\"files_processed\":$total_files_processed,"
  json+="\"files_failed\":$total_files_failed,"
  json+="\"consecutive_failures\":$consecutive_failures"

  if [[ ${#issues[@]} -gt 0 ]]; then
    json+=",\"issues\":["
    for i in "${!issues[@]}"; do
      if [[ $i -gt 0 ]]; then
        json+=","
      fi
      json+="\"${issues[$i]}\""
    done
    json+="]"
  fi

  json+="}"

  echo "$json"
}

# Function to start health endpoint server
start_health_endpoint() {
  if [[ "$HEALTH_ENDPOINT_ENABLED" != "true" ]]; then
    return
  fi

  log_info "Starting health endpoint server on port $HEALTH_ENDPOINT_PORT"

  # Start health endpoint in background
  (
    while true; do
      # Use netcat if available, otherwise try socat, otherwise skip
      if command -v nc >/dev/null 2>&1; then
        # Handle one request at a time
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n$(get_health_status)" | \
          nc -l -p "$HEALTH_ENDPOINT_PORT" -q 1 2>/dev/null || true
      elif command -v socat >/dev/null 2>&1; then
        # Alternative using socat
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n$(get_health_status)" | \
          socat -u - TCP-LISTEN:"$HEALTH_ENDPOINT_PORT",reuseaddr,fork 2>/dev/null || true
      else
        log_warn "Neither nc nor socat available for health endpoint. Install netcat or socat for health monitoring."
        break
      fi

      # Small delay to prevent busy looping
      sleep 0.1
    done
  ) &
}

# Function to update health metrics
update_health_metrics() {
  local success="$1"

  if [[ "$success" == "true" ]]; then
    last_successful_cycle=$(date +%s)
    consecutive_failures=0
  else
    consecutive_failures=$((consecutive_failures + 1))
  fi
}

# Function to migrate configuration from older versions
migrate_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    log_debug "Configuration file does not exist, no migration needed"
    return 0
  fi

  # Read current config version
  local current_version=""
  if grep -q "^CONFIG_VERSION=" "$config_file" 2>/dev/null; then
    current_version=$(grep "^CONFIG_VERSION=" "$config_file" | cut -d'=' -f2 | tr -d '"')
  fi

  # If no version found, assume it's from before versioning (pre-2.3.0)
  if [[ -z "$current_version" ]]; then
    log_info "Detected pre-2.3.0 configuration, migrating..."
    migrate_from_pre_2_3_0 "$config_file"
    return $?
  fi

  # Compare versions and migrate if needed
  if [[ "$current_version" != "$CONFIG_VERSION" ]]; then
    log_info "Migrating configuration from $current_version to $CONFIG_VERSION"

    # Add migration logic for specific version jumps here
    case "$current_version" in
      "2.2.0"|"2.2.1")
        migrate_from_2_2_x "$config_file"
        ;;
      "2.3.0")
        log_debug "Configuration already at latest version"
        ;;
      *)
        log_warn "Unknown configuration version $current_version, skipping migration"
        ;;
    esac
  else
    log_debug "Configuration is already at latest version ($CONFIG_VERSION)"
  fi
}

# Function to migrate from pre-2.3.0 configurations
migrate_from_pre_2_3_0() {
  local config_file="$1"

  log_info "Migrating configuration from pre-2.3.0 format"

  # Create backup
  cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)" || {
    log_error "Failed to create backup of configuration file"
    return 1
  }

  # Add new configuration options with defaults
  {
    echo ""
    echo "# Configuration version (automatically managed)"
    echo "CONFIG_VERSION=\"$CONFIG_VERSION\""
    echo ""
    echo "# Added in v2.3.0 - Health endpoint for monitoring"
    echo "# HEALTH_ENDPOINT_ENABLED=false       # Enable/disable health endpoint"
    echo "# HEALTH_ENDPOINT_PORT=8080           # Port for health endpoint server"
    echo "# HEALTH_ENDPOINT_PATH=/health        # Path for health checks"
    echo ""
    echo "# Added in v2.3.0 - File integrity verification"
    echo "# INTEGRITY_CHECK_ENABLED=false       # Enable/disable integrity checking"
    echo "# INTEGRITY_CHECK_ALGORITHM=sha256    # Hash algorithm (sha256, sha512, md5)"
    echo "# INTEGRITY_CHECK_TIMEOUT=30          # Timeout for integrity checks (seconds)"
    echo "# INTEGRITY_CHECK_MAX_SIZE=1073741824 # Max file size for checks (1GB)"
  } >> "$config_file" || {
    log_error "Failed to add new configuration options"
    return 1
  }

  log_info "Configuration migration completed successfully"
  return 0
}

# Function to migrate from 2.2.x configurations
migrate_from_2_2_x() {
  local config_file="$1"

  log_info "Migrating configuration from 2.2.x to 2.3.0"

  # For now, just update the version since 2.2.x to 2.3.0 is backward compatible
  # In the future, specific migration logic would go here

  # Update version
  sed -i "s/^CONFIG_VERSION=.*/CONFIG_VERSION=\"$CONFIG_VERSION\"/" "$config_file" 2>/dev/null || {
    log_warn "Failed to update configuration version"
  }

  log_info "Configuration migration completed successfully"
  return 0
}

# Function to check file type against filter rules
check_file_type() {
  local file_path="$1"

  # Skip if filtering is disabled
  if [[ "$FILE_FILTER_ENABLED" != "true" ]]; then
    return 0
  fi

  # Skip if no filter rules defined
  if [[ -z "$FILE_FILTER_MIME_TYPES" ]] && [[ -z "$FILE_FILTER_EXTENSIONS" ]]; then
    return 0
  fi

  # Check file size limit
  local file_size
  file_size=$(stat -c%s "$file_path" 2>/dev/null || echo "0")
  if [[ $file_size -gt $FILE_FILTER_MAX_SIZE ]]; then
    log_debug "File too large for type filtering (${file_size} > ${FILE_FILTER_MAX_SIZE}), skipping"
    return 0
  fi

  local mime_type=""
  local file_extension=""

  # Get MIME type using file command
  if [[ -n "$FILE_BIN" ]]; then
    mime_type=$("$FILE_BIN" -b --mime-type "$file_path" 2>/dev/null | tr -d '\n')
  fi

  # Get file extension
  file_extension=$(basename "$file_path" | rev | cut -d'.' -f1 | rev)
  if [[ "$file_extension" == "$(basename "$file_path")" ]]; then
    file_extension=""  # No extension
  fi

  log_debug "File type check: MIME='$mime_type', EXT='$file_extension'"

  # Check MIME type filter
  local mime_allowed=false
  if [[ -n "$FILE_FILTER_MIME_TYPES" ]]; then
    IFS=',' read -ra MIME_ARRAY <<< "$FILE_FILTER_MIME_TYPES"
    for allowed_mime in "${MIME_ARRAY[@]}"; do
      allowed_mime=$(echo "$allowed_mime" | xargs)  # Trim whitespace
      if [[ "$mime_type" == "$allowed_mime" ]]; then
        mime_allowed=true
        break
      fi
    done
  else
    mime_allowed=true  # No MIME filter defined
  fi

  # Check extension filter
  local ext_allowed=false
  if [[ -n "$FILE_FILTER_EXTENSIONS" ]]; then
    IFS=',' read -ra EXT_ARRAY <<< "$FILE_FILTER_EXTENSIONS"
    for allowed_ext in "${EXT_ARRAY[@]}"; do
      allowed_ext=$(echo "$allowed_ext" | xargs)  # Trim whitespace
      if [[ "${file_extension,,}" == "${allowed_ext,,}" ]]; then
        ext_allowed=true
        break
      fi
    done
  else
    ext_allowed=true  # No extension filter defined
  fi

  # Apply filtering logic
  case "$FILE_FILTER_MODE" in
    allow)
      if [[ "$mime_allowed" == "true" ]] && [[ "$ext_allowed" == "true" ]]; then
        log_debug "File type ALLOWED by filter rules"
        return 0
      else
        log_error "File type BLOCKED by allow filter: MIME='$mime_type' EXT='$file_extension'"
        return 1
      fi
      ;;
    deny)
      if [[ "$mime_allowed" == "false" ]] && [[ "$ext_allowed" == "false" ]]; then
        log_debug "File type ALLOWED (not in deny list)"
        return 0
      else
        log_error "File type BLOCKED by deny filter: MIME='$mime_type' EXT='$file_extension'"
        return 1
      fi
      ;;
    *)
      log_warn "Invalid FILE_FILTER_MODE: $FILE_FILTER_MODE, allowing file"
      return 0
      ;;
  esac
}

# Function to scan file for viruses
scan_for_viruses() {
  local file_path="$1"

  # Skip if virus scanning is disabled
  if [[ "$VIRUS_SCAN_ENABLED" != "true" ]]; then
    return 0
  fi

  # Skip if clamscan not available
  if [[ -z "$CLAMSCAN_BIN" ]]; then
    log_warn "Virus scanning enabled but clamscan not found"
    return 1
  fi

  # Check file size limit for scanning
  local file_size
  file_size=$(stat -c%s "$file_path" 2>/dev/null || echo "0")
  if [[ $file_size -gt $FILE_FILTER_MAX_SIZE ]]; then
    log_debug "File too large for virus scanning (${file_size} > ${FILE_FILTER_MAX_SIZE}), skipping"
    return 0
  fi

  log_debug "Scanning file for viruses: $file_path"

  # Run virus scan with timeout
  local scan_result=""
  if ! scan_result=$(timeout "$VIRUS_SCAN_TIMEOUT" "$CLAMSCAN_BIN" --no-summary --stdout "$file_path" 2>/dev/null); then
    log_warn "Virus scan timed out for $file_path"
    return 1
  fi

  # Check scan results
  if echo "$scan_result" | grep -q "Infected files: 0"; then
    log_debug "Virus scan PASSED for $file_path"
    return 0
  else
    log_error "Virus scan FAILED for $file_path"
    log_error "Scan results: $scan_result"

    # Quarantine infected file if enabled
    if [[ "$VIRUS_SCAN_QUARANTINE" == "true" ]]; then
      local quarantine_dir="${TARGET_DIR}/quarantine"
      mkdir -p "$quarantine_dir" 2>/dev/null || true

      local quarantine_file="$quarantine_dir/$(basename "$file_path").infected.$(date +%s)"
      if mv "$file_path" "$quarantine_file" 2>/dev/null; then
        log_info "Infected file quarantined: $quarantine_file"
      fi
    fi

    return 1
  fi
}

# Function to check if rate limits are exceeded
check_rate_limits() {
  local file_size="$1"

  # Skip if rate limiting is disabled
  if [[ "$RATE_LIMIT_ENABLED" != "true" ]]; then
    return 0
  fi

  local current_time
  current_time=$(date +%s)

  # Check if currently blocked
  if [[ $current_time -lt $rate_limit_blocked_until ]]; then
    local remaining=$((rate_limit_blocked_until - current_time))
    log_error "Rate limit exceeded - blocked for ${remaining}s"
    return 1
  fi

  # Reset counters if needed
  reset_rate_limit_counters "$current_time"

  # Check file count limits
  if [[ $rate_limit_minute_files -ge $RATE_LIMIT_FILES_PER_MINUTE ]]; then
    log_warn "Rate limit exceeded: $rate_limit_minute_files files in last minute (limit: $RATE_LIMIT_FILES_PER_MINUTE)"
    activate_rate_limit_block "$current_time"
    return 1
  fi

  if [[ $rate_limit_hour_files -ge $RATE_LIMIT_FILES_PER_HOUR ]]; then
    log_warn "Rate limit exceeded: $rate_limit_hour_files files in last hour (limit: $RATE_LIMIT_FILES_PER_HOUR)"
    activate_rate_limit_block "$current_time"
    return 1
  fi

  # Check size limits
  local new_minute_size=$((rate_limit_minute_size + file_size))
  local new_hour_size=$((rate_limit_hour_size + file_size))

  if [[ $new_minute_size -gt $RATE_LIMIT_SIZE_PER_MINUTE ]]; then
    log_warn "Rate limit exceeded: ${new_minute_size}B in last minute (limit: ${RATE_LIMIT_SIZE_PER_MINUTE}B)"
    activate_rate_limit_block "$current_time"
    return 1
  fi

  if [[ $new_hour_size -gt $RATE_LIMIT_SIZE_PER_HOUR ]]; then
    log_warn "Rate limit exceeded: ${new_hour_size}B in last hour (limit: ${RATE_LIMIT_SIZE_PER_HOUR}B)"
    activate_rate_limit_block "$current_time"
    return 1
  fi

  return 0
}

# Function to update rate limit counters
update_rate_limits() {
  local file_size="$1"

  # Skip if rate limiting is disabled
  if [[ "$RATE_LIMIT_ENABLED" != "true" ]]; then
    return 0
  fi

  local current_time
  current_time=$(date +%s)

  # Reset counters if needed
  reset_rate_limit_counters "$current_time"

  # Update counters
  rate_limit_minute_files=$((rate_limit_minute_files + 1))
  rate_limit_hour_files=$((rate_limit_hour_files + 1))
  rate_limit_minute_size=$((rate_limit_minute_size + file_size))
  rate_limit_hour_size=$((rate_limit_hour_size + file_size))

  log_debug "Rate limit counters updated: ${rate_limit_minute_files} files/min, ${rate_limit_hour_files} files/hour"
}

# Function to reset rate limit counters based on time intervals
reset_rate_limit_counters() {
  local current_time="$1"

  # Reset minute counters every minute
  if [[ $((current_time - rate_limit_minute_start)) -ge 60 ]]; then
    rate_limit_minute_start=$current_time
    rate_limit_minute_files=0
    rate_limit_minute_size=0
    log_debug "Reset minute rate limit counters"
  fi

  # Reset hour counters every hour
  if [[ $((current_time - rate_limit_hour_start)) -ge 3600 ]]; then
    rate_limit_hour_start=$current_time
    rate_limit_hour_files=0
    rate_limit_hour_size=0
    log_debug "Reset hour rate limit counters"
  fi

  rate_limit_last_reset=$current_time
}

# Function to activate rate limit blocking
activate_rate_limit_block() {
  local current_time="$1"

  rate_limit_blocked_until=$((current_time + RATE_LIMIT_BLOCK_DURATION))
  log_warn "Rate limiting activated - blocking transfers for ${RATE_LIMIT_BLOCK_DURATION}s"
}

# --- Script Starts ---

# Handle version flag
if [[ "${1:-}" == "--version" ]] || [[ "${1:-}" == "-v" ]]; then
  echo "Tailscale Receiver v${VERSION}"
  exit 0
fi

# Handle once flag for timer-based execution
ONCE_MODE=false
if [[ "${1:-}" == "--once" ]]; then
  ONCE_MODE=true
  log_info "Running in once mode (single cycle for systemd timer)"
fi

log_info "Starting Tailscale receiver service"

# Validate configuration before proceeding
validate_config

# Resolve binary paths for security and reliability
resolve_binaries

# Migrate configuration if needed
ENV_FILE="${ENV_FILE:-/etc/default/tailscale-receive}"
migrate_config "$ENV_FILE"

# Ensure single instance (prevent duplicate loops)
check_single_instance

# Initialize health monitoring
service_start_time=$(date +%s)
last_successful_cycle=$service_start_time

# Initialize rate limiting
if [[ "$RATE_LIMIT_ENABLED" == "true" ]]; then
  rate_limit_minute_start=$service_start_time
  rate_limit_hour_start=$service_start_time
  rate_limit_last_reset=$service_start_time
  log_info "Rate limiting enabled with limits: ${RATE_LIMIT_FILES_PER_MINUTE} files/min, ${RATE_LIMIT_FILES_PER_HOUR} files/hour"
fi

# Start health endpoint server if enabled
start_health_endpoint

mkdir -p "$TARGET_DIR"

# Single-instance guard
PID_FILE="${PID_FILE:-/var/run/tailscale-receive.pid}"
LOCK_FILE="${LOCK_FILE:-/var/run/tailscale-receive.lock}"

# Function to check for existing instances
check_single_instance() {
  log_debug "Checking for existing instances..."

  # Check if PID file exists and process is still running
  if [[ -f "$PID_FILE" ]]; then
    existing_pid=$(cat "$PID_FILE" 2>/dev/null)
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
      log_error "Another instance is already running (PID: $existing_pid)"
      log_error "If this is incorrect, remove $PID_FILE and try again"
      exit 12
    else
      log_warn "Stale PID file found, removing: $PID_FILE"
      rm -f "$PID_FILE" 2>/dev/null || true
    fi
  fi

  # Try to acquire lock file
  if ! (set -o noclobber; echo $$ > "$LOCK_FILE") 2>/dev/null; then
    existing_pid=$(cat "$LOCK_FILE" 2>/dev/null)
    log_error "Failed to acquire lock file: $LOCK_FILE"
    log_error "Another instance may be running (PID: ${existing_pid:-unknown})"
    exit 13
  fi

  # Write our PID to the PID file
  echo $$ > "$PID_FILE" || {
    log_error "Failed to write PID file: $PID_FILE"
    rm -f "$LOCK_FILE" 2>/dev/null || true
    exit 14
  }

  log_debug "Single-instance guard established (PID: $$, Lock: $LOCK_FILE)"
}

# Function to cleanup locks on exit
cleanup_locks() {
  log_debug "Cleaning up instance locks..."
  rm -f "$PID_FILE" "$LOCK_FILE" 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup_locks EXIT

# Exponential backoff state
declare -i sleep_interval="$POLL_INTERVAL"
declare -i max_sleep="$MAX_BACKOFF"
declare -i consecutive_failures=0
declare -i cycle_count=0
declare -i health_check_count=0
declare -i start_time
start_time=$(date +%s)

# Notification throttling state
declare -i last_notification_time=0
declare -i notification_throttle_seconds="$NOTIFICATION_THROTTLE"

# Health monitoring state
declare -i last_successful_cycle=0
declare -i consecutive_failures=0
declare -i total_files_processed=0
declare -i total_files_failed=0
declare -i service_start_time=0

# Rate limiting state
declare -i rate_limit_blocked_until=0
declare -i rate_limit_minute_start=0
declare -i rate_limit_hour_start=0
declare -i rate_limit_minute_files=0
declare -i rate_limit_hour_files=0
declare -i rate_limit_minute_size=0
declare -i rate_limit_hour_size=0
declare -i rate_limit_last_reset=0

log_info "Service initialized - Monitoring directory: $TARGET_DIR, Target user: $FIX_OWNER"

while true; do
  cycle_count=$((cycle_count + 1))
  cycle_start=$(date +%s)

  # 1. Health checks (configurable frequency)
  health_check_count=$((health_check_count + 1))
  perform_full_health_check=$((health_check_count % HEALTH_CHECK_INTERVAL == 1))

  if [[ "$perform_full_health_check" == "1" ]]; then
    log_debug "Performing full health check (cycle $cycle_count, check #$health_check_count)"
  fi

  # Always check network connectivity
  if ! "$PING_BIN" -c 1 -W "$NETWORK_TIMEOUT" 8.8.8.8 &>/dev/null; then
    log_warn "Network connectivity check failed (cycle $cycle_count). Backing off for ${sleep_interval}s (failure #$((consecutive_failures + 1)))"
    consecutive_failures=$((consecutive_failures + 1))
    update_health_metrics "false"
    sleep_interval=$((sleep_interval * 2))
    [ "$sleep_interval" -gt "$max_sleep" ] && sleep_interval=$max_sleep
    sleep "$sleep_interval"
    continue
  fi

  # Check Tailscale status (full check or basic ping)
  if [[ "$perform_full_health_check" == "1" ]]; then
    if ! timeout "$TAILSCALE_TIMEOUT" "$TS_BIN" status &>/dev/null; then
      log_error "Tailscale not authenticated (cycle $cycle_count). Please run 'tailscale up' manually or set TS_AUTHKEY environment variable. Backing off for ${sleep_interval}s"
      consecutive_failures=$((consecutive_failures + 1))
      update_health_metrics "false"
      sleep_interval=$((sleep_interval * 2))
      [ "$sleep_interval" -gt "$max_sleep" ] && sleep_interval=$max_sleep
      sleep "$sleep_interval"
      continue
    fi
  else
    # Basic Tailscale connectivity check (lighter weight)
    if ! timeout "$TAILSCALE_TIMEOUT" "$TS_BIN" ping --timeout=2s --self &>/dev/null 2>&1; then
      log_debug "Tailscale basic connectivity check failed (cycle $cycle_count), will retry with full check soon"
      # Don't increment consecutive_failures for basic checks, just log
    fi
  fi

  # 2. Get a snapshot of files BEFORE receiving (null-safe)
  mapfile -d '' files_before < <(find "$TARGET_DIR" -maxdepth 1 -mindepth 1 -printf '%P\0' 2>/dev/null | sort -z)

  # 3. Attempt to get new files
  log_debug "Attempting to retrieve Taildrop files (cycle $cycle_count)"
  if ! "$TS_BIN" file get "$TARGET_DIR" 2>/dev/null; then
    log_warn "tailscale file get failed (cycle $cycle_count). This may be normal if no files are pending. Backing off for ${sleep_interval}s"
    consecutive_failures=$((consecutive_failures + 1))
    update_health_metrics "false"
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

    log_info "New items detected: ${#new_files[@]} item(s) (cycle $cycle_count, ${cycle_duration}s)"

    processed_count=0
    failed_count=0
    total_size_bytes=0
    file_count=0
    dir_count=0
    declare -a processed_files=()
    declare -a processed_dirs=()

    # Loop through each new item (files or directories)
    for filename in "${new_files[@]}"; do
      if [[ -z "$filename" ]]; then
        continue
      fi

      file_path="$TARGET_DIR$filename"

      # Determine if it's a file or directory
      if [[ -d "$file_path" ]]; then
        item_type="directory"
        log_debug "Processing directory: $filename"

        # Use du for directory size (includes contents)
        item_size=$(du -sb "$file_path" 2>/dev/null | cut -f1 || echo "0")
        chown_cmd=("$CHOWN_BIN" -R "$FIX_OWNER:$FIX_OWNER" "$file_path")
      else
        item_type="file"
        log_debug "Processing file: $filename"

        # Use stat for file size
        item_size=$(stat -c%s "$file_path" 2>/dev/null || echo "0")
        chown_cmd=("$CHOWN_BIN" "$FIX_OWNER:$FIX_OWNER" "$file_path")
      fi

      # Fix ownership of the new item
      if ! "${chown_cmd[@]}" 2>/dev/null; then
        log_error "Failed to change ownership of $item_type '$filename' to $FIX_OWNER. Check file permissions."
        failed_count=$((failed_count + 1))
        continue
      fi

      # Format size for display
      if [[ $item_size -lt 1024 ]]; then
        size_display="${item_size}B"
      elif [[ $item_size -lt $((1024 * 1024)) ]]; then
        size_display="$((item_size / 1024))KB"
      else
        size_display="$((item_size / (1024 * 1024)))MB"
      fi

      # Check rate limits before processing
      local file_size
      file_size=$(stat -c%s "$file_path" 2>/dev/null || echo "0")
      if ! check_rate_limits "$file_size"; then
        failed_count=$((failed_count + 1))
        total_files_failed=$((total_files_failed + 1))
        log_error "File rejected due to rate limiting: $filename"
        continue
      fi

      # Update rate limit counters
      update_rate_limits "$file_size"

      # Perform integrity check if enabled and it's a file
      local integrity_passed=true
      if [[ "$INTEGRITY_CHECK_ENABLED" == "true" ]] && [[ -f "$file_path" ]]; then
        if ! check_file_integrity "$file_path"; then
          integrity_passed=false
          failed_count=$((failed_count + 1))
          total_files_failed=$((total_files_failed + 1))
          log_error "Skipping notifications for $filename due to integrity check failure"
          continue
        fi

        # Check file type against filter rules
        if ! check_file_type "$file_path"; then
          failed_count=$((failed_count + 1))
          total_files_failed=$((total_files_failed + 1))
          log_error "File rejected by type filter: $filename"
          continue
        fi

        # Scan for viruses if enabled
        if ! scan_for_viruses "$file_path"; then
          failed_count=$((failed_count + 1))
          total_files_failed=$((total_files_failed + 1))
          log_error "File rejected due to virus scan failure: $filename"
          continue
        fi
      fi

      log_info "Successfully processed $item_type: $filename (${size_display})"
      processed_count=$((processed_count + 1))
      total_files_processed=$((total_files_processed + 1))
      total_size_bytes=$((total_size_bytes + item_size))

      if [[ -d "$file_path" ]]; then
        processed_dirs+=("$filename")
        dir_count=$((dir_count + 1))
      else
        processed_files+=("$filename")
        file_count=$((file_count + 1))
      fi

    done

    # Send aggregated notification if we have processed files and throttling allows
    if [[ $processed_count -gt 0 ]] && [[ -n "$NOTIFY_SEND_BIN" ]]; then
      current_time=$(date +%s)
      time_since_last_notification=$((current_time - last_notification_time))

      if [[ $time_since_last_notification -ge $notification_throttle_seconds ]]; then
        # Format size for display
        if [[ $total_size_bytes -lt 1024 ]]; then
          size_display="${total_size_bytes}B"
        elif [[ $total_size_bytes -lt $((1024 * 1024)) ]]; then
          size_display="$((total_size_bytes / 1024))KB"
        else
          size_display="$((total_size_bytes / (1024 * 1024)))MB"
        fi

        # Create notification message
        if [[ $processed_count -eq 1 ]]; then
          if [[ $file_count -eq 1 ]]; then
            notify_title="Tailscale: File Received"
            notify_body="'${processed_files[0]}' (${size_display})"
          else
            notify_title="Tailscale: Directory Received"
            notify_body="'${processed_dirs[0]}' (${size_display})"
          fi
        else
          # Multiple items - show breakdown
          if [[ $file_count -gt 0 && $dir_count -gt 0 ]]; then
            notify_title="Tailscale: $processed_count Items Received"
            notify_body="$file_count file(s), $dir_count dir(s) - Total: ${size_display}"
          elif [[ $file_count -gt 0 ]]; then
            notify_title="Tailscale: $file_count Files Received"
            notify_body="Total: ${size_display} - Click to open folder"
          else
            notify_title="Tailscale: $dir_count Directories Received"
            notify_body="Total: ${size_display} - Click to open folder"
          fi
        fi

        # Send notification with folder open action capability
        if NOTIFY_SEND_BIN="$NOTIFY_SEND_BIN" "$RUNUSER_BIN" -l "$FIX_OWNER" -c "notify-send '$notify_title' '$notify_body' -i document-save -a Tailscale --action=open:Open" 2>/dev/null; then
          log_debug "Aggregated desktop notification sent: $processed_count files, $size_display"
          last_notification_time=$current_time
        else
          log_warn "Failed to send aggregated desktop notification. Desktop environment may not be available."
        fi
      else
        log_debug "Notification throttled (last notification ${time_since_last_notification}s ago, need ${notification_throttle_seconds}s)"
      fi
    fi

    # Format final summary with breakdown
    if [[ $file_count -gt 0 && $dir_count -gt 0 ]]; then
      summary_details="$file_count file(s), $dir_count dir(s) processed"
    elif [[ $file_count -gt 0 ]]; then
      summary_details="$file_count file(s) processed"
    else
      summary_details="$dir_count dir(s) processed"
    fi

    # Format total size
    if [[ $total_size_bytes -lt 1024 ]]; then
      total_size_display="${total_size_bytes}B"
    elif [[ $total_size_bytes -lt $((1024 * 1024)) ]]; then
      total_size_display="$((total_size_bytes / 1024))KB"
    else
      total_size_display="$((total_size_bytes / (1024 * 1024)))MB"
    fi

    log_info "Item processing complete: $processed_count successful, $failed_count failed ($summary_details, total size: ${total_size_display})"
  else
    log_debug "No new files detected (cycle $cycle_count)"
  fi

  # Reset backoff on successful cycle
  consecutive_failures=0
  update_health_metrics "true"
  sleep_interval="$POLL_INTERVAL"

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

  # Exit after one cycle if running in timer mode
  if [[ "$ONCE_MODE" == true ]]; then
    log_info "Timer mode: exiting after single cycle"
    exit 0
  fi

  sleep "$sleep_interval"
done
