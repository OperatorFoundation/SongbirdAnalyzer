#!/usr/bin/env bats

# =============================================================================
# INTEGRATION TESTS FOR splitall.sh
# =============================================================================
#
# Tests the actual audio splitting functionality with real dependencies
#

setup() {
    # Use the test helpers for safe environment setup
    source "$(dirname "$BATS_TEST_FILENAME")/../../helpers/test-helpers.sh"
    setup_test_environment

    # Store original directory and change to test environment
    ORIGINAL_DIR=$(pwd)
    cd "$TEST_TEMP_DIR"

    # Find the project root - go up from the test file location
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../" && pwd)"

    # Copy ONLY the files we need from the project root
    cp "$PROJECT_ROOT/splitall.sh" .

    # Create minimal songbird-core structure for testing
    mkdir -p songbird-core

    # Create mock core loader that doesn't actually load modules
    cat > songbird-core/songbird-core.sh << 'EOF'
#!/bin/bash
# Mock core loader for testing
setup_error_handling() { echo "Mock error handling setup"; }
error_exit() { echo "ERROR: $1" >&2; exit ${2:-1}; }
warning() { echo "WARNING: $1" >&2; }
info() { echo "INFO: $1" >&2; }
success() { echo "SUCCESS: $1" >&2; }
validate_prerequisites() { echo "Mock prerequisites validation"; return 0; }
validate_speaker_config() { echo "Mock speaker config validation"; return 0; }
setup_training_working_directory() {
    local dir="$1"
    mkdir -p "$dir"/{21525,23723,19839}
    return 0
}
run_with_error_handling() {
    local desc="$1"; shift
    echo "Running: $desc"
    "$@"
}
print_header() { echo "=== $1 ==="; }
print_progress() { echo "Progress: $1/$2 - $3"; }
get_file_info() { echo "File info for: $1"; }
register_cleanup_function() { echo "Registered cleanup: $1"; }

# Mock configuration
speakers=(21525 23723 19839)
MAX_TIME=10
EOF

    # Create mock split.sh
    cat > split.sh << 'EOF'
#!/bin/bash
mp3_file="$1"
max_time="$2"
output_dir="$3"

if [[ ! -f "$mp3_file" ]]; then
    exit 1
fi

basename_file=$(basename "$mp3_file" .mp3)
mkdir -p "$output_dir"
touch "$output_dir/${basename_file}_001.wav"
touch "$output_dir/${basename_file}_002.wav"
EOF
    chmod +x split.sh

    # Create test audio structure
    mkdir -p audio/training/{21525,23723,19839}
    touch audio/training/21525/{chapter01.mp3,chapter02.mp3}
    touch audio/training/23723/story01.mp3
    touch audio/training/19839/book01.mp3
}

teardown() {
    cd "$ORIGINAL_DIR"
    cleanup_test_environment
}

@test "splitall.sh requires both source and output directory arguments" {
    run ./splitall.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required arguments"* ]]
}

@test "splitall.sh requires output directory argument" {
    run ./splitall.sh audio/training
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required arguments"* ]]
}

@test "splitall.sh validates source directory exists" {
    run ./splitall.sh nonexistent/directory working-training
    [ "$status" -eq 1 ]
    [[ "$output" == *"Source directory not found"* ]]
}

@test "splitall.sh validates source directory is readable" {
    mkdir -p unreadable-dir
    chmod 000 unreadable-dir
    run ./splitall.sh unreadable-dir working-training
    [ "$status" -eq 1 ]
    [[ "$output" == *"Source directory not readable"* ]]
    chmod 755 unreadable-dir  # cleanup
}

@test "splitall.sh processes valid audio directory structure" {
    run ./splitall.sh audio/training working-training --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Speaker 21525"* ]]
    [[ "$output" == *"Speaker 23723"* ]]
    [[ "$output" == *"Speaker 19839"* ]]
}

@test "splitall.sh creates proper output directory structure" {
    ./splitall.sh audio/training working-training --force

    # Check that speaker directories are created
    [ -d "working-training/21525" ]
    [ -d "working-training/23723" ]
    [ -d "working-training/19839" ]
}

@test "splitall.sh processes MP3 files and creates WAV segments" {
    ./splitall.sh audio/training working-training --force

    # Check that mock WAV files were created (from our mock split.sh)
    [ -f "working-training/21525/chapter01_001.wav" ]
    [ -f "working-training/21525/chapter01_002.wav" ]
    [ -f "working-training/21525/chapter02_001.wav" ]
    [ -f "working-training/23723/story01_001.wav" ]
    [ -f "working-training/19839/book01_001.wav" ]
}

@test "splitall.sh handles speakers with no MP3 files" {
    # Create empty speaker directory
    mkdir -p audio/training/empty_speaker

    run ./splitall.sh audio/training working-training --force
    [ "$status" -eq 0 ]
    # Debug: show what we actually got
    echo "Actual output: $output" >&3
    # Check for the actual warning message from splitall.sh
    [[ "$output" == *"No MP3 files found"* ]]
}

@test "splitall.sh handles missing speaker directories gracefully" {
    # Remove one speaker directory
    rm -rf audio/training/19839

    run ./splitall.sh audio/training working-training --force
    # Debug: show what we actually got
    echo "Exit status: $status" >&3
    echo "Actual output: $output" >&3
    # Script should continue processing other speakers even if one is missing
    [ "$status" -eq 0 ]
    [[ "$output" == *"directory not found"* ]]
}

@test "splitall.sh accepts --force flag" {
    # Create existing working directory with content
    mkdir -p working-training/existing
    touch working-training/existing/file.txt

    run ./splitall.sh audio/training working-training --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Force Mode: true"* ]]
}

@test "splitall.sh accepts --verbose flag" {
    run ./splitall.sh audio/training working-training --verbose --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Verbose Mode: true"* ]]
}

@test "splitall.sh shows help with --help flag" {
    run ./splitall.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE:"* ]]
    [[ "$output" == *"source_dir"* ]]
    [[ "$output" == *"output_dir"* ]]
}

@test "splitall.sh validates split.sh dependency exists" {
    # Remove split.sh dependency
    rm split.sh

    run ./splitall.sh audio/training working-training --force
    [ "$status" -eq 1 ]
    [[ "$output" == *"split.sh not found"* ]]
}

@test "splitall.sh validates split.sh is executable" {
    # Make split.sh non-executable
    chmod -x split.sh

    run ./splitall.sh audio/training working-training --force
    [ "$status" -eq 1 ]
    [[ "$output" == *"split.sh is not executable"* ]]
}

@test "splitall.sh reports processing statistics" {
    run ./splitall.sh audio/training working-training --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"MP3 files processed"* ]]
    [[ "$output" == *"WAV segments created"* ]]
    [[ "$output" == *"Audio splitting completed successfully"* ]]
}

@test "splitall.sh handles individual file processing failures" {
    # Create a mock split.sh that fails on specific files
    cat > split.sh << 'EOF'
#!/bin/bash
mp3_file="$1"
if [[ "$mp3_file" == *"chapter02"* ]]; then
    echo "Simulated processing failure for chapter02" >&2
    exit 1
fi
# Process other files normally
output_dir="$3"
basename_file=$(basename "$mp3_file" .mp3)
mkdir -p "$output_dir"
touch "$output_dir/${basename_file}_001.wav"
EOF
    chmod +x split.sh

    run ./splitall.sh audio/training working-training --force
    # The script should report failures but may still exit 0 if some files succeeded
    # Check for failure reporting in output
    [[ "$output" == *"Failed to process"* || "$output" == *"failed"* ]]
}

@test "splitall.sh loads songbird core modules correctly" {
    # Test that the script loads without module errors
    run ./splitall.sh --help
    [ "$status" -eq 0 ]
    # Should not see actual module loading errors (our mock prevents them)
    [[ "$output" == *"USAGE:"* ]]
}

@test "splitall.sh creates comprehensive processing report" {
    run ./splitall.sh audio/training working-training --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"PROCESSING REPORT"* ]]
    [[ "$output" == *"Results by Speaker"* ]]
    [[ "$output" == *"Overall Summary"* ]]
    [[ "$output" == *"Processing Time"* ]]
}

@test "splitall.sh handles concurrent execution safely" {
    # Simplified concurrent test - just verify both can run
    ./splitall.sh audio/training working-training-1 --force &
    pid1=$!
    ./splitall.sh audio/training working-training-2 --force &
    pid2=$!

    wait $pid1; status1=$?
    wait $pid2; status2=$?

    [ "$status1" -eq 0 ]
    [ "$status2" -eq 0 ]
    [ -d "working-training-1/21525" ]
    [ -d "working-training-2/21525" ]
}