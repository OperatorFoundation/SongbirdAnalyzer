
#!/bin/bash
# =============================================================================
# SHARED FUNCTIONS AND CONFIGURATION
# =============================================================================
#
# Common variables, functions, and utilities used across evaluation scripts.
#
# KEY VARIABLES:
# --------------
# MAX_TIME=10                    # Audio segment length (seconds)
# DEVICE_NAME="Teensy MIDI_Audio" # Hardware device name
# modes=("n" "p" "w" "a")        # Teensy modification modes
# mode_names=("Noise" "PitchShift" "Wave" "All")
# speakers=("21525" "23723" "19839") # LibriVox speaker IDs
#
# AUDIO FUNCTIONS:
# ----------------
# save_original_audio_sources()    # Backup current audio devices
# restore_original_audio_sources() # Restore original audio devices
# check_audio_device()            # Verify Teensy device exists
# find_teensy_device()            # Locate Teensy USB device
#
# UTILITY FUNCTIONS:
# ------------------
# setup_working_directory()       # Create directory structure
# print_header()                  # Format section headers
#
# SAFETY FEATURES:
# ----------------
# - Automatic audio device restoration
# - Error checking for hardware presence
# - Directory cleanup and creation
# - Cross-platform device detection
#
# SOURCED BY:
# -----------
# All evaluation-*.sh scripts
# Provides consistent configuration and behavior
#
# =============================================================================

# SPEAKER CONFIGURATION
# =====================
# Central configuration for all speaker-related settings
# Uses parallel arrays for backward compatibility with older Bash versions

# Primary speaker configuration
speakers=("21525" "23723" "19839")

# Parallel arrays for speaker-specific data (must maintain same order as speakers array)
speaker_urls=(
    "https://www.archive.org/download/man_who_knew_librivox/man_who_knew_librivox_64kb_mp3.zip"
    "https://www.archive.org/download/man_thursday_zach_librivox/man_thursday_zach_librivox_64kb_mp3.zip"
    "https://www.archive.org/download/emma_solo_librivox/emma_solo_librivox_64kb_mp3.zip"
)

# Speaker-specific cleanup files (use NONE for speakers with no cleanup needed)
speaker_cleanup_patterns=(
    "NONE"
    "NONE"
    "emma_01_04_austen_64kb.mp3 emma_02_11_austen_64kb.mp3"
)

# DIRECTORY CONFIGURATION
# ========================
MAX_TIME=10
SPEAKERS_DIR="audio/training"
RESULTS_FILE="results/evaluation.csv"
RESULTS_FILE_STANDARDIZED="results/evaluation_standardized.csv"
FILES_DIR="results/testing_wav"
WORKING_DIR="working-evaluation"
MODEL_FILE="songbird.pkl"
DEVICE_NAME="Teensy MIDI_Audio" # The device name as it appears on macOS
TRACKING_FILE="modified_audio_tracking_report.txt"

# MODIFICATION MODES
# ==================
modes=("n" "p" "w" "a")
mode_names=("Noise" "PitchShift" "Wave" "All")

# SPEAKER UTILITY FUNCTIONS
# ==========================

# Get all configured speaker IDs
get_speakers() { echo "${speakers[@]}" }

# Find the array index for a speaker ID
get_speaker_index()
{
  local speaker_id="$1"
  local index=0

  for configured_speaker in "${speakers[@]}"; do
    if [[ "$configured_speaker" == "$speaker_id"]]; then
      echo "$index"
      return 0
    fi
    ((index++))
  done

    echo "-1"  # Not found
    return 1
}

# Get download URL for a specific speaker
get_speaker_url()
{
    local speaker_id="$1"
    local index=$(get_speaker_index "$speaker_id")

    if [[ "$index" -ge 0 ]]; then
        echo "${speaker_urls[$index]}"
    else
        echo ""
    fi
}

# Get cleanup files for a specific speaker
get_speaker_cleanup_files() {
    local speaker_id="$1"
    local index=$(get_speaker_index "$speaker_id")

    if [[ "$index" -ge 0 ]]; then
        local cleanup_pattern="${speaker_cleanup_patterns[$index]}"
        if [[ "$cleanup_pattern" != "NONE" ]]; then
            echo "$cleanup_pattern"
        fi
    fi
}

# Validate if a speaker ID is configured
is_valid_speaker()
{
    local speaker_id="$1"
    local index=$(get_speaker_index "$speaker_id")

    return $([ "$index" -ge 0 ])
}

# Get the number of configured speakers
get_speaker_count()
{
    echo "${#speakers[@]}"
}

# Display speaker configuration (useful for debugging)
show_speaker_config()
{
    echo "Configured speakers:"
    local index=0
    for speaker_id in "${speakers[@]}"; do
        echo "  [$index] Speaker: $speaker_id"
        echo "      URL: ${speaker_urls[$index]}"
        echo "      Cleanup: ${speaker_cleanup_patterns[$index]}"
        ((index++))
    done
}

# AUDIO DEVICE FUNCTIONS
# ======================

save_original_audio_sources()
{
  if command -v SwitchAudioSource &>/dev/null; then
    ORIGINAL_INPUT=$(SwitchAudioSource -c -t input)
    ORIGINAL_OUTPUT=$(SwitchAudioSource -c -t output)
    echo "Saved original audio settings:"
    echo "  - Input: $ORIGINAL_INPUT"
    echo "  - Output: $ORIGINAL_OUTPUT"
  fi
}

restore_original_audio_sources()
{
  if command -v SwitchAudioSource &>/dev/null; then
    echo "Restoring original audio devices..."

    if [ -n "$ORIGINAL_INPUT" ]; then
      echo "  - Setting input back to : $ORIGINAL_INPUT"
      SwitchAudioSource -t "input" -s "$ORIGINAL_INPUT" 2>/dev/null
    else
      echo "  - No original input device saved, using Built-in Microphone"
      SwitchAudioSource -t "input" -s "Built-in Microphone" 2>/dev/null
    fi

    if [ -n "$ORIGINAL_OUTPUT" ]; then
      echo "  - Setting output back to: $ORIGINAL_OUTPUT"
      SwitchAudioSource -t "output" -s "$ORIGINAL_OUTPUT" 2>/dev/null
    else
      echo "  - No original output device saved, using Built-in Output"
      SwitchAudioSource -t "output" -s "Built-in Output" 2>/dev/null
    fi
  fi
}

check_audio_device()
{
  # Returns true (0) if device exists, false (1) otherwise
  SwitchAudioSource -a | grep -q "$DEVICE_NAME"
  return $?
}

find_teensy_device() {
  # List all usb devices and grep for Teensy
  local device_list=$(ioreg -p IOUSB -l -w 0 | grep -i teensy -A10 | grep "IODialinDevice" | sed -e 's/.*= "//' -e 's/".*//')

  # if no device is found using ioreg, fall back to looking in /dev
  if [ -z "$device_list" ]; then
    # Try to find a likely Teensy usb modem device
    device_list=$(ls /dev/cu.usbmodem* 2>/dev/null)
  fi

  # Return the first device found or empty
  echo "$device_list" | head -n1
}


# HARDWARE VALIDATION CONFIGURATION
# ==================================
# Timeout settings for hardware validation tests
SERIAL_WRITE_TIMEOUT_SECONDS=2
FIRMWARE_DEV_MODE_CHECK_TIMEOUT_SECONDS=5
HARDWARE_VALIDATION_RETRY_COUNT=3
HARDWARE_VALIDATION_RETRY_DELAY_SECONDS=1

# Minimum file size threshold for audio validation (bytes)
MINIMUM_VALID_AUDIO_FILE_SIZE_BYTES=1024

# Test audio generation settings
FIRMWARE_TEST_TONE_DURATION_SECONDS=3
FIRMWARE_TEST_TONE_FREQUENCY_HZ=440

# ENHANCED HARDWARE VALIDATION FUNCTIONS
# =======================================

# Test if serial device is writable and responsive
test_serial_communication()
{
    local device_path="$1"

    if [ ! -w "$device_path" ]; then
        echo "ERROR: Cannot write to device $device_path"
        return 1
    fi

    # Test if we can write to the device without blocking
    if ! timeout ${SERIAL_WRITE_TIMEOUT_SECONDS} sh -c "echo 'n' > '$device_path'" 2>/dev/null; then
        echo "ERROR: Serial write operation timed out or failed"
        return 1
    fi

    return 0
}

# Validate that firmware is in development mode and responsive
test_firmware_responsiveness()
{
    local device_path="$1"
    local test_output_dir="$2"

    echo "Testing firmware responsiveness..."
    echo "IMPORTANT: Ensure Teensy firmware is in 'dev' mode to receive serial commands"

    # Create temporary test directory if it doesn't exist
    mkdir -p "$test_output_dir"

    local test_tone_file="$test_output_dir/firmware_test_tone.wav"
    local test_recording_file="$test_output_dir/firmware_test_recording.wav"

    # Generate a test tone for firmware validation
    echo "Generating test tone..."
    if ! sox -n -r 44100 -c 1 "$test_tone_file" synth ${FIRMWARE_TEST_TONE_DURATION_SECONDS} sine ${FIRMWARE_TEST_TONE_FREQUENCY_HZ} vol 0.5 2>/dev/null; then
        echo "ERROR: Failed to generate test tone"
        return 1
    fi

    # Test each firmware mode to verify responsiveness
    local mode_test_passed=0
    local total_modes_tested=0

    for mode_index in "${!modes[@]}"; do
        local mode="${modes[mode_index]}"
        local mode_name="${mode_names[mode_index]}"

        echo "Testing firmware mode: $mode_name ($mode)"

        ((total_modes_tested++))

        # Send mode command to firmware
        if ! echo "$mode" > "$device_path" 2>/dev/null; then
            echo "WARNING: Failed to send mode command '$mode' to firmware"
            continue
        fi

        # Give firmware time to process the mode change
        sleep 1

        # Play test tone and attempt to record modified output
        echo "Playing test tone and recording firmware output..."

        # Play the test tone in background
        afplay "$test_tone_file" &
        local afplay_process_id=$!

        # Record the modified audio output from firmware
        if timeout ${FIRMWARE_DEV_MODE_CHECK_TIMEOUT_SECONDS} rec "$test_recording_file" trim 0 ${FIRMWARE_TEST_TONE_DURATION_SECONDS} 2>/dev/null; then
            # Wait for playback to complete
            wait $afplay_process_id 2>/dev/null

            # Validate the recorded file
            if [ -f "$test_recording_file" ]; then
                local recorded_file_size
                if stat --version 2>/dev/null | grep -q GNU; then
                    recorded_file_size=$(stat --format="%s" "$test_recording_file" 2>/dev/null || echo "0")
                else
                    recorded_file_size=$(stat -f%z "$test_recording_file" 2>/dev/null || echo "0")
                fi

                if [ "$recorded_file_size" -gt $MINIMUM_VALID_AUDIO_FILE_SIZE_BYTES ]; then
                    echo "✓ Mode $mode_name test passed (recorded ${recorded_file_size} bytes)"
                    ((mode_test_passed++))
                else
                    echo "✗ Mode $mode_name test failed (file too small: ${recorded_file_size} bytes)"
                fi

                # Clean up test recording
                rm -f "$test_recording_file"
            else
                echo "✗ Mode $mode_name test failed (no recording created)"
            fi
        else
            # Kill playback if recording failed
            kill $afplay_process_id 2>/dev/null
            wait $afplay_process_id 2>/dev/null
            echo "✗ Mode $mode_name test failed (recording timeout or error)"
        fi
    done

    # Clean up test files
    rm -f "$test_tone_file"

    # Evaluate test results
    local success_percentage=$((mode_test_passed * 100 / total_modes_tested))

    if [ $mode_test_passed -eq $total_modes_tested ]; then
        echo "✓ Firmware responsiveness test PASSED ($mode_test_passed/$total_modes_tested modes working)"
        return 0
    elif [ $mode_test_passed -gt 0 ]; then
        echo "⚠ Firmware responsiveness test PARTIAL ($mode_test_passed/$total_modes_tested modes working, ${success_percentage}%)"
        echo "Some firmware modes may not be functioning correctly"
        return 1
    else
        echo "✗ Firmware responsiveness test FAILED (0/$total_modes_tested modes working)"
        echo "Firmware may not be in 'dev' mode or may have crashed"
        return 1
    fi
}

# Enhanced comprehensive hardware validation with retry logic
validate_hardware_setup()
{
    local retry_count=0
    local validation_temp_dir="/tmp/songbird_hardware_test"

    echo "Starting comprehensive hardware validation..."

    while [ $retry_count -lt $HARDWARE_VALIDATION_RETRY_COUNT ]; do
        if [ $retry_count -gt 0 ]; then
            echo "Retry attempt $retry_count of $HARDWARE_VALIDATION_RETRY_COUNT..."
            sleep $HARDWARE_VALIDATION_RETRY_DELAY_SECONDS
        fi

        # Step 1: Find Teensy device
        echo "Step 1: Locating Teensy device..."
        local teensy_device_path=$(find_teensy_device)

        if [ -z "$teensy_device_path" ]; then
            echo "✗ No Teensy device found"
            ((retry_count++))
            continue
        fi

        echo "✓ Found Teensy device at: $teensy_device_path"

        # Step 2: Test serial communication
        echo "Step 2: Testing serial communication..."
        if ! test_serial_communication "$teensy_device_path"; then
            echo "✗ Serial communication test failed"
            ((retry_count++))
            continue
        fi

        echo "✓ Serial communication test passed"

        # Step 3: Configure serial settings
        echo "Step 3: Configuring serial communication..."
        if ! stty -f "$teensy_device_path" 115200 cs8 -cstopb -parenb 2>/dev/null; then
            echo "✗ Failed to configure serial settings"
            ((retry_count++))
            continue
        fi

        echo "✓ Serial configuration successful"

        # Step 4: Check audio device availability
        echo "Step 4: Checking audio device availability..."
        if ! check_audio_device; then
            echo "✗ Audio device '$DEVICE_NAME' not found"
            echo "Available audio devices:"
            SwitchAudioSource -a 2>/dev/null || echo "  Could not list audio devices"
            ((retry_count++))
            continue
        fi

        echo "✓ Audio device '$DEVICE_NAME' found"

        # Step 5: Test firmware responsiveness
        echo "Step 5: Testing firmware responsiveness..."
        if ! test_firmware_responsiveness "$teensy_device_path" "$validation_temp_dir"; then
            echo "✗ Firmware responsiveness test failed"
            echo ""
            echo "TROUBLESHOOTING STEPS:"
            echo "1. Ensure Teensy firmware is running and in 'dev' mode"
            echo "2. Check audio cable connections"
            echo "3. Verify firmware has not crashed (try resetting Teensy)"
            echo "4. Confirm audio routing is working properly"
            ((retry_count++))
            continue
        fi

        echo "✓ Firmware responsiveness test passed"

        # Clean up temporary directory
        rm -rf "$validation_temp_dir"

        # All tests passed
        echo ""
        echo "🎉 Hardware validation SUCCESSFUL!"
        echo "All systems ready for audio recording"
        return 0
    done

    # All retries exhausted
    echo ""
    echo "💥 Hardware validation FAILED after $HARDWARE_VALIDATION_RETRY_COUNT attempts"
    echo ""
    echo "HARDWARE REQUIREMENTS:"
    echo "  - Teensy device connected via USB"
    echo "  - Songbird firmware loaded and running in 'dev' mode"
    echo "  - Audio cables properly connected"
    echo "  - '$DEVICE_NAME' audio device available in macOS"
    echo ""
    echo "Please resolve hardware issues and try again."

    # Clean up temporary directory
    rm -rf "$validation_temp_dir"

    return 1
}

# Quick hardware check (lighter validation for use during recording)
check_hardware_during_recording()
{
    local teensy_device_path="$1"

    # Quick check that device still exists and is writable
    if [ ! -w "$teensy_device_path" ]; then
        echo "⚠ WARNING: Teensy device no longer accessible at $teensy_device_path"
        return 1
    fi

    # Quick check that audio device is still available
    if ! check_audio_device; then
        echo "⚠ WARNING: Audio device '$DEVICE_NAME' no longer available"
        return 1
    fi

    return 0
}

# DIRECTORY STRUCTURE FUNCTIONS
# ==============================

setup_working_directory()
{
  # Delete existing directories before starting a new run
  echo "Cleaning previous output directories..."
  if [ -d "$WORKING_DIR" ]; then
    rm -rf "$WORKING_DIR"
    echo "Deleted existing directory $WORKING_DIR"
  fi

  # Create directory structure organized by mode/speaker
  for mode_index in "${!modes[@]}"; do
    mode_name="${mode_names[$mode_index]}"

      for speaker_id in $(get_speakers); do
          mkdir -p "$WORKING_DIR/$mode_name/$speaker_id"
          echo "Created directory: $WORKING_DIR/$mode_name/$speaker_id"
      done
  done
}

# UTILITY FUNCTIONS
# =================

print_header()
{
  echo ""
  echo "############################################"
  echo "#                                          #"
  echo "#       $1"
  echo "#                                          #"
  echo "############################################"
  echo ""
}