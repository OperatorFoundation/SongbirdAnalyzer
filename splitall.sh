#!/bin/bash

# =============================================================================
# AUDIO SPLITTER FOR TRAINING DATA
# =============================================================================
#
# Splits MP3 files into 10-second WAV segments for ML training.
#
# USAGE:
# ------
# ./splitall.sh <source_dir> <output_dir> [--force] [--verbose]
# ./splitall.sh audio/training working-training
# ./splitall.sh audio/training working-training --force --verbose
#
#
# =============================================================================

# Load the new modular core system
if ! source "$(dirname "$0")/songbird-core/songbird-core.sh"; then
    echo "💥 FATAL: Could not load Songbird core modules" >&2
    echo "   Make sure songbird-core directory exists with required modules" >&2
    exit 1
fi

# Initialize error handling system
setup_error_handling

# Parse command line arguments
parse_arguments()
{
    SPEAKER_DIR=""
    WORKING_DIR=""
    FORCE_MODE=false
    VERBOSE_OPERATIONS=false

    for arg in "$@"; do
        case $arg in
            --force)
                FORCE_MODE=true
                ;;
            --verbose|-v)
                VERBOSE_OPERATIONS=true
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                if [[ -z "$SPEAKER_DIR" ]]; then
                    SPEAKER_DIR="$arg"
                elif [[ -z "$WORKING_DIR" ]]; then
                    WORKING_DIR="$arg"
                else
                    error_exit "Too many arguments provided. Use --help for usage information."
                fi
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$SPEAKER_DIR" || -z "$WORKING_DIR" ]]; then
        error_exit "Missing required arguments. Use --help for usage information."
    fi
}

# Show usage information
show_usage() {
    cat << EOF
SONGBIRD AUDIO SPLITTER FOR TRAINING DATA

USAGE:
    $0 <source_dir> <output_dir> [options]

ARGUMENTS:
    source_dir      Directory containing speaker subdirectories with MP3 files
    output_dir      Directory where WAV segments will be created

OPTIONS:
    --force         Skip confirmation prompts and auto-backup existing data
    --verbose, -v   Enable verbose output and detailed progress reporting
    --help, -h      Show this help message

EXAMPLES:
    $0 audio/training working-training
    $0 audio/training working-training --force --verbose

SAFETY FEATURES:
    🛡️  Automatic backup of existing training data
    ✅ Comprehensive validation before processing
    📊 Progress tracking and detailed reporting
    🔄 Recovery mechanisms for common failures

SPEAKERS PROCESSED:
    $(printf '%s ' "${speakers[@]}")

For more information, see the project documentation.
EOF
}

# Validate environment and prerequisites
validate_environment()
{
    info "Validating environment and prerequisites..."

    # Check core prerequisites
    local requirements=(
        "ffmpeg"
        "working_directory"
        "python3"
    )

    if ! validate_prerequisites "${requirements[@]}"; then
        error_exit "Environment validation failed. Please install missing prerequisites."
    fi

    # Validate split.sh exists and is executable
    if [[ ! -f "./split.sh" ]]; then
        error_exit "split.sh not found in current directory. This script depends on split.sh."
    fi

    if [[ ! -x "./split.sh" ]]; then
        error_exit "split.sh is not executable. Run: chmod +x ./split.sh"
    fi

    # Validate speaker configuration
    if ! validate_speaker_config; then
        error_exit "Speaker configuration validation failed"
    fi

    success "Environment validation completed successfully"
}

# Validate source directory structure
validate_source_directory()
{
    local source_dir="$1"

    info "Validating source directory: $source_dir"

    if [[ ! -d "$source_dir" ]]; then
        error_exit "Source directory not found: $source_dir"
    fi

    if [[ ! -r "$source_dir" ]]; then
        error_exit "Source directory not readable: $source_dir"
    fi

    # Check for speaker subdirectories
    local found_speakers=()
    local missing_speakers=()

    for speaker_id in "${speakers[@]}"; do
        local speaker_dir="$source_dir/$speaker_id"

        if [[ -d "$speaker_dir" ]]; then
            # Check for MP3 files
            local mp3_count=$(find "$speaker_dir" -name "*.mp3" -type f 2>/dev/null | wc -l)

            if [[ $mp3_count -gt 0 ]]; then
                found_speakers+=("$speaker_id ($mp3_count MP3 files)")
                info "✅ Speaker $speaker_id: $mp3_count MP3 files found"
            else
                warning "⚠️  Speaker $speaker_id: directory exists but no MP3 files found"
                missing_speakers+=("$speaker_id (no MP3 files)")
            fi
        else
            warning "⚠️  Speaker $speaker_id: directory not found"
            missing_speakers+=("$speaker_id (directory missing)")
        fi
    done

    # Report validation results
    if [[ ${#found_speakers[@]} -eq 0 ]]; then
        error_exit "No valid speaker directories with MP3 files found in $source_dir"
    fi

    success "Source directory validation completed"
    info "Found speakers: ${found_speakers[*]}"

    if [[ ${#missing_speakers[@]} -gt 0 ]]; then
        info "Missing/empty speakers: ${missing_speakers[*]}"
    fi
}

# Process a single speaker's audio files
process_speaker_audio()
{
    local speaker_id="$1"
    local source_dir="$2"
    local output_dir="$3"

    local speaker_source_dir="$source_dir/$speaker_id"
    local speaker_output_dir="$output_dir/$speaker_id"

    info "Processing speaker $speaker_id..."

    # Verify directories exist
    if [[ ! -d "$speaker_source_dir" ]]; then
        warning "Skipping speaker $speaker_id: source directory not found"
        return 1
    fi

    if [[ ! -d "$speaker_output_dir" ]]; then
        error_log "Output directory not found: $speaker_output_dir"
        return 1
    fi

    # Find MP3 files
    local mp3_files=($(find "$speaker_source_dir" -name "*.mp3" -type f 2>/dev/null))

    if [[ ${#mp3_files[@]} -eq 0 ]]; then
        warning "No MP3 files found for speaker $speaker_id"
        return 0
    fi

    info "Found ${#mp3_files[@]} MP3 files for speaker $speaker_id"

    # Process each MP3 file
    local processed_count=0
    local failed_count=0

    for mp3_file in "${mp3_files[@]}"; do
        local file_basename=$(basename "$mp3_file")

        # Show progress
        print_progress $((processed_count + failed_count + 1)) ${#mp3_files[@]} "Processing $file_basename"

        # Get file info if verbose
        if [[ "$VERBOSE_OPERATIONS" == "true" ]]; then
            get_file_info "$mp3_file" true
        fi

        # Process with split.sh
        if run_with_error_handling "Splitting $file_basename" ./split.sh "$mp3_file" "$MAX_TIME" "$speaker_output_dir"; then
            ((processed_count++))
        else
            ((failed_count++))
            error_log "Failed to process: $file_basename"
        fi
    done

    # Report speaker processing results
    if [[ $failed_count -eq 0 ]]; then
        success "✅ Speaker $speaker_id: $processed_count files processed successfully"
    else
        warning "⚠️  Speaker $speaker_id: $processed_count succeeded, $failed_count failed"
    fi

    return 0
}

# Generate comprehensive processing report
generate_processing_report()
{
    local source_dir="$1"
    local output_dir="$2"
    local start_time="$3"
    local end_time="$4"

    print_header "PROCESSING REPORT"

    echo "Source Directory: $source_dir"
    echo "Output Directory: $output_dir"
    echo "Processing Time: $((end_time - start_time)) seconds"
    echo "Timestamp: $(date)"
    echo ""

    # Count results for each speaker
    echo "Results by Speaker:"
    echo "=================="

    local total_input_files=0
    local total_output_files=0

    for speaker_id in "${speakers[@]}"; do
        local input_count=0
        local output_count=0

        # Count input MP3 files
        if [[ -d "$source_dir/$speaker_id" ]]; then
            input_count=$(find "$source_dir/$speaker_id" -name "*.mp3" -type f 2>/dev/null | wc -l)
        fi

        # Count output WAV files
        if [[ -d "$output_dir/$speaker_id" ]]; then
            output_count=$(find "$output_dir/$speaker_id" -name "*.wav" -type f 2>/dev/null | wc -l)
        fi

        total_input_files=$((total_input_files + input_count))
        total_output_files=$((total_output_files + output_count))

        if [[ $input_count -gt 0 ]]; then
            echo "  Speaker $speaker_id: $input_count MP3 → $output_count WAV segments"
        else
            echo "  Speaker $speaker_id: No input files"
        fi
    done

    echo ""
    echo "Overall Summary:"
    echo "==============="
    echo "Total MP3 files processed: $total_input_files"
    echo "Total WAV segments created: $total_output_files"

    if [[ $total_input_files -gt 0 ]]; then
        local avg_segments_per_file=$((total_output_files / total_input_files))
        echo "Average segments per MP3: $avg_segments_per_file"
    fi

    # Estimate total audio duration
    local estimated_duration_minutes=$((total_output_files * MAX_TIME / 60))
    echo "Estimated total audio duration: ${estimated_duration_minutes} minutes"

    echo ""
    success "🎉 Audio splitting completed successfully!"
}

# Main processing function
main()
{
    local start_time=$(date +%s)

    # Parse command line arguments
    parse_arguments "$@"

    # Show configuration
    print_header "SONGBIRD AUDIO SPLITTER"

    echo "Configuration:"
    echo "=============="
    echo "Source Directory: $SPEAKER_DIR"
    echo "Output Directory: $WORKING_DIR"
    echo "Max Segment Time: ${MAX_TIME}s"
    echo "Force Mode: $FORCE_MODE"
    echo "Verbose Mode: $VERBOSE_OPERATIONS"
    echo "Speakers: ${speakers[*]}"
    echo ""

    # Validate environment
    validate_environment

    # Validate source directory
    validate_source_directory "$SPEAKER_DIR"

    # Setup working directory with backup handling
    info "Setting up output directory structure..."
    if ! setup_training_working_directory "$WORKING_DIR" "$FORCE_MODE"; then
        error_exit "Working directory setup failed or was cancelled"
    fi

    # Process each speaker
    print_header "PROCESSING AUDIO FILES"

    local speaker_count=0
    local speaker_success_count=0

    for speaker_id in "${speakers[@]}"; do
        ((speaker_count++))

        if process_speaker_audio "$speaker_id" "$SPEAKER_DIR" "$WORKING_DIR"; then
            ((speaker_success_count++))
        fi

        echo ""  # Add spacing between speakers
    done

    local end_time=$(date +%s)

    # Generate final report
    generate_processing_report "$SPEAKER_DIR" "$WORKING_DIR" "$start_time" "$end_time"

    # Final status
    if [[ $speaker_success_count -eq $speaker_count ]]; then
        success "All speakers processed successfully!"
        exit 0
    else
        warning "Processing completed with some failures ($speaker_success_count/$speaker_count speakers successful)"
        exit 1
    fi
}

# Cleanup function (registered with error handler)
cleanup_on_exit() {
    info "Cleaning up temporary files..."
    # Add any specific cleanup here if needed
}

# Register cleanup function
register_cleanup_function "cleanup_on_exit"

# Execute main function
main "$@"