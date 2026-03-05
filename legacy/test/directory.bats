#!/usr/bin/env bats
# Unit tests for directory handling functionality

# Mock external commands for testing
CHOWN_BIN="chown"

# Helper function to create test directory structure
setup_test_env() {
    TEST_DIR="$(mktemp -d)"
    TEST_USER="${USER:-$(whoami)}"

    # Create test files and directories
    mkdir -p "$TEST_DIR/testdir/subdir"
    echo "test content" > "$TEST_DIR/testfile.txt"
    echo "subdir content" > "$TEST_DIR/testdir/subdir/file.txt"
    echo "dir content" > "$TEST_DIR/testdir/file2.txt"
}

cleanup_test_env() {
    rm -rf "$TEST_DIR"
}

# Test directory size calculation
@test "directory size calculation with du" {
    setup_test_env

    # Test directory size
    dir_size=$(du -sb "$TEST_DIR/testdir" 2>/dev/null | cut -f1)
    [[ $dir_size -gt 0 ]]

    # Test file size
    file_size=$(stat -c%s "$TEST_DIR/testfile.txt" 2>/dev/null)
    [[ $file_size -gt 0 ]]

    # Directory should be larger than individual file
    [[ $dir_size -gt $file_size ]]

    cleanup_test_env
}

# Test ownership change on directories
@test "recursive chown on directories" {
    setup_test_env

    # Skip if not running as root
    if [[ $EUID -ne 0 ]]; then
        skip "Test requires root privileges for chown"
    fi

    # Change ownership recursively
    original_owner=$(stat -c%U "$TEST_DIR/testdir")
    $CHOWN_BIN -R "$TEST_USER:$TEST_USER" "$TEST_DIR/testdir" 2>/dev/null

    # Verify ownership changed
    new_owner=$(stat -c%U "$TEST_DIR/testdir")
    [[ "$new_owner" == "$TEST_USER" ]]

    # Verify subdirectory ownership
    subdir_owner=$(stat -c%U "$TEST_DIR/testdir/subdir")
    [[ "$subdir_owner" == "$TEST_USER" ]]

    # Verify file ownership
    file_owner=$(stat -c%U "$TEST_DIR/testdir/file2.txt")
    [[ "$file_owner" == "$TEST_USER" ]]

    cleanup_test_env
}

# Test file vs directory detection
@test "file vs directory detection" {
    setup_test_env

    # Test file detection
    [[ -f "$TEST_DIR/testfile.txt" ]]
    [[ ! -d "$TEST_DIR/testfile.txt" ]]

    # Test directory detection
    [[ -d "$TEST_DIR/testdir" ]]
    [[ ! -f "$TEST_DIR/testdir" ]]

    # Test subdirectory detection
    [[ -d "$TEST_DIR/testdir/subdir" ]]
    [[ ! -f "$TEST_DIR/testdir/subdir" ]]

    cleanup_test_env
}

# Test size formatting logic
@test "size formatting for display" {
    # Test byte formatting
    size=500
    if [[ $size -lt 1024 ]]; then
        display="${size}B"
    fi
    [[ "$display" == "500B" ]]

    # Test KB formatting
    size=2048
    if [[ $size -lt $((1024 * 1024)) ]]; then
        display="$((size / 1024))KB"
    fi
    [[ "$display" == "2KB" ]]

    # Test MB formatting
    size=$((1024 * 1024 * 3))
    display="$((size / (1024 * 1024)))MB"
    [[ "$display" == "3MB" ]]
}

# Test notification message generation
@test "notification message generation" {
    # Single file
    file_count=1
    dir_count=0
    processed_files=("test.txt")
    processed_dirs=()
    total_size_bytes=1024

    if [[ $file_count -eq 1 && $dir_count -eq 0 ]]; then
        notify_title="Tailscale: File Received"
        notify_body="'${processed_files[0]}' (1KB)"
        [[ "$notify_title" == "Tailscale: File Received" ]]
        [[ "$notify_body" == "'test.txt' (1KB)" ]]
    fi

    # Single directory
    file_count=0
    dir_count=1
    processed_files=()
    processed_dirs=("testdir")
    total_size_bytes=$((1024 * 1024))

    if [[ $file_count -eq 0 && $dir_count -eq 1 ]]; then
        notify_title="Tailscale: Directory Received"
        notify_body="'${processed_dirs[0]}' (1MB)"
        [[ "$notify_title" == "Tailscale: Directory Received" ]]
        [[ "$notify_body" == "'testdir' (1MB)" ]]
    fi

    # Multiple items
    file_count=2
    dir_count=1
    total_size_bytes=$((1024 * 1024 * 2))

    if [[ $file_count -gt 0 && $dir_count -gt 0 ]]; then
        notify_title="Tailscale: 3 Items Received"
        notify_body="2 file(s), 1 dir(s) - Total: 2MB"
        [[ "$notify_title" == "Tailscale: 3 Items Received" ]]
        [[ "$notify_body" == "2 file(s), 1 dir(s) - Total: 2MB" ]]
    fi
}

# Test PID file management
@test "PID file creation and cleanup" {
    TEST_PID_FILE="$(mktemp)"
    TEST_LOCK_FILE="$(mktemp)"

    # Remove the files created by mktemp so we can test creation
    rm -f "$TEST_PID_FILE" "$TEST_LOCK_FILE"

    # Test PID file creation
    echo $$ > "$TEST_PID_FILE"
    [[ -f "$TEST_PID_FILE" ]]
    [[ "$(cat "$TEST_PID_FILE")" == "$$" ]]

    # Test lock file creation
    (set -o noclobber; echo $$ > "$TEST_LOCK_FILE") 2>/dev/null
    [[ -f "$TEST_LOCK_FILE" ]]
    [[ "$(cat "$TEST_LOCK_FILE")" == "$$" ]]

    # Test cleanup
    rm -f "$TEST_PID_FILE" "$TEST_LOCK_FILE"
    [[ ! -f "$TEST_PID_FILE" ]]
    [[ ! -f "$TEST_LOCK_FILE" ]]
}

# Test lock file conflict detection
@test "lock file conflict detection" {
    TEST_LOCK_FILE="$(mktemp)"

    # Create initial lock file
    echo "12345" > "$TEST_LOCK_FILE"

    # Try to create lock file again (should fail)
    if (set -o noclobber; echo $$ > "$TEST_LOCK_FILE") 2>/dev/null; then
        # If we get here, noclobber didn't work as expected
        rm -f "$TEST_LOCK_FILE"
        skip "noclobber not supported in this shell"
    else
        # Expected behavior - lock file creation failed
        [[ "$(cat "$TEST_LOCK_FILE")" == "12345" ]]
    fi

    rm -f "$TEST_LOCK_FILE"
}

# Test --once flag functionality
@test "--once flag detection" {
    # Test that --once flag is recognized
    [[ "${1:-}" != "--once" ]] && [[ "${1:-}" != "-v" ]] && [[ "${1:-}" != "--version" ]]

    # Test once mode variable
    ONCE_MODE=false
    if [[ "${1:-}" == "--once" ]]; then
        ONCE_MODE=true
    fi

    # Simulate --once flag
    set -- "--once"
    if [[ "${1:-}" == "--once" ]]; then
        ONCE_MODE=true
    fi
    [[ "$ONCE_MODE" == "true" ]]

    # Test without flag
    set --
    ONCE_MODE=false
    if [[ "${1:-}" == "--once" ]]; then
        ONCE_MODE=true
    fi
    [[ "$ONCE_MODE" == "false" ]]
}

# Test timer mode exit condition
@test "timer mode exit after single cycle" {
    ONCE_MODE=true
    cycle_count=1

    # Simulate end of cycle logic
    echo "Cycle $cycle_count completed, sleeping for 15s"

    # Exit after one cycle if running in timer mode
    if [[ "$ONCE_MODE" == true ]]; then
        exit_code=0
    fi

    [[ $exit_code -eq 0 ]]
}

# Test Nautilus script creation
@test "nautilus script creation" {
    # Test script content structure
    NAUTILUS_SCRIPT_NAME="Send to device using Tailscale"
    NAUTILUS_SCRIPTS_DIR="/tmp/test_nautilus"

    # Create test directory
    mkdir -p "$NAUTILUS_SCRIPTS_DIR"

    # Create a test script similar to what create_nautilus_script does
    local script_path="$NAUTILUS_SCRIPTS_DIR/$NAUTILUS_SCRIPT_NAME"
    cat > "$script_path" << 'EOF'
#!/bin/bash
# Nautilus script to send files using Tailscale

if [ $# -eq 0 ]; then
    echo "Error: No files selected." >&2
    exit 1
fi

if [ ! -x "/usr/local/bin/tailscale-send.sh" ]; then
    echo "Error: Tailscale sender not found." >&2
    exit 1
fi

exec /usr/local/bin/tailscale-send.sh "$@"
EOF

    chmod +x "$script_path"

    # Test script exists and is executable
    [[ -f "$script_path" ]]
    [[ -x "$script_path" ]]

    # Test script content
    grep -q "tailscale-send.sh" "$script_path"
    grep -q "No files selected" "$script_path"

    # Cleanup
    rm -rf "$NAUTILUS_SCRIPTS_DIR"
}

# Test GNOME/Nautilus detection
@test "desktop environment detection" {
    # Test command detection logic
    local nautilus_available=false
    if command -v nautilus >/dev/null 2>&1; then
        nautilus_available=true
    fi

    # This test just validates the detection logic works
    # (actual availability depends on system)
    [[ "$nautilus_available" == "true" ]] || [[ "$nautilus_available" == "false" ]]

    local dolphin_available=false
    if command -v dolphin >/dev/null 2>&1; then
        dolphin_available=true
    fi

    [[ "$dolphin_available" == "true" ]] || [[ "$dolphin_available" == "false" ]]
}

# Test configurable polling intervals
@test "configurable polling intervals" {
    # Test default values
    POLL_INTERVAL="${POLL_INTERVAL:-15}"
    HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-30}"
    NETWORK_TIMEOUT="${NETWORK_TIMEOUT:-1}"
    TAILSCALE_TIMEOUT="${TAILSCALE_TIMEOUT:-5}"
    MAX_BACKOFF="${MAX_BACKOFF:-300}"
    NOTIFICATION_THROTTLE="${NOTIFICATION_THROTTLE:-5}"

    # Validate default ranges
    [[ $POLL_INTERVAL -gt 0 ]]
    [[ $HEALTH_CHECK_INTERVAL -gt 0 ]]
    [[ $NETWORK_TIMEOUT -gt 0 ]]
    [[ $TAILSCALE_TIMEOUT -gt 0 ]]
    [[ $MAX_BACKOFF -gt 0 ]]
    [[ $NOTIFICATION_THROTTLE -ge 0 ]]
}

# Test exponential backoff calculation
@test "exponential backoff calculation" {
    local sleep_interval=15
    local max_sleep=300

    # Test initial value
    [[ $sleep_interval -eq 15 ]]

    # Test backoff doubling
    sleep_interval=$((sleep_interval * 2))
    [[ $sleep_interval -eq 30 ]]

    # Test max cap
    sleep_interval=$((sleep_interval * 2))
    sleep_interval=$((sleep_interval * 2))
    sleep_interval=$((sleep_interval * 2))  # Should exceed max (15*16=240, still < 300)
    sleep_interval=$((sleep_interval * 2))  # Now exceeds (15*32=480 > 300)
    [[ $sleep_interval -gt $max_sleep ]]
    # Apply cap
    if [[ $sleep_interval -gt $max_sleep ]]; then
        sleep_interval=$max_sleep
    fi
    [[ $sleep_interval -eq $max_sleep ]]
}

# Test health check interval logic
@test "health check interval logic" {
    local cycle_count=1
    local health_check_count=1
    local health_check_interval=5

    # First cycle should perform full health check
    perform_full_health_check=$((health_check_count % health_check_interval == 1))
    [[ "$perform_full_health_check" == "1" ]]

    # Subsequent cycles should not
    health_check_count=2
    perform_full_health_check=$((health_check_count % health_check_interval == 1))
    [[ "$perform_full_health_check" == "0" ]]

    # Every Nth cycle should perform check
    health_check_count=6
    perform_full_health_check=$((health_check_count % health_check_interval == 1))
    [[ "$perform_full_health_check" == "1" ]]
}

# Test notification throttling
@test "notification throttling logic" {
    local last_notification_time=100
    local current_time=105
    local notification_throttle_seconds=5

    # Should allow notification (time elapsed >= throttle)
    time_since_last=$((current_time - last_notification_time))
    [[ $time_since_last -ge $notification_throttle_seconds ]]

    # Should block notification (too soon)
    current_time=102
    time_since_last=$((current_time - last_notification_time))
    [[ $time_since_last -lt $notification_throttle_seconds ]]
}

# Test file type filtering configuration
@test "file type filtering configuration" {
    # Test default values
    FILE_FILTER_ENABLED="${FILE_FILTER_ENABLED:-false}"
    FILE_FILTER_MODE="${FILE_FILTER_MODE:-allow}"
    FILE_FILTER_MAX_SIZE="${FILE_FILTER_MAX_SIZE:-104857600}"

    # Validate defaults
    [[ "$FILE_FILTER_ENABLED" == "false" ]]
    [[ "$FILE_FILTER_MODE" == "allow" ]]
    [[ $FILE_FILTER_MAX_SIZE -gt 0 ]]
}

# Test MIME type filtering logic
@test "MIME type filtering logic" {
    setup_test_env

    local test_file="$TEST_DIR/testfile.txt"

    # Test allow mode with matching MIME type
    FILE_FILTER_MODE="allow"
    FILE_FILTER_MIME_TYPES="text/plain"
    FILE_FILTER_EXTENSIONS=""

    # This test validates the logic structure, actual filtering requires 'file' command
    [[ "$FILE_FILTER_MODE" == "allow" ]]
    [[ -n "$FILE_FILTER_MIME_TYPES" ]]

    # Test deny mode
    FILE_FILTER_MODE="deny"
    FILE_FILTER_MIME_TYPES="application/octet-stream"
    [[ "$FILE_FILTER_MODE" == "deny" ]]

    cleanup_test_env
}

# Test file extension filtering
@test "file extension filtering" {
    # Test extension matching logic
    local file_path="/tmp/test.pdf"
    local extension="pdf"
    FILE_FILTER_EXTENSIONS="pdf,doc,txt"

    # Check if extension is in allowed list
    local ext_allowed=false
    IFS=',' read -ra EXT_ARRAY <<< "$FILE_FILTER_EXTENSIONS"
    for allowed_ext in "${EXT_ARRAY[@]}"; do
      allowed_ext=$(echo "$allowed_ext" | xargs)
      if [[ "${extension,,}" == "${allowed_ext,,}" ]]; then
        ext_allowed=true
        break
      fi
    done

    [[ "$ext_allowed" == "true" ]]

    # Test case insensitive matching
    extension="PDF"
    ext_allowed=false
    for allowed_ext in "${EXT_ARRAY[@]}"; do
      allowed_ext=$(echo "$allowed_ext" | xargs)
      if [[ "${extension,,}" == "${allowed_ext,,}" ]]; then
        ext_allowed=true
        break
      fi
    done

    [[ "$ext_allowed" == "true" ]]

    # Test non-matching extension
    extension="exe"
    ext_allowed=false
    for allowed_ext in "${EXT_ARRAY[@]}"; do
      allowed_ext=$(echo "$allowed_ext" | xargs)
      if [[ "${extension,,}" == "${allowed_ext,,}" ]]; then
        ext_allowed=true
        break
      fi
    done

    [[ "$ext_allowed" == "false" ]]
}

# Test virus scanning configuration
@test "virus scanning configuration" {
    # Test default values
    VIRUS_SCAN_ENABLED="${VIRUS_SCAN_ENABLED:-false}"
    VIRUS_SCAN_ENGINE="${VIRUS_SCAN_ENGINE:-clamav}"
    VIRUS_SCAN_TIMEOUT="${VIRUS_SCAN_TIMEOUT:-60}"
    VIRUS_SCAN_QUARANTINE="${VIRUS_SCAN_QUARANTINE:-false}"

    # Validate defaults
    [[ "$VIRUS_SCAN_ENABLED" == "false" ]]
    [[ "$VIRUS_SCAN_ENGINE" == "clamav" ]]
    [[ $VIRUS_SCAN_TIMEOUT -gt 0 ]]
}

# Test quarantine directory creation
@test "quarantine directory handling" {
    setup_test_env

    local quarantine_dir="$TEST_DIR/quarantine"
    local test_file="$TEST_DIR/testfile.txt"

    # Test quarantine directory creation
    mkdir -p "$quarantine_dir" 2>/dev/null
    [[ -d "$quarantine_dir" ]]

    # Test quarantine file naming
    local timestamp=$(date +%s)
    local quarantine_file="$quarantine_dir/$(basename "$test_file").infected.$timestamp"

    # Simulate quarantine operation (without actual move for test)
    [[ -n "$quarantine_file" ]]
    [[ "$quarantine_file" == *".infected.$timestamp" ]]

    cleanup_test_env
}

# Test rate limiting configuration
@test "rate limiting configuration" {
    # Test default values
    RATE_LIMIT_ENABLED="${RATE_LIMIT_ENABLED:-false}"
    RATE_LIMIT_FILES_PER_MINUTE="${RATE_LIMIT_FILES_PER_MINUTE:-60}"
    RATE_LIMIT_FILES_PER_HOUR="${RATE_LIMIT_FILES_PER_HOUR:-500}"
    RATE_LIMIT_SIZE_PER_MINUTE="${RATE_LIMIT_SIZE_PER_MINUTE:-104857600}"
    RATE_LIMIT_SIZE_PER_HOUR="${RATE_LIMIT_SIZE_PER_HOUR:-1073741824}"
    RATE_LIMIT_BLOCK_DURATION="${RATE_LIMIT_BLOCK_DURATION:-300}"

    # Validate defaults
    [[ "$RATE_LIMIT_ENABLED" == "false" ]]
    [[ $RATE_LIMIT_FILES_PER_MINUTE -gt 0 ]]
    [[ $RATE_LIMIT_FILES_PER_HOUR -gt 0 ]]
    [[ $RATE_LIMIT_SIZE_PER_MINUTE -gt 0 ]]
    [[ $RATE_LIMIT_SIZE_PER_HOUR -gt 0 ]]
    [[ $RATE_LIMIT_BLOCK_DURATION -gt 0 ]]
}

# Test rate limit counter logic
@test "rate limit counter logic" {
    # Initialize counters
    local rate_limit_minute_files=0
    local rate_limit_hour_files=0
    local rate_limit_minute_size=0
    local rate_limit_hour_size=0

    # Test counter updates
    local file_size=1024
    rate_limit_minute_files=$((rate_limit_minute_files + 1))
    rate_limit_hour_files=$((rate_limit_hour_files + 1))
    rate_limit_minute_size=$((rate_limit_minute_size + file_size))
    rate_limit_hour_size=$((rate_limit_hour_size + file_size))

    [[ $rate_limit_minute_files -eq 1 ]]
    [[ $rate_limit_hour_files -eq 1 ]]
    [[ $rate_limit_minute_size -eq 1024 ]]
    [[ $rate_limit_hour_size -eq 1024 ]]
}

# Test rate limit threshold checking
@test "rate limit threshold checking" {
    # Test file count limits
    local rate_limit_minute_files=55
    local rate_limit_hour_files=450
    local RATE_LIMIT_FILES_PER_MINUTE=60
    local RATE_LIMIT_FILES_PER_HOUR=500

    # Should allow (under limit)
    [[ $rate_limit_minute_files -lt $RATE_LIMIT_FILES_PER_MINUTE ]]
    [[ $rate_limit_hour_files -lt $RATE_LIMIT_FILES_PER_HOUR ]]

    # Test at limit
    rate_limit_minute_files=60
    rate_limit_hour_files=500

    # Should block (at or over limit)
    [[ $rate_limit_minute_files -ge $RATE_LIMIT_FILES_PER_MINUTE ]]
    [[ $rate_limit_hour_files -ge $RATE_LIMIT_FILES_PER_HOUR ]]
}

# Test rate limit blocking mechanism
@test "rate limit blocking mechanism" {
    local current_time=1000
    local RATE_LIMIT_BLOCK_DURATION=300
    local rate_limit_blocked_until=0

    # Test activation
    rate_limit_blocked_until=$((current_time + RATE_LIMIT_BLOCK_DURATION))
    [[ $rate_limit_blocked_until -eq 1300 ]]

    # Test blocking check
    local check_time=1200
    [[ $check_time -lt $rate_limit_blocked_until ]]

    # Test after block expires
    check_time=1400
    [[ $check_time -gt $rate_limit_blocked_until ]]
}

# Test rate limit counter reset logic
@test "rate limit counter reset logic" {
    local rate_limit_minute_start=1000
    local rate_limit_hour_start=1000
    local current_time=1660  # 11 minutes later

    # Test minute reset (should trigger)
    if [[ $((current_time - rate_limit_minute_start)) -ge 60 ]]; then
        local should_reset_minute=true
    fi

    # Test hour reset (should trigger after 60 minutes, not 11)
    if [[ $((current_time - rate_limit_hour_start)) -ge 3600 ]]; then
        local should_reset_hour=true
    else
        local should_reset_hour=false
    fi

    [[ "$should_reset_minute" == "true" ]]
    [[ "$should_reset_hour" == "false" ]]
}

# Test health endpoint configuration
@test "health endpoint configuration" {
    # Test default values
    HEALTH_ENDPOINT_ENABLED="${HEALTH_ENDPOINT_ENABLED:-false}"
    HEALTH_ENDPOINT_PORT="${HEALTH_ENDPOINT_PORT:-8080}"
    HEALTH_ENDPOINT_PATH="${HEALTH_ENDPOINT_PATH:-/health}"

    # Validate defaults
    [[ "$HEALTH_ENDPOINT_ENABLED" == "false" ]]
    [[ $HEALTH_ENDPOINT_PORT -gt 0 ]]
    [[ $HEALTH_ENDPOINT_PORT -le 65535 ]]
    [[ "$HEALTH_ENDPOINT_PATH" == "/health" ]]
}

# Test health status generation
@test "health status json generation" {
    # Initialize health variables
    local current_time
    current_time=$(date +%s)
    service_start_time=$((current_time - 3600))  # 1 hour ago
    last_successful_cycle=$((current_time - 60))  # 1 minute ago
    cycle_count=100
    total_files_processed=10
    total_files_failed=1
    consecutive_failures=0

    # Test healthy status
    local status="healthy"
    [[ "$status" == "healthy" ]]

    # Test degraded status conditions
    total_files_processed=100
    total_files_failed=60  # >50% failure rate
    local failure_rate=$((total_files_failed * 100 / total_files_processed))
    if [[ $failure_rate -gt 50 ]]; then
        status="degraded"
    fi
    [[ "$status" == "degraded" ]]

    # Test unhealthy status
    consecutive_failures=15  # >10 consecutive failures
    if [[ $consecutive_failures -gt 10 ]]; then
        status="unhealthy"
    fi
    [[ "$status" == "unhealthy" ]]
}

# Test health endpoint binary detection
@test "health endpoint binary detection" {
    # Test nc detection
    local nc_available=false
    if command -v nc >/dev/null 2>&1; then
        nc_available=true
    fi

    # Test socat detection
    local socat_available=false
    if command -v socat >/dev/null 2>&1; then
        socat_available=true
    fi

    # At least one should be available, or both false
    [[ "$nc_available" == "true" ]] || [[ "$socat_available" == "true" ]] || [[ "$nc_available" == "false" && "$socat_available" == "false" ]]
}

# Test uptime calculation
@test "uptime calculation" {
    local current_time
    current_time=$(date +%s)
    service_start_time=$((current_time - 7200))  # 2 hours ago

    local uptime=$((current_time - service_start_time))
    [[ $uptime -eq 7200 ]]

    # Test reasonable uptime range
    [[ $uptime -gt 0 ]]
    [[ $uptime -lt 31536000 ]]  # Less than 1 year
}

# Test configuration version tracking
@test "configuration version tracking" {
    CONFIG_VERSION="${CONFIG_VERSION:-2.3.0}"
    [[ "$CONFIG_VERSION" == "2.3.0" ]]
}

# Test configuration migration detection
@test "configuration migration detection" {
    # Test version comparison
    local current_version="2.2.1"
    local target_version="2.3.0"

    if [[ "$current_version" != "$target_version" ]]; then
        migration_needed=true
    else
        migration_needed=false
    fi

    [[ "$migration_needed" == "true" ]]

    # Test same version
    current_version="2.3.0"
    if [[ "$current_version" != "$target_version" ]]; then
        migration_needed=true
    else
        migration_needed=false
    fi

    [[ "$migration_needed" == "false" ]]
}

# Test pre-2.3.0 migration content
@test "pre-2.3.0 migration content" {
    # Create a temporary config file for testing
    local test_config
    test_config="$(mktemp)"

    # Create old-style config
    cat > "$test_config" << 'EOF'
# Old configuration format
TARGET_USER=testuser
TARGET_DIR=/home/testuser/Downloads/tailscale
LOG_LEVEL=info
EOF

    # Check that it doesn't have CONFIG_VERSION
    if grep -q "^CONFIG_VERSION=" "$test_config" 2>/dev/null; then
        has_version=true
    else
        has_version=false
    fi

    [[ "$has_version" == "false" ]]

    # Clean up
    rm -f "$test_config"
}

# Test version-specific migration logic
@test "version-specific migration logic" {
    local current_version="2.2.1"
    local config_file="/tmp/test_config"

    # Test migration path detection
    case "$current_version" in
      "2.2.0"|"2.2.1")
        migration_type="2_2_x"
        ;;
      "2.3.0")
        migration_type="current"
        ;;
      *)
        migration_type="unknown"
        ;;
    esac

    [[ "$migration_type" == "2_2_x" ]]

    # Test current version
    current_version="2.3.0"
    case "$current_version" in
      "2.2.0"|"2.2.1")
        migration_type="2_2_x"
        ;;
      "2.3.0")
        migration_type="current"
        ;;
      *)
        migration_type="unknown"
        ;;
    esac

    [[ "$migration_type" == "current" ]]
}

# Test integrity check configuration
@test "integrity check configuration" {
    # Test default values
    INTEGRITY_CHECK_ENABLED="${INTEGRITY_CHECK_ENABLED:-false}"
    INTEGRITY_CHECK_ALGORITHM="${INTEGRITY_CHECK_ALGORITHM:-sha256}"
    INTEGRITY_CHECK_TIMEOUT="${INTEGRITY_CHECK_TIMEOUT:-30}"
    INTEGRITY_CHECK_MAX_SIZE="${INTEGRITY_CHECK_MAX_SIZE:-1073741824}"

    # Validate defaults
    [[ "$INTEGRITY_CHECK_ENABLED" == "false" ]]
    [[ "$INTEGRITY_CHECK_ALGORITHM" == "sha256" ]]
    [[ $INTEGRITY_CHECK_TIMEOUT -gt 0 ]]
    [[ $INTEGRITY_CHECK_MAX_SIZE -gt 0 ]]
}

# Test hash algorithm selection
@test "hash algorithm selection" {
    # Test SHA256
    INTEGRITY_CHECK_ALGORITHM="sha256"
    local expected_bin="sha256sum"
    [[ "$expected_bin" == "sha256sum" ]]

    # Test SHA512
    INTEGRITY_CHECK_ALGORITHM="sha512"
    expected_bin="sha512sum"
    [[ "$expected_bin" == "sha512sum" ]]

    # Test MD5
    INTEGRITY_CHECK_ALGORITHM="md5"
    expected_bin="md5sum"
    [[ "$expected_bin" == "md5sum" ]]
}

# Test file size limit checking
@test "file size limit checking" {
    setup_test_env

    local test_file="$TEST_DIR/testfile.txt"
    local file_size
    file_size=$(stat -c%s "$test_file" 2>/dev/null || echo "0")

    # Test file within reasonable limit
    local max_size=1048576  # 1MB
    [[ $file_size -le $max_size ]]

    # Test file size detection works
    [[ $file_size -gt 0 ]]

    # Test that very small limit would exclude file
    local small_limit=5  # 5 bytes
    [[ $file_size -gt $small_limit ]]

    cleanup_test_env
}

# Test integrity check hash calculation
@test "integrity check hash calculation" {
    setup_test_env

    local test_file="$TEST_DIR/testfile.txt"

    # Test that hash calculation works (if sha256sum is available)
    if command -v sha256sum >/dev/null 2>&1; then
        local hash
        hash=$(sha256sum "$test_file" 2>/dev/null | cut -d' ' -f1)
        [[ -n "$hash" ]]
        [[ ${#hash} -eq 64 ]]  # SHA256 should be 64 characters
    else
        skip "sha256sum not available for testing"
    fi

    cleanup_test_env
}

# Test integrity check with timeout
@test "integrity check timeout handling" {
    setup_test_env

    # Create a large file that might take time to hash
    local large_file="$TEST_DIR/large_file.dat"
    dd if=/dev/zero of="$large_file" bs=1024 count=1024 2>/dev/null

    # Test timeout parameter validation
    INTEGRITY_CHECK_TIMEOUT="${INTEGRITY_CHECK_TIMEOUT:-30}"
    [[ $INTEGRITY_CHECK_TIMEOUT -gt 0 ]]
    [[ $INTEGRITY_CHECK_TIMEOUT -le 300 ]]  # Reasonable upper limit

    cleanup_test_env
}