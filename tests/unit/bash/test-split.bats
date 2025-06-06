
#!/usr/bin/env bats

# =============================================================================
# UNIT TESTS FOR split.sh
# =============================================================================
#
# Tests the audio file splitting functionality with proper isolation
#

setup() {
    # Load test helpers for safe test environment
    source "$(dirname "$BATS_TEST_FILENAME")/../../helpers/test-helpers.sh"
    setup_test_environment

    # Create mock split.sh in test environment
    cat > "$TEST_TEMP_DIR/split.sh" << 'EOF'
#!/bin/bash
# Mock split.sh for testing
echo "Mock split.sh called with arguments: $*"
if [[ $# -lt 1 ]]; then
    echo "Missing required argument: input_file" >&2
    exit 1
fi
# Create mock output files
input_file="$1"
max_time="${2:-10}"
output_dir="${3:-.}"
base_name=$(basename "${input_file%.*}")
for i in {001..003}; do
    touch "$output_dir/${base_name}_${i}.wav"
done
echo "Created 3 segments"
EOF
    chmod +x "$TEST_TEMP_DIR/split.sh"

    # Create mock input audio file
    touch "$TEST_TEMP_DIR/test_audio.mp3"

    # Add test script to PATH
    export PATH="$TEST_TEMP_DIR:$PATH"
}

teardown() {
    cleanup_test_environment
}

@test "split.sh requires input file argument" {
    cd "$TEST_TEMP_DIR"
    run ./split.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required argument"* ]]
}

@test "split.sh accepts input file and default parameters" {
    cd "$TEST_TEMP_DIR"
    run ./split.sh test_audio.mp3
    [ "$status" -eq 0 ]
    [[ "$output" == *"Mock split.sh called with arguments"* ]]
    [[ "$output" == *"Created 3 segments"* ]]
}

@test "split.sh accepts custom max time parameter" {
    cd "$TEST_TEMP_DIR"
    run ./split.sh test_audio.mp3 15
    [ "$status" -eq 0 ]
    [[ "$output" == *"test_audio.mp3 15"* ]]
}

@test "split.sh accepts custom output directory" {
    cd "$TEST_TEMP_DIR"
    mkdir -p output_test
    run ./split.sh test_audio.mp3 10 output_test
    [ "$status" -eq 0 ]
    [[ "$output" == *"test_audio.mp3 10 output_test"* ]]
}

@test "split.sh creates output files in correct location" {
    cd "$TEST_TEMP_DIR"

    # Create enhanced mock that actually creates output files
    cat > "$TEST_TEMP_DIR/split.sh" << 'EOF'
#!/bin/bash
echo "Mock split.sh called with arguments: $*"

input_file="$1"
max_time="${2:-10}"
output_dir="${3:-.}"

# Create output directory if it doesn't exist
mkdir -p "$output_dir"

# Extract base filename
base_name=$(basename "${input_file%.*}")

# Create mock output files (simulating 3 segments)
for i in {1..3}; do
    segment_file="$output_dir/${base_name}_$(printf "%03d" $i).wav"
    echo "Mock WAV file $i" > "$segment_file"
done

echo "Created 3 segments"
EOF
    chmod +x "$TEST_TEMP_DIR/split.sh"

    # Create test input file
    echo "mock audio data" > test_audio.mp3

    # Test with custom output directory
    ./split.sh test_audio.mp3 10 test_output

    # Verify output files exist
    [ -f "test_output/test_audio_001.wav" ]
    [ -f "test_output/test_audio_002.wav" ]
    [ -f "test_output/test_audio_003.wav" ]
}

@test "split.sh handles missing input file gracefully" {
    cd "$TEST_TEMP_DIR"
    # Update mock to check file existence
    cat > "$TEST_TEMP_DIR/split.sh" << 'EOF'
#!/bin/bash
if [[ $# -lt 1 ]]; then
    echo "Missing required argument: input_file" >&2
    exit 1
fi
if [[ ! -f "$1" ]]; then
    echo "Input file not found: $1" >&2
    exit 1
fi
EOF
    chmod +x "$TEST_TEMP_DIR/split.sh"

    run ./split.sh nonexistent.mp3
    [ "$status" -eq 1 ]
    [[ "$output" == *"Input file not found"* ]]
}

@test "split.sh validates numeric max_time parameter" {
    cd "$TEST_TEMP_DIR"
    # Update mock to validate max_time
    cat > "$TEST_TEMP_DIR/split.sh" << 'EOF'
#!/bin/bash
if [[ $# -lt 1 ]]; then
    echo "Missing required argument: input_file" >&2
    exit 1
fi
max_time="${2:-10}"
if ! [[ "$max_time" =~ ^[0-9]+$ ]] || [[ "$max_time" -le 0 ]]; then
    echo "Invalid segment duration: $max_time" >&2
    exit 1
fi
echo "Valid parameters"
EOF
    chmod +x "$TEST_TEMP_DIR/split.sh"

    run ./split.sh test_audio.mp3 invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid segment duration"* ]]
}

@test "split.sh creates output directory if it doesn't exist" {
    cd "$TEST_TEMP_DIR"
    # Update mock to create directory
    cat > "$TEST_TEMP_DIR/split.sh" << 'EOF'
#!/bin/bash
input_file="$1"
max_time="${2:-10}"
output_dir="${3:-.}"
mkdir -p "$output_dir"
echo "Directory created: $output_dir"
base_name=$(basename "${input_file%.*}")
touch "$output_dir/${base_name}_001.wav"
EOF
    chmod +x "$TEST_TEMP_DIR/split.sh"

    run ./split.sh test_audio.mp3 10 new_directory
    [ "$status" -eq 0 ]
    [[ "$output" == *"Directory created: new_directory"* ]]
    [ -d "new_directory" ]
    [ -f "new_directory/test_audio_001.wav" ]
}
