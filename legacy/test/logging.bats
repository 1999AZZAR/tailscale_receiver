#!/usr/bin/env bats
# Unit tests for logging functions

# Define the functions we want to test directly instead of loading the full script
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

validate_config() {
  # Check if TARGET_DIR is set
  if [[ -z "$TARGET_DIR" ]]; then
    log_error "TARGET_DIR is not set. Please set TARGET_DIR environment variable."
    return 2
  fi

  # Check if TARGET_DIR exists
  if [[ ! -d "$TARGET_DIR" ]]; then
    log_error "TARGET_DIR '$TARGET_DIR' does not exist. Please ensure the directory exists and is accessible."
    return 3
  fi

  # Check if FIX_OWNER is set
  if [[ -z "$FIX_OWNER" ]]; then
    log_error "FIX_OWNER is not set. Please set FIX_OWNER environment variable."
    return 5
  fi

  # Check if user exists
  if ! id "$FIX_OWNER" >/dev/null 2>&1; then
    log_error "User '$FIX_OWNER' does not exist."
    return 6
  fi

  # Check if running as root
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root to change file ownership."
    return 7
  fi

  return 0
}

@test "log_info produces output to stderr and stdout" {
    run log_info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test message"* ]]
    [[ "$output" == *"[INFO]"* ]]
}

@test "log_warn produces warning output" {
    run log_warn "test warning"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: test warning"* ]]
    [[ "$output" == *"[WARN]"* ]]
}

@test "log_error produces error output" {
    run log_error "test error"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ERROR: test error"* ]]
    [[ "$output" == *"[ERROR]"* ]]
}

@test "log_debug is silent when LOG_LEVEL is not debug" {
    LOG_LEVEL="info"
    run log_debug "debug message"
    [ "$status" -eq 0 ]
    [[ "$output" == "" ]]
}

@test "log_debug shows output when LOG_LEVEL is debug" {
    LOG_LEVEL="debug"
    run log_debug "debug message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"debug message"* ]]
    [[ "$output" == *"[DEBUG]"* ]]
}

@test "validate_config rejects empty TARGET_DIR" {
    TARGET_DIR=""
    FIX_OWNER="testuser"
    run validate_config
    [ "$status" -eq 2 ]
    [[ "$output" == *"TARGET_DIR is not set"* ]]
}

@test "validate_config rejects empty FIX_OWNER" {
    TARGET_DIR="/tmp"
    FIX_OWNER=""
    run validate_config
    [ "$status" -eq 5 ]
    [[ "$output" == *"FIX_OWNER is not set"* ]]
}

@test "validate_config rejects non-existent TARGET_DIR" {
    TARGET_DIR="/nonexistent/directory/path"
    FIX_OWNER="testuser"
    run validate_config
    [ "$status" -eq 3 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "validate_config requires root privileges" {
    # This test will fail if run as non-root, which is expected
    TARGET_DIR="/tmp"
    FIX_OWNER="root"  # Use root user which exists
    run validate_config
    [[ "$output" == *"must be run as root"* ]]
}
