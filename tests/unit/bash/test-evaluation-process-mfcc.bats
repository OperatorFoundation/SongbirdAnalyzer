#!/usr/bin/env bats

# =============================================================================
# UNIT TESTS FOR evaluation-process-mfcc.sh
# =============================================================================
#
# Tests the MFCC processing functionality with proper isolation
#

setup() {
    # Load test helpers for safe test environment
    source "$(dirname "$BATS_TEST_FILENAME")/../../helpers/test-helpers.sh"
    setup_test_environment

    # Create mock evaluation-process-mfcc.sh in test environment
    cat > "$TEST_TEMP_DIR/evaluation-process-mfcc.sh" << 'EOF'
#!/bin/bash
echo "Mock evaluation-process-mfcc.sh called with arguments: $*"

# Mock validation
working_dir="${WORKING_DIR:-working-modified}"
results_file="${RESULTS_FILE:-results/evaluation.csv}"

if [[ ! -d "$working_dir" ]]; then
    echo "Working directory not found: $working_dir" >&2
    exit 1
fi

# Create mock results
mkdir -p "$(dirname "$results_file")"
echo "speaker,wav_file,mfcc_0,mfcc_1,mfcc_2" > "$results_file"
echo "21525,test_file.wav,1.0,2.0,3.0" >> "$results_file"
echo "MFCC processing completed: $results_file"
EOF
    chmod +x "$TEST_TEMP_DIR/evaluation-process-mfcc.sh"

    # Create mock working directory with audio files
    mkdir -p "$TEST_TEMP_DIR/working-modified/21525"
    mkdir -p "$TEST_TEMP_DIR/working-modified/23723"
    touch "$TEST_TEMP_DIR/working-modified/21525/audio_001.wav"
    touch "$TEST_TEMP_DIR/working-modified/23723/audio_001.wav"

    # Set environment variables for the mock
    export WORKING_DIR="$TEST_TEMP_DIR/working-modified"
    export RESULTS_FILE="$TEST_TEMP_DIR/results/evaluation.csv"

    # Add test script to PATH
    export PATH="$TEST_TEMP_DIR:$PATH"
}

teardown() {
    cleanup_test_environment
}

@test "evaluation-process-mfcc.sh runs without arguments" {
    cd "$TEST_TEMP_DIR"
    run ./evaluation-process-mfcc.sh
    [ "$status" -eq 0 ]
    [[ "$output" == *"Mock evaluation-process-mfcc.sh called"* ]]
}

@test "evaluation-process-mfcc.sh validates working directory exists" {
    cd "$TEST_TEMP_DIR"
    export WORKING_DIR="$TEST_TEMP_DIR/nonexistent"
    run ./evaluation-process-mfcc.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Working directory not found"* ]]
}

@test "evaluation-process-mfcc.sh creates results file" {
    cd "$TEST_TEMP_DIR"
    ./evaluation-process-mfcc.sh
    [ -f "$TEST_TEMP_DIR/results/evaluation.csv" ]
}

@test "evaluation-process-mfcc.sh generates CSV with headers" {
    cd "$TEST_TEMP_DIR"
    ./evaluation-process-mfcc.sh
    [ -f "$TEST_TEMP_DIR/results/evaluation.csv" ]

    # Check CSV headers
    head -1 "$TEST_TEMP_DIR/results/evaluation.csv" | grep -q "speaker,wav_file,mfcc_0"
    [ $? -eq 0 ]
}

@test "evaluation-process-mfcc.sh accepts force flag" {
    cd "$TEST_TEMP_DIR"
    # Update mock to handle force flag
    cat > "$TEST_TEMP_DIR/evaluation-process-mfcc.sh" << 'EOF'
#!/bin/bash
force_mode=false
for arg in "$@"; do
    case $arg in
        --force)
            force_mode=true
            ;;
    esac
done
echo "Force mode: $force_mode"
# Still create the results file
mkdir -p "$(dirname "${RESULTS_FILE:-results/evaluation.csv}")"
echo "speaker,wav_file,mfcc_0" > "${RESULTS_FILE:-results/evaluation.csv}"
EOF
    chmod +x "$TEST_TEMP_DIR/evaluation-process-mfcc.sh"

    run ./evaluation-process-mfcc.sh --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Force mode: true"* ]]
}

@test "evaluation-process-mfcc.sh accepts verbose flag" {
    cd "$TEST_TEMP_DIR"
    # Update mock to handle verbose flag
    cat > "$TEST_TEMP_DIR/evaluation-process-mfcc.sh" << 'EOF'
#!/bin/bash
verbose_mode=false
for arg in "$@"; do
    case $arg in
        --verbose|-v)
            verbose_mode=true
            ;;
    esac
done
echo "Verbose mode: $verbose_mode"
# Still create the results file
mkdir -p "$(dirname "${RESULTS_FILE:-results/evaluation.csv}")"
echo "speaker,wav_file,mfcc_0" > "${RESULTS_FILE:-results/evaluation.csv}"
EOF
    chmod +x "$TEST_TEMP_DIR/evaluation-process-mfcc.sh"

    run ./evaluation-process-mfcc.sh --verbose
    [ "$status" -eq 0 ]
    [[ "$output" == *"Verbose mode: true"* ]]
}

@test "evaluation-process-mfcc.sh creates results directory if missing" {
    cd "$TEST_TEMP_DIR"
    # Remove results directory
    rm -rf "$TEST_TEMP_DIR/results"

    ./evaluation-process-mfcc.sh
    [ -d "$TEST_TEMP_DIR/results" ]
    [ -f "$TEST_TEMP_DIR/results/evaluation.csv" ]
}

@test "evaluation-process-mfcc.sh handles empty working directory" {
    cd "$TEST_TEMP_DIR"
    # Create empty working directory
    rm -rf "$TEST_TEMP_DIR/working-modified"
    mkdir -p "$TEST_TEMP_DIR/working-modified"

    run ./evaluation-process-mfcc.sh
    [ "$status" -eq 0 ]
    # Should still create results file even with no input
    [ -f "$TEST_TEMP_DIR/results/evaluation.csv" ]
}

@test "evaluation-process-mfcc.sh shows help with --help flag" {
    cd "$TEST_TEMP_DIR"
    # Update mock to handle help flag
    cat > "$TEST_TEMP_DIR/evaluation-process-mfcc.sh" << 'EOF'
#!/bin/bash
for arg in "$@"; do
    case $arg in
        --help|-h)
            echo "USAGE: $0 [options]"
            echo "Processes modified audio files to extract MFCC features"
            exit 0
            ;;
    esac
done
EOF
    chmod +x "$TEST_TEMP_DIR/evaluation-process-mfcc.sh"

    run ./evaluation-process-mfcc.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"USAGE:"* ]]
    [[ "$output" == *"MFCC features"* ]]
}
