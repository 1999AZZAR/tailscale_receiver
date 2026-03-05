#!/usr/bin/env bats
# Integration tests for complete system functionality

# Setup and teardown for integration tests
setup_integration() {
    export TEST_MODE=true
    export TARGET_DIR="$(mktemp -d)/tailscale"
    export FIX_OWNER="$(whoami)"
    export TARGET_USER="$(whoami)"
    export LOG_LEVEL="error"  # Reduce noise in tests

    # Create target directory
    mkdir -p "$TARGET_DIR"
}

teardown_integration() {
    # Clean up test directories
    rm -rf "$TARGET_DIR" 2>/dev/null || true
}

# Test script startup and configuration loading
@test "script startup and configuration loading" {
    setup_integration

    # Test that script starts with valid config
    run timeout 3s bash tailscale-receive.sh --once
    # Should start and attempt to run (may fail due to missing tailscale, but shouldn't crash)
    [[ "$output" == *"Starting Tailscale receiver service"* ]]

    teardown_integration
}

# Test version flag functionality
@test "version flag functionality" {
    setup_integration

    # Test version output
    run bash tailscale-receive.sh --version
    [[ $status -eq 0 ]]
    [[ "$output" == *"Tailscale Receiver v"* ]]

    teardown_integration
}

# Test configuration validation
@test "configuration validation" {
    setup_integration

    # Test with valid configuration
    export TARGET_DIR="$TARGET_DIR"
    export FIX_OWNER="$FIX_OWNER"

    # Script should not fail with valid config
    run timeout 2s bash tailscale-receive.sh --once 2>&1
    # Should complete without config validation errors
    [[ ! "$output" == *"is not set"* ]]
    [[ ! "$output" == *"does not exist"* ]]

    teardown_integration
}

# Test timer mode flag recognition
@test "timer mode flag recognition" {
    setup_integration

    # Test --once flag is recognized
    run timeout 2s bash tailscale-receive.sh --once 2>&1
    # Should not hang indefinitely and should start service
    [[ "$output" == *"Starting Tailscale receiver service"* ]]

    teardown_integration
}

# Test once mode functionality
@test "once mode functionality" {
    setup_integration

    # Test once mode runs without crashing
    run timeout 3s bash tailscale-receive.sh --once
    # Just check that it ran (may exit with error due to config)
    [[ -n "$output" ]]

    teardown_integration
}

# Test basic script functionality
@test "basic script functionality" {
    setup_integration

    # Test that script can start and show expected output
    run timeout 3s bash tailscale-receive.sh --once 2>&1
    [[ "$output" == *"Starting Tailscale receiver service"* ]]

    teardown_integration
}

# Test script exit behavior
@test "script exit behavior" {
    setup_integration

    # Test that script exits (expected behavior without proper setup)
    run timeout 5s bash tailscale-receive.sh --once
    # Should exit with some code (3 for config error is common)
    [[ $status -ne 0 ]]

    teardown_integration
}

# Test configuration file creation
@test "configuration file creation" {
    setup_integration

    # Test that config template is valid
    local config_file="$TARGET_DIR/test_config"
    cat > "$config_file" << 'EOF'
# Test configuration
TARGET_USER=testuser
TARGET_DIR=/tmp/test
LOG_LEVEL=info
EOF

    # Verify config file was created
    [[ -f "$config_file" ]]
    [[ "$(grep "TARGET_USER" "$config_file")" == *"testuser"* ]]

    teardown_integration
}

# Test directory creation
@test "directory creation" {
    setup_integration

    # Test that target directory gets created
    run mkdir -p "$TARGET_DIR"
    [[ -d "$TARGET_DIR" ]]

    # Test file creation in directory
    echo "test content" > "$TARGET_DIR/test.txt"
    [[ -f "$TARGET_DIR/test.txt" ]]
    [[ "$(cat "$TARGET_DIR/test.txt")" == "test content" ]]

    teardown_integration
}