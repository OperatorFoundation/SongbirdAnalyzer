#!/bin/bash

# =============================================================================
# TEST HELPERS AND UTILITIES
# =============================================================================
#
# Common utilities and helper functions for Songbird test suite.
# Provides mocking, fixture management, and assertion helpers.
#
# =============================================================================

# Test configuration
readonly TEST_FIXTURES_DIR="$(dirname "${BASH_SOURCE[0]}")/../fixtures"
readonly TEST_TEMP_DIR="/tmp/songbird-tests-$$"
readonly MOCK_AUDIO_DURATION=5

# Setup test environment
setup_test_environment()
{
    # Create temporary test directory
    mkdir -p "$TEST_TEMP_DIR"

    # Create basic directory structure
    mkdir -p "$TEST_TEMP_DIR"/{audio,results,working-test,models}

    # Set environment variables for testing
    export SONGBIRD_TEST_MODE=true
    export WORKING_DIR="$TEST_TEMP_DIR/working-test"
    export RESULTS_FILE="$TEST_TEMP_DIR/results/test.csv"
    export MODEL_FILE="$TEST_TEMP_DIR/models/test.pkl"
}

# Cleanup test environment
cleanup_test_environment()
{
    if [[ -d "$TEST_TEMP_DIR" ]]
    then
        rm -rf "$TEST_TEMP_DIR"
    fi

    unset SONGBIRD_TEST_MODE
    unset WORKING_DIR
    unset RESULTS_FILE
    unset MODEL_FILE
}

# Create mock audio file
create_mock_audio_file()
{
    local output_path="$1"
    local duration="${2:-$MOCK_AUDIO_DURATION}"

    # Generate silence using sox if available, otherwise create empty file
    if command -v sox &>/dev/null
    then
        sox -n -r 44100 -b 16 "$output_path" trim 0.0 "$duration"
    else
        # Create a minimal WAV header for testing
        {
            # WAV header (44 bytes)
            printf "RIFF"
            printf "\x24\x08\x00\x00"  # File size - 8
            printf "WAVE"
            printf "fmt "
            printf "\x10\x00\x00\x00"  # Format chunk size
            printf "\x01\x00"          # Audio format (PCM)
            printf "\x01\x00"          # Number of channels
            printf "\x44\xAC\x00\x00"  # Sample rate (44100)
            printf "\x88\x58\x01\x00"  # Byte rate
            printf "\x02\x00"          # Block align
            printf "\x10\x00"          # Bits per sample
            printf "data"
            printf "\x00\x08\x00\x00"  # Data chunk size
            # Add some audio data (2048 bytes of silence)
            dd if=/dev/zero bs=2048 count=1 2>/dev/null
        } > "$output_path"
    fi
}

# Create mock CSV file with MFCC data
create_mock_csv_file()
{
    local output_path="$1"
    local num_samples="${2:-10}"

    {
        # Header
        echo "speaker,wav_file,mfcc_0,mfcc_1,mfcc_2,mfcc_3,mfcc_4"

        # Sample data
        for i in $(seq 1 "$num_samples")
        do
            local speaker=$((21525 + (i % 3)))  # Rotate through 3 speakers
            local wav_file="sample_${i}.wav"
            local mfcc_values="$(shuf -i 1-100 -n 5 | tr '\n' ',' | sed 's/,$//')"
            echo "$speaker,$wav_file,$mfcc_values"
        done
    } > "$output_path"
}

# Create mock model file
create_mock_model_file()
{
    local output_path="$1"

    # Create a minimal pickle file (for testing purposes)
    python3 -c "
import pickle
import sys

# Create a simple mock model object
class MockModel:
    def __init__(self):
        self.feature_count = 5
        self.classes_ = ['21525', '23723', '19839']

    def predict(self, X):
        import random
        return [random.choice(self.classes_) for _ in range(len(X))]

    def predict_proba(self, X):
        import random
        return [[random.random() for _ in self.classes_] for _ in range(len(X))]

model = MockModel()
with open('$output_path', 'wb') as f:
    pickle.dump(model, f)
"
}

# Assert file exists
assert_file_exists()
{
    local file_path="$1"
    local message="${2:-File should exist: $file_path}"

    if [[ ! -f "$file_path" ]]
    then
        echo "ASSERTION FAILED: $message" >&2
        return 1
    fi
}

# Assert directory exists
assert_directory_exists()
{
    local dir_path="$1"
    local message="${2:-Directory should exist: $dir_path}"

    if [[ ! -d "$dir_path" ]]
    then
        echo "ASSERTION FAILED: $message" >&2
        return 1
    fi
}

# Assert command succeeds
assert_success()
{
    local command="$1"
    local message="${2:-Command should succeed: $command}"

    if ! eval "$command" &>/dev/null
    then
        echo "ASSERTION FAILED: $message" >&2
        return 1
    fi
}

# Assert command fails
assert_failure()
{
    local command="$1"
    local message="${2:-Command should fail: $command}"

    if eval "$command" &>/dev/null
    then
        echo "ASSERTION FAILED: $message" >&2
        return 1
    fi
}

# Assert string contains substring
assert_contains()
{
    local string="$1"
    local substring="$2"
    local message="${3:-String should contain: $substring}"

    if [[ "$string" != *"$substring"* ]]
    then
        echo "ASSERTION FAILED: $message" >&2
        echo "  String: $string" >&2
        return 1
    fi
}

# Mock external command
mock_command()
{
    local command_name="$1"
    local mock_script="$2"

    # Create mock executable in temporary directory
    local mock_path="$TEST_TEMP_DIR/mock_$command_name"
    echo "$mock_script" > "$mock_path"
    chmod +x "$mock_path"

    # Add to PATH
    export PATH="$TEST_TEMP_DIR:$PATH"
}

# Verify mock was called
verify_mock_called()
{
    local command_name="$1"
    local expected_calls="${2:-1}"

    local call_log="$TEST_TEMP_DIR/mock_${command_name}_calls"
    if [[ ! -f "$call_log" ]]
    then
        echo "Mock $command_name was never called" >&2
        return 1
    fi

    local actual_calls
    actual_calls=$(wc -l < "$call_log")

    if [[ "$actual_calls" -ne "$expected_calls" ]]
    then
        echo "Mock $command_name called $actual_calls times, expected $expected_calls" >&2
        return 1
    fi
}