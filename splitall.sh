#!/bin/bash
# =============================================================================
# AUDIO SPLITTER FOR TRAINING DATA
# =============================================================================
#
# Splits MP3 files into 10-second WAV segments for ML training.
# Processes speakers 21525, 23723, and 19839.
#
# USAGE:
# ------
# ./splitall.sh <source_dir> <output_dir>
# ./splitall.sh audio/training working-training
#
# FUNCTION:
# ---------
# - Cleans existing WAV files in output directories
# - Creates speaker-specific output directories
# - Processes all MP3 files using split.sh
# - Reports processing statistics
#
# SAFETY:
# -------
# 🟢 SAFE - Only processes training data, no recordings affected
# ⚠️  Cleans existing WAV files in output directories
#
# DEPENDENCIES:
# -------------
# - split.sh (individual file splitter)
# - ffmpeg (for audio conversion)
#
# AUTOMATIC INTEGRATION:
# ----------------------
# Called by songbird-pipeline.sh training - rarely used directly
#
# =============================================================================

source songbird-common.sh

SPEAKER_DIR="$1"
WORKING_DIR="$2"

echo "Processing audio for speakers: $(get_speakers)"

for speaker_id in $(get_speakers); do
  if ! is_valid_speaker "$speaker_id"; then
    echo "Error: Invalid speaker ID: $speaker_id"
    continue
  fi

  # Clean the working directories if they already exist
  if [ -d "${WORKING_DIR}/$speaker_id" ]; then
    rm -f "${WORKING_DIR}/$speaker_id"/*.wav
    echo "Cleaned WAV files for speaker $speaker_id"
  fi

  # Create an output directory for each SPEAKER_ID
  mkdir -p "${WORKING_DIR}/$speaker_id"

  # Check if input directory exists
  if [ ! -d "${SPEAKER_DIR}/$speaker_id" ]; then
    echo "Warning: Directory ${SPEAKER_DIR}/$speaker_id does not exist. Skipping..."
    continue
  fi

  # Process all mp3 files for the current speaker_id
  mp3_count=0

  for file in "${SPEAKER_DIR}/$speaker_id"/*.mp3; do
    if [ -f "$file" ]; then
      ./split.sh "$file" ${MAX_TIME} "${WORKING_DIR}/$speaker_id"
      mp3_count=$((mp3_count + 1))
    fi
  done

  if [ $mp3_count -eq 0 ]; then
    echo "No MP3 files found for speaker ID $speaker_id"
  else
    echo "Processed $mp3_count files for speaker ID $speaker_id"
  fi

done