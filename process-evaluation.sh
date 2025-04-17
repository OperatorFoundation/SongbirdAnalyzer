
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

#!/bin/bash

MAX_TIME=15
USERS_DIR="audio/training"
RESULTS_FILE="results/evaluation.csv"
FILES_DIR="results/testing_wav"
WORKING_DIR="working-evaluation"
MODEL_FILE="songbird.pkl"
DEVICE_NAME="Teensy MIDI_Audio" # The device name as it appears on macOS
TRACKING_FILE="modified_audio_tracking_report.txt"

# Track if we're stopping early
EARLY_TERMINATION=0

set_audio_to_defaults() {
  if command -v SwitchAudioSource &>/dev/null; then
    echo "Restoring default audio devices..."
    SwitchAudioSource -t "input" -s "Built-in Microphone" 2>dev/null
    SwitchAudioSource -t "output" -s "Built-in Output" 2>dev/null
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

  # Return audio devices to default settings if possible
  set_audio_to_defaults

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

check_audio_device()
{
  # Returns true (0) if device exists, false (1) otherwise
  SwitchAudioSource -a | grep -q "$DEVICE_NAME"
  return $?
}

# Check If Audio Device Exists
if ! check_audio_device; then
  echo "ERROR: Audio device '$DEVICE_DEVICE_NAME' not found."
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
echo "Teensy audio configuration complete!"


############################################
#                                          #
#       Evaluation Business                #
#                                          #
############################################

# Register signal handlers
trap cleanup SIGINT SIGTERM SIGHUP

# Create a report for tracking our progress
echo "FILE MODIFICATION TRACKING REPORT" > $TRACKING_FILE
echo "Generated on $(date)" >> $TRACKING_FILE
echo "----------------------------------------" >> $TRACKING_FILE

# Initialize Counters
declare -A total_files_created
declare -A files_modified
total_processed=0

modes=("n" "p" "w" "a")
mode_names=("Noise" "PitchShift" "Wave" "All")
users=("21525" "23723" "19839")

# Process each user in the array
for user in ${users[@]}; do
  mkdir -p $WORKING_DIR/$user # Make sure we have an evaluation directory for each user

  # Initialize counters for this user
  total_files_created[$user]=0

    # Initialize mode-specific counters for this user
  for mode in "${modes[@]}"; do
    files_modified["$user-$mode"]=0
  done

  # Count number of source files for this user
  source_file_count=$(find $FILES_DIR/$user -name "*.wav" | wc -l | tr -d ' ')
  echo ""
  echo "========================================================="
  echo "USER $user: Found $source_file_count source files to process"
  echo "========================================================="

  # Get all files for this user into an array
  user_files=()
  while IFS= read -r file_path; do
    user_files+=("$file_path")
  done < <(find $FILES_DIR/$user -name "*.wav" | sort)

   # Process each file with a counter for progress tracking
   current_file=0
   for file in "${user_files[@]}"; do
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
      output_path="$WORKING_DIR/$user/$filename"

      # Play the file and record
      echo "  Mode: $mode_name ($mode) [$(($mode_index+1)) of ${#modes[@]}]"

      # Check for termination request before starting new recording
      if [ $EARLY_TERMINATION -eq 1 ]; then
        echo "  Skipping this mode due to termination request."
        continue
      fi

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
          ((files_modified["$user_$mode"]++))
          ((total_files_created[$user]++))
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
  done

  # Log speaker summary to tracking file
  echo "" >> $TRACKING_FILE
  echo "USER $user SUMMARY:" >> $TRACKING_FILE
  echo "Total files created: ${total_files_created[$user]}" >> $TRACKING_FILE

  for mode_index in "$!modes[@]"; do
    mode="${modes[$mode_index]}"
    mode_name="${mode_names[$mode_index]}"
    echo "  - $mode_name mode: ${files_modified["$user-$mode"]}" >> $TRACKING_FILE
  done
  echo "----------------------------------------" >> $TRACKING_FILE
done

# Log grand totals to tracking file
echo "" >> $TRACKING_FILE
echo "OVERALL SUMMARY:" >> $TRACKING_FILE
echo "Total audio files processed: $total_processed" >> $TRACKING_FILE

# Calculate totals by mode across all users
for mode_index in "${!modes[@]}"; do
  mode="${modes[$mode_index]}"
  mode_name="${mode_names[$mode_index]}"
  mode_total=0

  for user in ${users[@]}; do
    mode_total=$((mode_total + files_modified["$user-$mode"]))
  done

  echo "Total files in $mode_name mode: $mode_total" >> $TRACKING_FILE
done

echo "" >> $TRACKING_FILE
echo "Tracking report saved to: $TRACKING_FILE"

echo "Running analysis scripts..."
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
for user in "${users[@]}"; do
  # Calculate expected number of files (source files × number of modes)
  source_count=$(find $FILES_DIR/$user -name "*.wav" | wc -l | tr -d ' ')
  expected=$((source_count * ${#modes[@]}))

  # Get actual count
  actual=${total_files_created[$user]}

  # Calculate completion percentage
  if [ $expected -eq 0 ]; then
    percentage="N/A"
  else
    percentage=$((actual * 100 / expected))
  fi

  echo "User $user: ${total_files_created[$user]} files created ($percentage% of expected $expected files)"
  for mode_index in "${!modes[@]}"; do
    mode="${modes[$mode_index]}"
    mode_name="${mode_names[$mode_index]}"
    echo "  - $mode_name mode: ${files_modified["$user-$mode"]}"
  done
done
echo ""
echo "Check $TRACKING_FILE for detailed report"
echo "==============================================="