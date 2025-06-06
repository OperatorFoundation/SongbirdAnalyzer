#!/bin/bash

# =============================================================================
# AUDIO RECORDING ENGINE WITH CHECKPOINT SYSTEM
# =============================================================================
#
# Records modified audio using Teensy hardware with comprehensive error handling,
# progress tracking, and checkpoint/resume functionality.
#
# USAGE:
# ------
# ./evaluation-record-modified-audio.sh [--resume] [--force] [--verbose]
#
# =============================================================================


# Load the modular core system
if ! source "$(dirname "$0")/songbird-core/songbird-core.sh"; then
    echo "💥 FATAL: Could not load Songbird core modules" >&2
    exit 1
fi

# Initialize error handling
setup_error_handling

# Recording state variables
RECORDING_SESSION_START_TIME=""
TOTAL_RECORDINGS_PLANNED=0
RECORDINGS_COMPLETED=0
RECORDINGS_FAILED=0
RESUME_MODE=false

# Parse command line arguments
parse_arguments()
{
    FORCE_MODE=false

    for arg in "$@"; do
        case $arg in
            --resume)
                RESUME_MODE=true
                ;;
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
                warning "Unknown argument: $arg"
                ;;
        esac
    done
}

# Show usage information
show_usage() {
    cat << EOF
SONGBIRD EVALUATION RECORDING SCRIPT

USAGE:
    $0 [options]

OPTIONS:
    --resume        Resume previous recording session from checkpoint
    --force         Skip confirmation prompts and overwrite existing files
    --verbose, -v   Enable verbose output and detailed progress reporting
    --help, -h      Show this help message

DESCRIPTION:
    Records modified audio using Teensy hardware for all configured speakers
    and modification modes. Features comprehensive error handling, automatic
    checkpointing, and resume capability.

RECORDING PROCESS:
    1. Hardware validation and audio system setup
    2. Load or create recording checkpoint
    3. Process each speaker/mode combination
    4. Real-time audio validation
    5. Progress tracking with ETA calculation
    6. Automatic recovery from failures

SAFETY FEATURES:
    🛡️  Hardware monitoring with automatic recovery
    ✅ Checkpoint system for session resume
    📊 Real-time progress tracking
    🔄 Audio validation and retry mechanisms

For more information, see the project documentation.
EOF
}

# Calculate recording session statistics
calculate_session_stats()
{
    # Total combinations = speakers × modes × files per speaker
    TOTAL_RECORDINGS_PLANNED=0

    for speaker in "${speakers[@]}"; do
        local files_dir="$FILES_DIR/$speaker"
        if [[ -d "$files_dir" ]]; then
            local file_count=$(find "$files_dir" -name "*.wav" -type f 2>/dev/null | wc -l)
            TOTAL_RECORDINGS_PLANNED=$((TOTAL_RECORDINGS_PLANNED + file_count * ${#modes[@]}))
        fi
    done

    info "Recording session statistics:"
    info "  Speakers: ${#speakers[@]}"
    info "  Modes: ${#modes[@]}"
    info "  Total recordings planned: $TOTAL_RECORDINGS_PLANNED"
}

# Setup recording session
setup_recording_session() {
    print_header "RECORDING SESSION SETUP"

    RECORDING_SESSION_START_TIME=$(date +%s)

    # Validate working directory
    check_directory_writable "$WORKING_DIR" "Working directory not accessible"

    # Calculate session statistics
    calculate_session_stats

    if [[ $TOTAL_RECORDINGS_PLANNED -eq 0 ]]; then
        error_exit "No recordings to process. Check that test files exist in $FILES_DIR"
    fi

    # Initialize or load checkpoint
    if [[ "$USE_PYTHON_CHECKPOINTS" == "true" ]]; then
        setup_checkpoint_system
    else
        warning "Python checkpoints disabled, using legacy tracking"
        setup_legacy_tracking
    fi

    # Show session overview
    echo "Recording Session Overview:"
    echo "=========================="
    echo "Total recordings planned: $TOTAL_RECORDINGS_PLANNED"
    echo "Estimated duration: $((TOTAL_RECORDINGS_PLANNED * (MAX_TIME + 5) / 60)) minutes"
    echo "Checkpoint file: $CHECKPOINT_FILE"
    echo ""

    if [[ "$RESUME_MODE" == "true" ]]; then
        load_checkpoint_status
    fi

    success "Recording session setup completed"
}

# Setup Python checkpoint system
setup_checkpoint_system() {
    local checkpoint_script="$SONGBIRD_CORE_PYTHON_DIR/checkpoint_manager.py"

    if [[ ! -f "$checkpoint_script" ]]; then
        warning "Python checkpoint script not found, falling back to legacy tracking"
        setup_legacy_tracking
        return 1
    fi

    if [[ "$RESUME_MODE" == "true" && -f "$CHECKPOINT_FILE" ]]; then
        info "Loading existing checkpoint for resume..."

        # Get checkpoint summary
        local summary=$("$PYTHON_CMD" "$checkpoint_script" summary "$CHECKPOINT_FILE" 2>/dev/null)
        if [[ $? -eq 0 ]]; then
            echo "Checkpoint Summary:"
            echo "$summary" | jq -r '
                "  Total tasks: \(.total_tasks)",
                "  Completed: \(.status_counts.COMPLETED // 0)",
                "  Failed: \(.status_counts.FAILED // 0)",
                "  Pending: \(.status_counts.PENDING // 0)",
                "  Completion rate: \(.completion_rate | floor)%"
            ' 2>/dev/null || echo "$summary"
        fi
    else
        info "Initializing new checkpoint..."
        if ! "$PYTHON_CMD" "$checkpoint_script" init "$CHECKPOINT_FILE"; then
            error_exit "Failed to initialize checkpoint system"
        fi

        # Register all recording tasks
        register_all_recording_tasks
    fi

    success "Checkpoint system ready"
}

# Register all recording tasks in checkpoint system
register_all_recording_tasks() {
    local checkpoint_script="$SONGBIRD_CORE_PYTHON_DIR/checkpoint_manager.py"

    info "Registering recording tasks in checkpoint system..."

    local registered_count=0

    for speaker in "${speakers[@]}"; do
        local files_dir="$FILES_DIR/$speaker"

        if [[ ! -d "$files_dir" ]]; then
            warning "Files directory not found for speaker $speaker: $files_dir"
            continue
        fi

        # Process each test file
        for test_file in "$files_dir"/*.wav; do
            if [[ -f "$test_file" ]]; then
                local source_filename=$(basename "$test_file")

                # Register task for each mode
                for mode_index in "${!modes[@]}"; do
                    local mode="${modes[mode_index]}"
                    local mode_name="${mode_names[mode_index]}"
                    local output_filename="${speaker}_${source_filename%.*}_${mode_name}.wav"
                    local output_path="$WORKING_DIR/$speaker/$output_filename"

                    local task_id=$("$PYTHON_CMD" "$checkpoint_script" register "$CHECKPOINT_FILE" \
                        "$speaker" "$mode_name" "$source_filename" "$output_path" 2>/dev/null)

                    if [[ $? -eq 0 ]]; then
                        ((registered_count++))
                    else
                        error_log "Failed to register task: $speaker/$mode_name/$source_filename"
                    fi
                done
            fi
        done
    done

    success "Registered $registered_count recording tasks"
}

# Load checkpoint status for resume
load_checkpoint_status() {
    local checkpoint_script="$SONGBIRD_CORE_PYTHON_DIR/checkpoint_manager.py"

    # Get current status counts
    local summary=$("$PYTHON_CMD" "$checkpoint_script" summary "$CHECKPOINT_FILE" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        RECORDINGS_COMPLETED=$(echo "$summary" | jq -r '.status_counts.COMPLETED // 0' 2>/dev/null || echo "0")
        RECORDINGS_FAILED=$(echo "$summary" | jq -r '.status_counts.FAILED // 0' 2>/dev/null || echo "0")

        info "Resume mode: $RECORDINGS_COMPLETED completed, $RECORDINGS_FAILED failed"

        local remaining=$((TOTAL_RECORDINGS_PLANNED - RECORDINGS_COMPLETED - RECORDINGS_FAILED))
        info "Remaining recordings: $remaining"
    fi
}

# Setup legacy tracking (fallback)
setup_legacy_tracking() {
    if [[ ! -f "$TRACKING_FILE" ]]; then
        echo "# Modified Audio Tracking Report" > "$TRACKING_FILE"
        echo "# Generated on $(date)" >> "$TRACKING_FILE"
        echo "# Format: speaker|mode|source_file|output_file|status|timestamp" >> "$TRACKING_FILE"
    fi
}

# Check if recording task is already completed
is_recording_completed() {
    local speaker="$1"
    local mode_name="$2"
    local source_filename="$3"

    if [[ "$USE_PYTHON_CHECKPOINTS" == "true" ]]; then
        local checkpoint_script="$SONGBIRD_CORE_PYTHON_DIR/checkpoint_manager.py"
        "$PYTHON_CMD" "$checkpoint_script" is_completed "$CHECKPOINT_FILE" "$speaker" "$mode_name" "$source_filename" >/dev/null 2>&1
        return $?
    else
        # Legacy tracking check
        local output_filename="${speaker}_${source_filename%.*}_${mode_name}.wav"
        local output_path="$WORKING_DIR/$speaker/$output_filename"
        [[ -f "$output_path" ]]
        return $?
    fi
}

# Mark recording task as completed
mark_recording_completed() {
    local speaker="$1"
    local mode_name="$2"
    local source_filename="$3"
    local output_path="$4"
    local validation_result="$5"

    if [[ "$USE_PYTHON_CHECKPOINTS" == "true" ]]; then
        local checkpoint_script="$SONGBIRD_CORE_PYTHON_DIR/checkpoint_manager.py"

        # Get task by parameters to find task_id
        local task_info=$("$PYTHON_CMD" -c "
import sys
sys.path.append('$SONGBIRD_CORE_PYTHON_DIR')
from checkpoint_manager import CheckpointManager
manager = CheckpointManager('$CHECKPOINT_FILE')
task = manager.get_task_by_params('$speaker', '$mode_name', '$source_filename')
if task:
    print(task.task_id)
else:
    print('')
" 2>/dev/null)

        if [[ -n "$task_info" ]]; then
            "$PYTHON_CMD" "$checkpoint_script" complete "$CHECKPOINT_FILE" "$task_info" >/dev/null 2>&1
        fi
    else
        # Legacy tracking
        echo "$speaker|$mode_name|$source_filename|$output_path|COMPLETED|$(date)" >> "$TRACKING_FILE"
    fi

    ((RECORDINGS_COMPLETED++))
}

# Mark recording task as failed
mark_recording_failed() {
    local speaker="$1"
    local mode_name="$2"
    local source_filename="$3"
    local error_message="$4"

    if [[ "$USE_PYTHON_CHECKPOINTS" == "true" ]]; then
        local checkpoint_script="$SONGBIRD_CORE_PYTHON_DIR/checkpoint_manager.py"

        # Get task by parameters to find task_id
        local task_info=$("$PYTHON_CMD" -c "
import sys
sys.path.append('$SONGBIRD_CORE_PYTHON_DIR')
from checkpoint_manager import CheckpointManager
manager = CheckpointManager('$CHECKPOINT_FILE')
task = manager.get_task_by_params('$speaker', '$mode_name', '$source_filename')
if task:
    print(task.task_id)
else:
    print('')
" 2>/dev/null)

        if [[ -n "$task_info" ]]; then
            "$PYTHON_CMD" "$checkpoint_script" fail "$CHECKPOINT_FILE" "$task_info" "$error_message" >/dev/null 2>&1
        fi
    else
        # Legacy tracking
        echo "$speaker|$mode_name|$source_filename|FAILED|FAILED|$(date) - $error_message" >> "$TRACKING_FILE"
    fi

    ((RECORDINGS_FAILED++))
}

# Record single audio file with specific mode
record_single_audio() {
    local speaker="$1"
    local mode="$2"
    local mode_name="$3"
    local test_file="$4"
    local output_dir="$5"

    local source_filename=$(basename "$test_file")
    local output_filename="${speaker}_${source_filename%.*}_${mode_name}.wav"
    local output_path="$output_dir/$output_filename"

    # Check if already completed
    if is_recording_completed "$speaker" "$mode_name" "$source_filename"; then
        info "⏭️  Skipping $speaker/$mode_name/$source_filename (already completed)"
        ((RECORDINGS_COMPLETED++))
        return 0
    fi

    # Check if output file exists and force mode is off
    if [[ -f "$output_path" && "$FORCE_MODE" != "true" ]]; then
        warning "Output file exists: $output_filename"
        info "⏭️  Skipping (use --force to overwrite)"
        return 0
    fi

    info "🎙️  Recording: $speaker/$mode_name/$source_filename"

    # Send mode command to Teensy
    if ! echo "$mode" > "$TEENSY_DEVICE_PATH" 2>/dev/null; then
        local error_msg="Failed to send mode command '$mode' to Teensy"
        error_log "$error_msg"
        mark_recording_failed "$speaker" "$mode_name" "$source_filename" "$error_msg"
        return 1
    fi

    # Give Teensy time to process mode change
    sleep 1

    # Start recording in background
    local recording_pid
    rec "$output_path" trim 0 "$MAX_TIME" &
    recording_pid=$!

    # Play the test file
    local playback_pid
    afplay "$test_file" &
    playback_pid=$!

    # Wait for both processes to complete
    wait "$playback_pid" 2>/dev/null
    wait "$recording_pid" 2>/dev/null
    local recording_exit_code=$?

    # Validate recording
    if [[ $recording_exit_code -eq 0 && -f "$output_path" ]]; then
        # Use Python validation if available
        if validate_audio_file_robust "$output_path" "$EXPECTED_AUDIO_DURATION_SECONDS" "$AUDIO_VALIDATION_TOLERANCE_SECONDS"; then
            success "✅ Recording successful: $output_filename"
            mark_recording_completed "$speaker" "$mode_name" "$source_filename" "$output_path" "validated"
            return 0
        else
            local error_msg="Audio validation failed"
            error_log "$error_msg: $output_filename"
            mark_recording_failed "$speaker" "$mode_name" "$source_filename" "$error_msg"

            # Remove invalid file
            rm -f "$output_path"
            return 1
        fi
    else
        local error_msg="Recording process failed (exit code: $recording_exit_code)"
        error_log "$error_msg: $output_filename"
        mark_recording_failed "$speaker" "$mode_name" "$source_filename" "$error_msg"

        # Remove any partial file
        rm -f "$output_path"
        return 1
    fi
}

# Process all recordings for a speaker
process_speaker_recordings() {
    local speaker="$1"

    info "Processing recordings for speaker: $speaker"

    local files_dir="$FILES_DIR/$speaker"
    local output_dir="$WORKING_DIR/$speaker"

    # Validate directories
    check_file_readable "$files_dir" "Test files directory not found for speaker $speaker"
    check_directory_writable "$output_dir" "Output directory not accessible for speaker $speaker"

    # Get list of test files
    local test_files=($(find "$files_dir" -name "*.wav" -type f 2>/dev/null | sort))

    if [[ ${#test_files[@]} -eq 0 ]]; then
        warning "No test files found for speaker $speaker in $files_dir"
        return 0
    fi

    info "Found ${#test_files[@]} test files for speaker $speaker"

    # Process each test file with each mode
    for test_file in "${test_files[@]}"; do
        local source_filename=$(basename "$test_file")

        for mode_index in "${!modes[@]}"; do
            local mode="${modes[mode_index]}"
            local mode_name="${mode_names[mode_index]}"

            # Calculate and show progress
            local current_recording=$((RECORDINGS_COMPLETED + RECORDINGS_FAILED + 1))
            print_progress "$current_recording" "$TOTAL_RECORDINGS_PLANNED" "$speaker/$mode_name/$source_filename"

            # Perform the recording
            if ! record_single_audio "$speaker" "$mode" "$mode_name" "$test_file" "$output_dir"; then
                warning "Recording failed: $speaker/$mode_name/$source_filename"

                # Hardware check after failure
                if ! check_hardware_during_recording "$TEENSY_DEVICE_PATH" "true"; then
                    warning "Hardware check failed, attempting recovery..."
                    if reset_teensy_device; then
                        info "Hardware recovery successful, continuing..."
                    else
                        error_log "Hardware recovery failed"
                        return 1
                    fi
                fi
            fi

            # Brief pause between recordings
            sleep 0.5
        done
    done

    success "Completed recordings for speaker $speaker"
    return 0
}

# Generate recording session report
generate_recording_report() {
    local end_time=$(date +%s)
    local session_duration=$((end_time - RECORDING_SESSION_START_TIME))
    local report_file="$WORKING_DIR/recording_session_report.txt"

    print_header "RECORDING SESSION REPORT"

    {
        echo "SONGBIRD RECORDING SESSION REPORT"
        echo "================================="
        echo "Generated: $(date)"
        echo "Session Duration: ${session_duration} seconds ($((session_duration / 60)) minutes)"
        echo ""

        echo "RECORDING STATISTICS:"
        echo "===================="
        echo "Total Planned: $TOTAL_RECORDINGS_PLANNED"
        echo "Completed: $RECORDINGS_COMPLETED"
        echo "Failed: $RECORDINGS_FAILED"
        echo "Success Rate: $(( RECORDINGS_COMPLETED * 100 / (RECORDINGS_COMPLETED + RECORDINGS_FAILED) ))%"
        echo ""

        if [[ "$USE_PYTHON_CHECKPOINTS" == "true" ]]; then
            echo "CHECKPOINT SUMMARY:"
            echo "=================="
            "$PYTHON_CMD" "$SONGBIRD_CORE_PYTHON_DIR/checkpoint_manager.py" summary "$CHECKPOINT_FILE" 2>/dev/null || echo "Checkpoint summary unavailable"
            echo ""
        fi

        echo "OUTPUT DIRECTORIES:"
        echo "=================="
        for speaker in "${speakers[@]}"; do
            local output_dir="$WORKING_DIR/$speaker"
            if [[ -d "$output_dir" ]]; then
                local file_count=$(find "$output_dir" -name "*.wav" -type f 2>/dev/null | wc -l)
                echo "  $speaker: $file_count WAV files"
            else
                echo "  $speaker: No output directory"
            fi
        done

        echo ""
        echo "SESSION STATUS: $(if [[ $RECORDINGS_FAILED -eq 0 ]]; then echo "COMPLETED SUCCESSFULLY"; else echo "COMPLETED WITH FAILURES"; fi)"

    } > "$report_file"

    success "Recording session report saved: $report_file"

    # Show summary
    echo ""
    echo "Recording Session Summary:"
    echo "========================="
    echo "✅ Completed: $RECORDINGS_COMPLETED"
    if [[ $RECORDINGS_FAILED -gt 0 ]]; then
        echo "❌ Failed: $RECORDINGS_FAILED"
    fi
    echo "📊 Success Rate: $(( RECORDINGS_COMPLETED * 100 / (RECORDINGS_COMPLETED + RECORDINGS_FAILED) ))%"
    echo "⏱️  Duration: $((session_duration / 60)) minutes"
}

# Main recording function
main() {
    # Parse arguments
    parse_arguments "$@"

    # Show header
    print_header "SONGBIRD EVALUATION RECORDING"

    echo "Recording Configuration:"
    echo "======================="
    echo "Resume Mode: $RESUME_MODE"
    echo "Force Mode: $FORCE_MODE"
    echo "Verbose Mode: $VERBOSE_OPERATIONS"
    echo "Max Recording Time: ${MAX_TIME}s"
    echo "Speakers: ${speakers[*]}"
    echo "Modes: ${mode_names[*]}"
    echo ""

    # Validate prerequisites
    local requirements=("python3" "sox" "SwitchAudioSource")
    if ! validate_prerequisites "${requirements[@]}"; then
        error_exit "Prerequisites validation failed"
    fi

    # Validate hardware
    if [[ "$REQUIRE_HARDWARE_VALIDATION" == "true" ]]; then
        if ! validate_hardware_setup 2; then
            error_exit "Hardware validation failed"
        fi
    fi

    # Setup recording session
    setup_recording_session

    # Switch to Teensy audio
    if ! switch_to_teensy_audio "both"; then
        error_exit "Failed to switch to Teensy audio device"
    fi

    # Process recordings for each speaker
    print_header "RECORDING PROCESS"

    for speaker in "${speakers[@]}"; do
        if ! process_speaker_recordings "$speaker"; then
            error_log "Failed to complete recordings for speaker $speaker"
        fi
        echo ""  # Add spacing between speakers
    done

    # Generate final report
    generate_recording_report

    # Final status
    if [[ $RECORDINGS_FAILED -eq 0 ]]; then
        success "🎉 All recordings completed successfully!"
        exit 0
    else
        warning "Recording session completed with $RECORDINGS_FAILED failures"
        echo ""
        echo "To retry failed recordings, run:"
        echo "  $0 --resume"
        exit 1
    fi
}

# Cleanup function
cleanup_recording_session() {
    info "Cleaning up recording session..."

    # Kill any remaining audio processes
    pkill -f "rec.*\.wav" 2>/dev/null || true
    pkill -f "afplay.*\.wav" 2>/dev/null || true

    # Restore original audio sources
    restore_original_audio_sources
}

# Register cleanup
register_cleanup_function "cleanup_recording_session"

# Execute main function
main "$@"