#!/bin/bash

# Common variables
MAX_TIME=10
USERS_DIR="audio/training"
RESULTS_FILE="results/evaluation.csv"
FILES_DIR="results/testing_wav"
WORKING_DIR="working-evaluation"
MODEL_FILE="songbird.pkl"
DEVICE_NAME="Teensy MIDI_Audio" # The device name as it appears on macOS
TRACKING_FILE="modified_audio_tracking_report.txt"

# Modes and speakers
modes=("n" "p" "w" "a")
mode_names=("Noise" "PitchShift" "Wave" "All")
speakers=("21525" "23723" "19839")

# Audio device functions
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

# Directory structure
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

    for speaker in "${speakers[@]}"; do
      mkdir -p "$WORKING_DIR/$mode_name/$speaker"
      echo "Created directory: $WORKING_DIR/$mode_name/$speaker"
    done
  done
}

# Print a section header
print_header() {
  echo ""
  echo "############################################"
  echo "#                                          #"
  echo "#       $1"
  echo "#                                          #"
  echo "############################################"
  echo ""
}