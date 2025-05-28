#!/opt/homebrew/bin/bash

: <<'BOOP'
###############################################################
#                                                             #
#  ██████  IMPORTANT: DEVICE DEPENDANT OPERATION              #
#  █       This script should only be run while               #
#  █       a songbird device is plugged in to your computer   #
#  ██████  and in development mode.                           #
#                                                             #
###############################################################
BOOP


MAX_TIME=10
USERS_DIR="audio/training"
RESULTS_FILE="results/evaluation.csv"
FILES_DIR="results/testing_wav"
WORKING_DIR="working-evaluation"
MODEL_FILE="songbird.pkl"
DEVICE_NAME="Teensy MIDI_Audio" # The device name as it appears on macOS
TRACKING_FILE="modified_audio_tracking_report.txt"

# Track if we're stopping early
EARLY_TERMINATION=0

# Track original audio devices
ORIGINAL_INPUT=""
ORIGINAL_OUTPUT=""

# Initialize Counters
declare -A total_files_created
declare -A files_modified
total_processed=0

modes=("n" "p" "w" "a")
mode_names=("Noise" "PitchShift" "Wave" "All")
speakers=("21525" "23723" "19839")

# Register signal handlers
trap cleanup SIGINT SIGTERM SIGHUP

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

cleanup() {
  echo ""
  echo "⚠️ Process interrupted! Cleaning up..."

  # Kill any playing audio
  pkill afplay 2>/dev/null

  # Kill any recording processes
  pkill rec 2>/dev/null

  # Set flag for early termination
  EARLY_TERMINATION=1

  # Update tracking file
    # Update tracking file with termination notice
  echo "" >> $TRACKING_FILE
  echo "PROCESS TERMINATED EARLY: $(date)" >> $TRACKING_FILE
  echo "----------------------------------------" >> $TRACKING_FILE

  # Return audio devices to original settings if possible
  restore_original_audio_sources

  echo "Termination cleanup complete. Partial results saved."
  exit 1
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

check_audio_device()
{
  # Returns true (0) if device exists, false (1) otherwise
  SwitchAudioSource -a | grep -q "$DEVICE_NAME"
  return $?
}

process_all_speakers_audio()
{
  # Create a report for tracking our progress
  echo "FILE MODIFICATION TRACKING REPORT" > $TRACKING_FILE
  echo "Generated on $(date)" >> $TRACKING_FILE
  echo "----------------------------------------" >> $TRACKING_FILE

  # Process each speaker in the array
  for speaker in ${speakers[@]}; do
  # Initialize counters for this speaker
  total_files_created[$speaker]=0

  # Initialize mode-specific counters for this speaker
  for mode in "${modes[@]}"; do
    files_modified["$speaker-$mode"]=0
  done

  # Count number of source files for this speaker
  source_file_count=$(find $FILES_DIR/$speaker -name "*.wav" | wc -l | tr -d ' ')
  echo ""
  echo "========================================================="
  echo "SPEAKER $speaker: Found $source_file_count source files to process"
  echo "========================================================="

  # Get all files for this speaker into an array
  speaker_files=()
  while IFS= read -r file_path; do
    speaker_files+=("$file_path")
  done < <(find $FILES_DIR/$speaker -name "*.wav")

   # Process each file with a counter for progress tracking
   current_file=0
   for file in "${speaker_files[@]}"; do
     # Check if we're terminating early
     if [ $EARLY_TERMINATION -eq 1 ]; then
       echo "Skipping the remaining files due to termination request"
       break
     fi

    ((current_file++))

    display_name=$(basename "$file")
    echo ""
    echo "PROCESSING FILE $current_file of $source_file_count: $display_name"
    echo "---------------------------------------------------------"

    file_status="Success"  # Track if all modifications for this file succeeded\

    for mode_index in "${!modes[@]}"; do # Play and record each file in each mode
      mode="${modes[mode_index]}"
      mode_name="${mode_names[mode_index]}"

      echo $mode > $device
      basename=$(basename "$file" ".wav")
      filename=$basename-$mode_name.wav
      output_path="$WORKING_DIR/$mode_name/$speaker/$filename"

      # Play the file and record
      echo "  Mode: $mode_name ($mode) [$(($mode_index+1)) of ${#modes[@]}]"

      # Check for termination request before starting new recording
      if [ $EARLY_TERMINATION -eq 1 ]; then
        echo "  Skipping this mode due to termination request."
        continue
      fi

      echo "  Current audio input device: $(SwitchAudioSource -c -t input)"
      echo "  Current audio output device: $(SwitchAudioSource -c -t output)"

      afplay $file &
      afplay_pid=$!
      echo "  Recording to: $output_path..."

      rec $output_path trim 0 $MAX_TIME
      rec_status=$? # the exit status of the most recently executed command

      # Check if recording was successful
      if [ $rec_status -eq 0 ] && [ -f "$output_path" ]; then
        # Recording was successful, continue processing

        # Get the file size to verify its a valid recording (more than 1kb)
        # Check file size - use platform-independent approach
        if [ -f "$output_path" ]; then
          # Try different stat formats based on OS
          if stat --version 2>/dev/null | grep -q GNU; then
            # GNU stat (Linux)
            filesize=$(stat --format="%s" "$output_path" 2>/dev/null || echo "0")
          else
            # BSD stat (macOS)
            filesize=$(stat -f%z "$output_path" 2>/dev/null || echo "0")
          fi

          # Make sure filesize is a number
          if ! [[ "$filesize" =~ ^[0-9]+$ ]]; then
            filesize=0
          fi
        else
          filesize=0
        fi

        if [ $filesize -gt 1024 ]; then
          echo "Recording complete and verified: $output_path ($filesize bytes)"
          ((files_modified["$speaker-$mode"]++))
          ((total_files_created[$speaker]++))
          ((total_processed++))
                  else
          echo "⚠️ WARNING: Recording may be corrupt or empty: $output_path ($filesize bytes)"
          file_status="Failed - Small File"
        fi
      else
        # Recording failed
        echo "⚠️ ERROR: Recording failed for $output_path"
        file_status="Failed - Recording Error"
      fi

      # Log individual file results
      echo "  - $basename ($mode): $file_status" >> $TRACKING_FILE
    done
    echo "---------------------------------------------------------"
  done

  # Log speaker summary to tracking file
  echo "" >> $TRACKING_FILE
  echo "SPEAKER $speaker SUMMARY:" >> $TRACKING_FILE
  echo "Total files created: ${total_files_created[$speaker]}" >> $TRACKING_FILE

  for mode_index in "${!modes[@]}"; do
    mode="${modes[$mode_index]}"
    mode_name="${mode_names[$mode_index]}"
    echo "  - $mode_name mode: ${files_modified["$speaker-$mode"]}" >> $TRACKING_FILE
  done
  echo "----------------------------------------" >> $TRACKING_FILE
done

  # Log grand totals to tracking file
  echo "" >> $TRACKING_FILE
  echo "OVERALL SUMMARY:" >> $TRACKING_FILE
  echo "Total audio files processed: $total_processed" >> $TRACKING_FILE

  # Calculate totals by mode across all speakers
  for mode_index in "${!modes[@]}"; do
    mode="${modes[$mode_index]}"
    mode_name="${mode_names[$mode_index]}"
    mode_total=0

    for speaker in ${speakers[@]}; do
      mode_total=$((mode_total + files_modified["$speaker-$mode"]))
    done

    echo "Total files in $mode_name mode: $mode_total" >> $TRACKING_FILE
  done

  echo "" >> $TRACKING_FILE
  echo "Tracking report saved to: $TRACKING_FILE"
}

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

device=$(find_teensy_device)

# check if the device was found
if [ -z "$device" ]; then
  echo "⚠️ ERROR: Could not find a Teensy device. Is it connected?"
  exit 1
else
  echo "Found Teensy device at: $device"
fi

# Configure serial communication settings
# 115200 - Set baud rate to 115200 bps
# cs8    - 8 data bits
# -cstopb - 1 stop bit (disable 2 stop bits)
# -parenb - No parity bit
stty -f $device 115200 cs8 -cstopb -parenb

# Check if SwitchAudioSource is installed
if ! command -v SwitchAudioSource &>/dev/null; then
  echo "ERROR: SwitchAudioSource not found. Install it with: brew install switchaudio-osx"
  exit 1
fi

# Save original audio sources before changing anything
save_original_audio_sources

# Check If Audio Device Exists
if ! check_audio_device; then
  echo "ERROR: Audio device '$DEVICE_NAME' not found."
  echo "Available audio devices: "
  SwitchAudioSource -a
  exit 1
fi

# Set Teensy as the audio input device
echo "Setting $DEVICE_NAME as audio input device"
SwitchAudioSource -t "input" -s "$DEVICE_NAME"

echo "Setting $DEVICE_NAME as audio output device..."
SwitchAudioSource -t "output" -s "$DEVICE_NAME"

# Verify that the settings were applied
echo "Current audio input device: $(SwitchAudioSource -c -t input)"
echo "Current audio output device: $(SwitchAudioSource -c -t output)"
echo "Teensy audio configuration complete!\n"


############################################
#                                          #
#       Evaluation Business                #
#                                          #
############################################

setup_working_directory
process_all_speakers_audio

echo "\nRunning analysis scripts..."
if [ $EARLY_TERMINATION -eq 0 ]; then
  python3 automfcc.py $WORKING_DIR $RESULTS_FILE
  python3 evaluate.py $RESULTS_FILE
  python3 predict.py $RESULTS_FILE $MODEL_FILE
else
  echo "Skipping analysis scripts due to early termination."
  echo "You can run them manually when ready:"
  echo "  python3 automfcc.py $WORKING_DIR $RESULTS_FILE"
  echo "  python3 evaluate.py $RESULTS_FILE"
  echo "  python3 predict.py $RESULTS_FILE $MODEL_FILE"
fi

# Display a summary to the console
echo ""
echo "=============== PROCESSING SUMMARY ==============="
if [ $EARLY_TERMINATION -eq 1 ]; then
  echo "⚠️ PROCESS WAS TERMINATED EARLY"
fi
echo "Total files processed: $total_processed"

for speaker in "${speakers[@]}"; do
  # Calculate expected number of files (source files × number of modes)
  source_count=$(find $FILES_DIR/$speaker -name "*.wav" | wc -l | tr -d ' ')
  expected=$((source_count * ${#modes[@]}))

  # Get actual count
  actual=${total_files_created[$speaker]}

  # Calculate completion percentage
  if [ $expected -eq 0 ]; then
    percentage="N/A"
  else
    percentage=$((actual * 100 / expected))
  fi

  echo "User $speaker: ${total_files_created[$speaker]} files created ($percentage% of expected $expected files)"
  for mode_index in "${!modes[@]}"; do
    mode="${modes[$mode_index]}"
    mode_name="${mode_names[$mode_index]}"
    echo "  - $mode_name mode: ${files_modified["$speaker-$mode"]}"
  done
done
echo ""
echo "Check $TRACKING_FILE for detailed report"
echo "==============================================="

# Return audio devices to original settings at the end of processing
restore_original_audio_sources
echo "Evaluation completed successfully!"