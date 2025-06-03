#!/bin/bash

# =============================================================================
# AUDIO RECORDING ENGINE WITH CHECKPOINT SYSTEM
# =============================================================================
#
# ⚠️  DESTRUCTIVE OPERATION - OVERWRITES EXISTING RECORDINGS
#
# Records audio modified by Teensy hardware in 4 modes: Noise, PitchShift,
# Wave, and All. Processes test files for all 3 speakers.
#
# NEW: CHECKPOINT & RESUME SYSTEM
# -------------------------------
# ✅ Automatically detects interrupted sessions
# ✅ Asks for confirmation before resuming
# ✅ Validates existing recordings thoroughly
# ✅ Skips already completed work
# ✅ Provides detailed progress tracking
#
# CRITICAL WARNING:
# -----------------
# 🔴 DELETES all existing files in working-evaluation/ (if starting fresh)
# 🔴 Records fresh modified audio (20-45 minutes for full session)
# 🔴 Cannot be undone - backup precious recordings first!
#
# BACKUP BEFORE RUNNING:
# ----------------------
# cp -r working-evaluation/ backup-$(date +%Y%m%d)/
#
# HARDWARE REQUIREMENTS:
# ----------------------
# - Teensy device connected and functional
# - Teensy firmware responding to mode commands (n, p, w, a)
# - Audio cables properly connected
#
# PROCESS:
# --------
# For each test audio file:
#   1. Check if already completed (checkpoint system)
#   2. Send mode command to Teensy (n/p/w/a)
#   3. Play original audio through Teensy
#   4. Record modified output
#   5. Validate recording thoroughly (size, format, duration, content)
#   6. Update checkpoint file
#   7. Generate tracking report
#
# INTERRUPTION HANDLING:
# ----------------------
# - Ctrl+C saves partial results
# - Restores original audio devices
# - Maintains checkpoint file for resume
# - Creates termination report
#
# AUTOMATIC INTEGRATION:
# ----------------------
# Called by songbird-pipeline.sh evaluation
#
# =============================================================================

# Source common functions
source songbird-common.sh

# Register signal handlers for cleanup
trap cleanup SIGINT SIGTERM SIGHUP

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
  echo "" >> $TRACKING_FILE
  echo "PROCESS TERMINATED EARLY: $(date)" >> $TRACKING_FILE
  echo "----------------------------------------" >> $TRACKING_FILE

  # Update checkpoint file with termination notice
  if [ -f "$CHECKPOINT_FILE" ]; then
    echo "# Session terminated early: $(date)" >> $CHECKPOINT_FILE
  fi

  # Display checkpoint summary
  display_checkpoint_summary

  # Return audio devices to original settings if possible
  restore_original_audio_sources

  echo "Termination cleanup complete. Partial results saved."
  echo "You can resume this session later by running the script again."
  exit 1
}

# Functions to simulate associative arrays
set_total_files_created() {
  local speaker="$1"
  local value="$2"
  # Clean speaker name for variable name (replace hyphens and other chars with underscores)
  local clean_speaker=$(echo "$speaker" | sed 's/[^a-zA-Z0-9]/_/g')
  eval "total_files_created_${clean_speaker}=${value}"
}

get_total_files_created() {
  local speaker="$1"
  local clean_speaker=$(echo "$speaker" | sed 's/[^a-zA-Z0-9]/_/g')
  local value
  eval "value=\$total_files_created_${clean_speaker}"
  echo "${value:-0}"
}

increment_total_files_created() {
  local speaker="$1"
  local current=$(get_total_files_created "$speaker")
  set_total_files_created "$speaker" $((current + 1))
}

set_files_modified() {
  local speaker="$1"
  local mode="$2"
  local value="$3"
  # Clean the key for variable name
  local clean_key=$(echo "${speaker}-${mode}" | sed 's/[^a-zA-Z0-9]/_/g')
  eval "files_modified_${clean_key}=${value}"
}

get_files_modified() {
  local speaker="$1"
  local mode="$2"
  local clean_key=$(echo "${speaker}-${mode}" | sed 's/[^a-zA-Z0-9]/_/g')
  local value
  eval "value=\$files_modified_${clean_key}"
  echo "${value:-0}"
}

increment_files_modified() {
  local speaker="$1"
  local mode="$2"
  local current=$(get_files_modified "$speaker" "$mode")
  set_files_modified "$speaker" "$mode" $((current + 1))
}

print_header "Audio Recording with Checkpoint System"

# Initialize Counters
total_processed=0
total_skipped=0
EARLY_TERMINATION=0
RESUME_MODE=false

# INITIALIZE CHECKPOINT SYSTEM
# ============================
echo "Initializing checkpoint system..."

if ! initialize_checkpoint_system "$WORKING_DIR"; then
    echo "ERROR: Failed to initialize checkpoint system"
    exit 1
fi

# Check for resumable session
if check_for_resumable_session; then
    if confirm_resume_session; then
        RESUME_MODE=true
        echo "📋 Resume mode enabled. Checking existing recordings..."
    else
        RESUME_MODE=false
        echo "🔄 Fresh session mode. All recordings will be processed."
    fi
else
    echo "🆕 No previous session found. Starting fresh recording session."
    RESUME_MODE=false
fi

# COMPREHENSIVE HARDWARE VALIDATION
# ==================================
echo "Performing comprehensive hardware validation before starting recording..."
echo "This may take up to 30 seconds to complete all tests."
echo ""

if ! validate_hardware_setup; then
    echo ""
    echo "❌ CRITICAL ERROR: Hardware validation failed"
    echo "Cannot proceed with audio recording until hardware issues are resolved."
    exit 1
fi

echo ""
echo "Hardware validation completed successfully. Starting recording process..."
echo ""

# Get the validated Teensy device path
device=$(find_teensy_device)

# This should not fail since validation passed, but double-check
if [ -z "$device" ]; then
  echo "⚠️ ERROR: Could not find a Teensy device. Is it connected?"
  exit 1
fi

echo "Using validated Teensy device at: $device"

# Configure serial communication settings
# 115200 - Set baud rate to 115200 bps
# cs8    - 8 data bits
# -cstopb - 1 stop bit (disable 2 stop bits)
# -parenb - No parity bit
stty -f $device 115200 cs8 -cstopb -parenb

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
echo "Teensy audio configuration complete!"

# Create a report for tracking our progress
echo "FILE MODIFICATION TRACKING REPORT" > $TRACKING_FILE
echo "Generated on $(date)" >> $TRACKING_FILE
if [ "$RESUME_MODE" = "true" ]; then
    echo "Mode: RESUME - Continuing from previous session" >> $TRACKING_FILE
else
    echo "Mode: FRESH - New recording session" >> $TRACKING_FILE
fi
echo "----------------------------------------" >> $TRACKING_FILE

# Process each speaker in the array
for speaker in ${speakers[@]}; do
  # Initialize counters for this speaker
  set_total_files_created "$speaker" 0

  # Initialize mode-specific counters for this speaker
  for mode in "${modes[@]}"; do
    set_files_modified "$speaker" "$mode" 0
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
    source_filename=$(basename "$file")
    echo ""
    echo "PROCESSING FILE $current_file of $source_file_count: $display_name"
    echo "---------------------------------------------------------"

    file_status="Success"  # Track if all modifications for this file succeeded

    for mode_index in "${!modes[@]}"; do # Play and record each file in each mode
      mode="${modes[mode_index]}"
      mode_name="${mode_names[mode_index]}"

      basename=$(basename "$file" ".wav")
      filename=$basename-$mode_name.wav
      output_path="$WORKING_DIR/$mode_name/$speaker/$filename"

      # CHECK CHECKPOINT: Skip if already completed
      if [ "$RESUME_MODE" = "true" ] && is_recording_completed "$speaker" "$mode_name" "$source_filename"; then
        echo "  Mode: $mode_name ($mode) [$(($mode_index+1)) of ${#modes[@]}] - CHECKING EXISTING..."

        # Validate existing file thoroughly
        if validate_existing_audio_file "$output_path" "$EXPECTED_AUDIO_DURATION_SECONDS"; then
          echo "  ✅ SKIPPED - Valid recording already exists: $output_path"
          increment_files_modified "$speaker" "$mode"
          increment_total_files_created "$speaker"
          ((total_processed++))
          ((total_skipped++))

          # Log skip in tracking file
          echo "  - $basename ($mode): Skipped - Valid existing file" >> $TRACKING_FILE
          continue
        else
          echo "  ⚠️ EXISTING FILE INVALID - Re-recording: $output_path"
          # Mark as failed in checkpoint and continue with recording
          record_completion "$speaker" "$mode_name" "$source_filename" "$output_path" "FAILED"
        fi
      fi

      # Periodic hardware check during long recording sessions
      if ! check_hardware_during_recording "$device"; then
          echo "⚠️ HARDWARE FAILURE DETECTED during recording!"
          echo "Attempting to continue, but results may be compromised."
          file_status="Failed - Hardware Issue"
      fi

      echo $mode > $device

      # Play the file and record
      echo "  Mode: $mode_name ($mode) [$(($mode_index+1)) of ${#modes[@]}] - RECORDING..."

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
        # Recording was successful, validate thoroughly
        if validate_existing_audio_file "$output_path" "$EXPECTED_AUDIO_DURATION_SECONDS"; then
          echo "  ✅ Recording complete and validated: $output_path"
          increment_files_modified "$speaker" "$mode"
          increment_total_files_created "$speaker"
          ((total_processed++))

          # Record successful completion in checkpoint
          record_completion "$speaker" "$mode_name" "$source_filename" "$output_path" "COMPLETED"

          # Log success in tracking file
          echo "  - $basename ($mode): Success" >> $TRACKING_FILE
        else
          echo "  ❌ Recording validation failed: $output_path"
          file_status="Failed - Validation Failed"

          # Record failure in checkpoint
          record_completion "$speaker" "$mode_name" "$source_filename" "$output_path" "FAILED"

          # Log failure in tracking file
          echo "  - $basename ($mode): Failed - Validation Failed" >> $TRACKING_FILE
        fi
      else
        # Recording failed
        echo "  ❌ Recording failed: $output_path"
        file_status="Failed - Recording Error"

        # Record failure in checkpoint
        record_completion "$speaker" "$mode_name" "$source_filename" "$output_path" "FAILED"

        # Log failure in tracking file
        echo "  - $basename ($mode): Failed - Recording Error" >> $TRACKING_FILE
      fi
    done
    echo "---------------------------------------------------------"
  done

  # Log speaker summary to tracking file
  echo "" >> $TRACKING_FILE
  echo "SPEAKER $speaker SUMMARY:" >> $TRACKING_FILE
  echo "Total files created: $(get_total_files_created "$speaker")" >> $TRACKING_FILE

  for mode_index in "${!modes[@]}"; do
    mode="${modes[$mode_index]}"
    mode_name="${mode_names[$mode_index]}"
    echo "  - $mode_name mode: $(get_files_modified "$speaker" "$mode")" >> $TRACKING_FILE
  done
  echo "----------------------------------------" >> $TRACKING_FILE
done

# Log grand totals to tracking file
echo "" >> $TRACKING_FILE
echo "OVERALL SUMMARY:" >> $TRACKING_FILE
echo "Total audio files processed: $total_processed" >> $TRACKING_FILE
echo "Total files skipped (existing): $total_skipped" >> $TRACKING_FILE

# Calculate totals by mode across all speakers
for mode_index in "${!modes[@]}"; do
  mode="${modes[$mode_index]}"
  mode_name="${mode_names[$mode_index]}"
  mode_total=0

  for speaker in ${speakers[@]}; do
    mode_total=$((mode_total + $(get_files_modified "$speaker" "$mode")))
  done

  echo "Total files in $mode_name mode: $mode_total" >> $TRACKING_FILE
done

echo "" >> $TRACKING_FILE
echo "Tracking report saved to: $TRACKING_FILE"

# Display a summary to the console
echo ""
echo "=============== PROCESSING SUMMARY ==============="
if [ $EARLY_TERMINATION -eq 1 ]; then
  echo "⚠️ PROCESS WAS TERMINATED EARLY"
fi
echo "Total files processed: $total_processed"
echo "Total files skipped (valid existing): $total_skipped"

for speaker in "${speakers[@]}"; do
  # Calculate expected number of files (source files × number of modes)
  source_count=$(find $FILES_DIR/$speaker -name "*.wav" | wc -l | tr -d ' ')
  expected=$((source_count * ${#modes[@]}))

  # Get actual count
  actual=$(get_total_files_created "$speaker")

  # Calculate completion percentage
  if [ $expected -eq 0 ]; then
    percentage="N/A"
  else
    percentage=$((actual * 100 / expected))
  fi

  echo "User $speaker: $(get_total_files_created "$speaker") files created ($percentage% of expected $expected files)"
  for mode_index in "${!modes[@]}"; do
    mode="${modes[$mode_index]}"
    mode_name="${mode_names[$mode_index]}"
    echo "  - $mode_name mode: $(get_files_modified "$speaker" "$mode")"
  done
done

echo ""
echo "Check $TRACKING_FILE for detailed report"

# Display final checkpoint summary
display_checkpoint_summary

echo "==============================================="

# Return audio devices to original settings at the end of processing
restore_original_audio_sources
echo ""
echo "🎉 Audio recording completed!"
if [ "$RESUME_MODE" = "true" ]; then
    echo "📋 Checkpoint file saved for future reference: $CHECKPOINT_FILE"
else
    echo "💾 Checkpoint file created for future recovery: $CHECKPOINT_FILE"
fi