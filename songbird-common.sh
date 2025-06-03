
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