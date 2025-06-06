
#!/bin/bash

# =============================================================================
# AUDIO FILE SPLITTER
# =============================================================================
#
# Splits an audio file into segments of a specified maximum length.
# Used for preparing training data by converting long audio files into
# uniform segments suitable for machine learning processing.
#
# USAGE:
# ------
# ./split.sh <input_file> [max_time] [output_dir]
#
# ARGUMENTS:
# ----------
# input_file    Path to the input audio file to split
# max_time      Maximum duration per segment in seconds (optional)
# output_dir    Directory where segments will be saved (optional)
#
# OUTPUT FORMAT:
# --------------
# Segments are saved as: {basename}_{sequence_number}.wav
# Example: audio_001.wav, audio_002.wav, etc.
#
# =============================================================================

# Load the modular core system
if ! source "$(dirname "$0")/songbird-core/songbird-core.sh"
then
    echo "💥 FATAL: Could not load Songbird core modules" >&2
    echo "   Make sure songbird-core directory exists with required modules" >&2
    exit 1
fi

# Initialize error handling system
setup_error_handling

# Configuration constants
readonly DEFAULT_SEGMENT_DURATION_SECONDS=10
readonly SEGMENT_FILE_NAME_FORMAT="%03n"
readonly AUDIO_CHANNELS_MONO=1
readonly SOX_VERBOSITY_LEVEL=1

# Parse and validate command line arguments
parse_arguments()
{
    if [[ $# -lt 1 ]]
    then
        error_exit "Missing required argument: input_file
Usage: $0 <input_file> [max_time] [output_dir]"
    fi

    INPUT_FILE="$1"
    SEGMENT_DURATION="${2:-$DEFAULT_SEGMENT_DURATION_SECONDS}"
    OUTPUT_DIR="$3"

    # Validate input file
    check_file_readable "$INPUT_FILE" "Input audio file not accessible"

    # Validate segment duration is a positive number
    if ! [[ "$SEGMENT_DURATION" =~ ^[0-9]+$ ]] || [[ "$SEGMENT_DURATION" -le 0 ]]
    then
        error_exit "Invalid segment duration: $SEGMENT_DURATION (must be a positive integer)"
    fi

    # If no output directory specified, use current directory
    if [[ -z "$OUTPUT_DIR" ]]
    then
        OUTPUT_DIR="."
    fi

    # Ensure output directory exists and is writable
    check_directory_writable "$OUTPUT_DIR" "Output directory not accessible"
}

# Extract base filename without extension for output naming
get_base_filename()
{
    local input_file="$1"
    basename "${input_file%.*}"
}

# Split audio file into segments using sox
split_audio_file()
{
    local input_file="$1"
    local segment_duration="$2"
    local output_dir="$3"

    local base_filename
    base_filename=$(get_base_filename "$input_file")

    local output_pattern="$output_dir/${base_filename}_${SEGMENT_FILE_NAME_FORMAT}.wav"

    info "Splitting audio file into ${segment_duration}-second segments..."
    info "Input: $input_file"
    info "Output pattern: $output_pattern"

    # Use sox to split the audio file with the following options:
    # -V1: Set verbosity level to minimal
    # -c 1: Convert to mono (single channel)
    # trim 0 {duration}: Extract segments of specified duration
    # : newfile : restart: Create new files and restart segment extraction
    if run_with_error_handling "Audio splitting" \
        sox "$input_file" \
            -V$SOX_VERBOSITY_LEVEL \
            -c $AUDIO_CHANNELS_MONO \
            "$output_pattern" \
            trim 0 "$segment_duration" : newfile : restart
    then
        # Count generated segments
        local segment_count
        segment_count=$(find "$output_dir" -name "${base_filename}_*.wav" -type f 2>/dev/null | wc -l)

        success "Successfully created $segment_count audio segments"

        if [[ "$VERBOSE_OPERATIONS" == "true" ]]
        then
            info "Generated segments:"
            find "$output_dir" -name "${base_filename}_*.wav" -type f | sort
        fi
    else
        error_exit "Failed to split audio file: $input_file"
    fi
}

# Main execution function
main()
{
    local input_file segment_duration output_dir

    parse_arguments "$@"

    info "Starting audio file splitting process..."
    info "Segment duration: ${SEGMENT_DURATION} seconds"

    split_audio_file "$INPUT_FILE" "$SEGMENT_DURATION" "$OUTPUT_DIR"

    success "Audio splitting completed successfully"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
    main "$@"
fi