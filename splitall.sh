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
# ./splitall.sh <source_dir> <output_dir> [--force]
# ./splitall.sh audio/training working-training
# ./splitall.sh audio/training working-training --force
#
# FUNCTION:
# ---------
# - Safely handles existing WAV files in output directories
# - Creates speaker-specific output directories
# - Processes all MP3 files using split.sh
# - Reports processing statistics
#
# SAFETY:
# -------
# 🟢 SAFE - Only processes training data, no recordings affected
# ✅ PROTECTED - Automatic backup of existing training data
# ⚠️  Training data is regenerable, but backups are available
#
# FLAGS:
# ------
# --force    Skip interactive prompts and automatically create backups
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

# Parse arguments
SPEAKER_DIR=""
WORKING_DIR=""
FORCE_MODE=false

# Process positional arguments first
for arg in "$@"; do
    case $arg in
        --force)
            FORCE_MODE=true
            ;;
        *)
            if [ -z "$SPEAKER_DIR" ]; then
                SPEAKER_DIR="$arg"
            elif [ -z "$WORKING_DIR" ]; then
                WORKING_DIR="$arg"
            fi
            ;;
    esac
done

# Validate required arguments
if [ -z "$SPEAKER_DIR" ] || [ -z "$WORKING_DIR" ]; then
    echo "ERROR: Missing required arguments"
    echo "Usage: $0 <source_dir> <output_dir> [--force]"
    echo ""
    echo "Examples:"
    echo "  $0 audio/training working-training"
    echo "  $0 audio/training working-training --force"
    exit 1
fi

echo "Processing audio for speakers: $(get_speakers)"
echo "Source directory: $SPEAKER_DIR"
echo "Output directory: $WORKING_DIR"
if [ "$FORCE_MODE" = "true" ]; then
    echo "Force mode: enabled"
fi
echo ""

# Use the new safe training directory setup
if ! setup_training_working_directory "$WORKING_DIR" "$FORCE_MODE"; then
    echo "Training directory setup failed or was cancelled."
    exit 1
fi

for speaker_id in $(get_speakers); do
    if ! is_valid_speaker "$speaker_id"; then
        echo "Error: Invalid speaker ID: $speaker_id"
        continue
    fi

    # The directory was already created by setup_training_working_directory
    # But verify it exists
    if [ ! -d "${WORKING_DIR}/$speaker_id" ]; then
        echo "Error: Expected directory not found: ${WORKING_DIR}/$speaker_id"
        continue
    fi

    # Check if input directory exists
    if [ ! -d "${SPEAKER_DIR}/$speaker_id" ]; then
        echo "Warning: Source directory ${SPEAKER_DIR}/$speaker_id does not exist. Skipping..."
        continue
    fi

    # Process all mp3 files for the current speaker_id
    mp3_count=0

    echo "Processing speaker $speaker_id..."
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

echo ""
echo "Audio splitting completed successfully!"