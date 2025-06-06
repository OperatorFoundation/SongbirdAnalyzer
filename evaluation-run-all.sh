#!/bin/bash

# =============================================================================
# COMPLETE EVALUATION PIPELINE
# =============================================================================
#
# Runs the complete evaluation pipeline with error handling,
# progress tracking, and checkpoint/resume functionality.
#
# USAGE:
# ------
# ./evaluation-run-all.sh [--resume] [--force] [--verbose] [--skip-setup]
#
# =============================================================================

# Load the modular core system
if ! source "$(dirname "$0")/songbird-core/songbird-core.sh"; then
    echo "💥 FATAL: Could not load Songbird core modules" >&2
    exit 1
fi

# Initialize error handling
setup_error_handling

# Pipeline state variables
PIPELINE_START_TIME=""
PIPELINE_STEPS=("setup" "recording" "mfcc" "analysis")
PIPELINE_STEP_STATUS=()
CURRENT_STEP=0
SKIP_SETUP=false

# Initialize pipeline status
for step in "${PIPELINE_STEPS[@]}"; do
    PIPELINE_STEP_STATUS+=("PENDING")
done

# Parse command line arguments
parse_arguments() {
    RESUME_MODE=false
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
            --skip-setup)
                SKIP_SETUP=true
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
SONGBIRD COMPLETE EVALUATION PIPELINE

USAGE:
    $0 [options]

OPTIONS:
    --resume        Resume pipeline from last successful step
    --force         Skip confirmation prompts and overwrite existing data
    --verbose, -v   Enable verbose output and detailed progress reporting
    --skip-setup    Skip environment setup (assume already configured)
    --help, -h      Show this help message

DESCRIPTION:
    Runs the complete evaluation pipeline:
    1. Environment Setup
    2. Audio Recording
    3. MFCC Processing
    4. Results Analysis

PIPELINE FEATURES:
    🔄 Checkpoint/resume capability
    📊 Step-by-step progress tracking
    ⏱️  Time estimation and ETA calculation
    🛡️  Comprehensive error handling
    📋 Detailed reporting and logs

SAFETY FEATURES:
    ✅ Automatic validation at each step
    🔄 Recovery mechanisms for failures
    📁 Automatic backup of existing data
    📊 Comprehensive progress reporting

For more information, see the project documentation.
EOF
}

# Update pipeline step status
update_step_status()
{
    local step_index="$1"
    local status="$2"  # PENDING, RUNNING, COMPLETED, FAILED

    if [[ $step_index -ge 0 && $step_index -lt ${#PIPELINE_STEPS[@]} ]]; then
        PIPELINE_STEP_STATUS[$step_index]="$status"
        CURRENT_STEP=$step_index
    fi
}

# Show pipeline progress
show_pipeline_progress()
{
    local show_header="${1:-true}"

    if [[ "$show_header" == "true" ]]; then
        print_header "PIPELINE PROGRESS"
    fi

    echo "Evaluation Pipeline Status:"
    echo "=========================="

    for i in "${!PIPELINE_STEPS[@]}"; do
        local step="${PIPELINE_STEPS[$i]}"
        local status="${PIPELINE_STEP_STATUS[$i]}"
        local step_name=""

        case "$step" in
            "setup") step_name="Environment Setup" ;;
            "recording") step_name="Audio Recording" ;;
            "mfcc") step_name="MFCC Processing" ;;
            "analysis") step_name="Results Analysis" ;;
        esac

        local status_icon=""
        case "$status" in
            "PENDING") status_icon="⏳" ;;
            "RUNNING") status_icon="🔄" ;;
            "COMPLETED") status_icon="✅" ;;
            "FAILED") status_icon="❌" ;;
        esac

        printf "%d. %s %s %s\n" $((i+1)) "$status_icon" "$step_name" "$status"
    done

    # Calculate progress percentage
    local completed_count=0
    for status in "${PIPELINE_STEP_STATUS[@]}"; do
        if [[ "$status" == "COMPLETED" ]]; then
            ((completed_count++))
        fi
    done

    local progress_percent=$((completed_count * 100 / ${#PIPELINE_STEPS[@]}))
    echo ""
    echo "Overall Progress: ${completed_count}/${#PIPELINE_STEPS[@]} steps ($progress_percent%)"

    # Show current step
    if [[ $CURRENT_STEP -lt ${#PIPELINE_STEPS[@]} ]]; then
        local current_step_name=""
        case "${PIPELINE_STEPS[$CURRENT_STEP]}" in
            "setup") current_step_name="Environment Setup" ;;
            "recording") current_step_name="Audio Recording" ;;
            "mfcc") current_step_name="MFCC Processing" ;;
            "analysis") current_step_name="Results Analysis" ;;
        esac
        echo "Current Step: $current_step_name"
    fi
}

# Estimate remaining time
estimate_remaining_time()
{
    local current_time=$(date +%s)
    local elapsed_time=$((current_time - PIPELINE_START_TIME))

    if [[ $elapsed_time -gt 60 && $CURRENT_STEP -gt 0 ]]; then
        local avg_time_per_step=$((elapsed_time / CURRENT_STEP))
        local remaining_steps=$((${#PIPELINE_STEPS[@]} - CURRENT_STEP))
        local estimated_remaining=$((remaining_steps * avg_time_per_step))

        echo ""
        echo "Time Estimates:"
        echo "==============="
        echo "Elapsed: $((elapsed_time / 60)) minutes"
        echo "Estimated Remaining: $((estimated_remaining / 60)) minutes"
        echo "Estimated Total: $(((elapsed_time + estimated_remaining) / 60)) minutes"
    fi
}

# Run pipeline step with error handling
run_pipeline_step() {
    local step_index="$1"
    local step_name="$2"
    local step_script="$3"
    local step_args="$4"

    update_step_status "$step_index" "RUNNING"
    show_pipeline_progress false

    print_header "STEP $((step_index + 1)): $step_name"

    local step_start_time=$(date +%s)

    info "Starting: $step_name"
    info "Script: $step_script $step_args"

    # Run the step
    if eval "$step_script $step_args"; then
        local step_end_time=$(date +%s)
        local step_duration=$((step_end_time - step_start_time))

        update_step_status "$step_index" "COMPLETED"
        success "✅ $step_name completed successfully in $((step_duration / 60)) minutes"
        return 0
    else
        update_step_status "$step_index" "FAILED"
        error_log "❌ $step_name failed"
        return 1
    fi
}

# Load pipeline checkpoint
load_pipeline_checkpoint() {
    local checkpoint_file="$WORKING_DIR/.pipeline_checkpoint"

    if [[ "$RESUME_MODE" == "true" && -f "$checkpoint_file" ]]; then
        info "Loading pipeline checkpoint..."

        # Read checkpoint data
        local step_index=0
        while IFS= read -r line; do
            if [[ $line =~ ^([0-9]+):(.*)$ ]]; then
                local idx="${BASH_REMATCH[1]}"
                local status="${BASH_REMATCH[2]}"

                if [[ $idx -ge 0 && $idx -lt ${#PIPELINE_STEP_STATUS[@]} ]]; then
                    PIPELINE_STEP_STATUS[$idx]="$status"
                    if [[ "$status" == "COMPLETED" ]]; then
                        CURRENT_STEP=$((idx + 1))
                    fi
                fi
            fi
        done < "$checkpoint_file"

        success "Pipeline checkpoint loaded"
        show_pipeline_progress false
    fi
}

# Save pipeline checkpoint
save_pipeline_checkpoint() {
    local checkpoint_file="$WORKING_DIR/.pipeline_checkpoint"

    # Create checkpoint directory
    mkdir -p "$(dirname "$checkpoint_file")"

    # Save current status
    for i in "${!PIPELINE_STEP_STATUS[@]}"; do
        echo "$i:${PIPELINE_STEP_STATUS[$i]}"
    done > "$checkpoint_file"

    info "Pipeline checkpoint saved"
}

# Validate pipeline prerequisites
validate_pipeline_prerequisites() {
    print_header "PIPELINE PREREQUISITES VALIDATION"

    # Check all required scripts exist
    local required_scripts=(
        "./evaluation-setup-environment.sh"
        "./evaluation-record-modified-audio.sh"
        "./evaluation-process-mfcc.sh"
        "./evaluation-analyze-results.sh"
    )

    local missing_scripts=()

    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            missing_scripts+=("$script")
        elif [[ ! -x "$script" ]]; then
            warning "Script not executable: $script"
            info "Making executable..."
            chmod +x "$script" || error_log "Failed to make executable: $script"
        fi
    done

    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        error_exit "Missing required scripts: ${missing_scripts[*]}"
    fi

    # Validate core prerequisites
    local requirements=(
        "python3"
        "sox"
        "SwitchAudioSource"
        "working_directory"
    )

    if ! validate_prerequisites "${requirements[@]}"; then
        error_exit "Pipeline prerequisites validation failed"
    fi

    success "Pipeline prerequisites validation completed"
}

# Generate pipeline report
generate_pipeline_report() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - PIPELINE_START_TIME))
    local report_file="$WORKING_DIR/pipeline_report.txt"

    print_header "PIPELINE EXECUTION REPORT"

    {
        echo "SONGBIRD EVALUATION PIPELINE REPORT"
        echo "==================================="
        echo "Generated: $(date)"
        echo "Total Duration: ${total_duration} seconds ($((total_duration / 60)) minutes)"
        echo ""

        echo "PIPELINE STEPS:"
        echo "=============="
        for i in "${!PIPELINE_STEPS[@]}"; do
            local step="${PIPELINE_STEPS[$i]}"
            local status="${PIPELINE_STEP_STATUS[$i]}"
            local step_name=""

            case "$step" in
                "setup") step_name="Environment Setup" ;;
                "recording") step_name="Audio Recording" ;;
                "mfcc") step_name="MFCC Processing" ;;
                "analysis") step_name="Results Analysis" ;;
            esac

            echo "$((i+1)). $step_name: $status"
        done

        echo ""
        echo "RESULTS SUMMARY:"
        echo "==============="

        # Check for results files
        if [[ -f "$RESULTS_FILE" ]]; then
            local result_count=$(tail -n +2 "$RESULTS_FILE" 2>/dev/null | wc -l)
            echo "MFCC Results: $result_count entries in $RESULTS_FILE"
        else
            echo "MFCC Results: No results file found"
        fi

        if [[ -f "$RESULTS_FILE_STANDARDIZED" ]]; then
            local std_result_count=$(tail -n +2 "$RESULTS_FILE_STANDARDIZED" 2>/dev/null | wc -l)
            echo "Standardized Results: $std_result_count entries in $RESULTS_FILE_STANDARDIZED"
        else
            echo "Standardized Results: No standardized results file found"
        fi

        # Check for audio recordings
        local total_recordings=0
        for speaker in "${speakers[@]}"; do
            local speaker_dir="$WORKING_DIR/$speaker"
            if [[ -d "$speaker_dir" ]]; then
                local count=$(find "$speaker_dir" -name "*.wav" -type f 2>/dev/null | wc -l)
                total_recordings=$((total_recordings + count))
            fi
        done
        echo "Audio Recordings: $total_recordings WAV files"

        echo ""

        # Calculate success status
        local failed_steps=0
        for status in "${PIPELINE_STEP_STATUS[@]}"; do
            if [[ "$status" == "FAILED" ]]; then
                ((failed_steps++))
            fi
        done

        if [[ $failed_steps -eq 0 ]]; then
            echo "PIPELINE STATUS: COMPLETED SUCCESSFULLY"
        else
            echo "PIPELINE STATUS: COMPLETED WITH $failed_steps FAILED STEPS"
        fi

        echo ""
        echo "Generated by Songbird Evaluation Pipeline v$SONGBIRD_VERSION"

    } > "$report_file"

    success "Pipeline report saved: $report_file"

    # Show summary
    echo ""
    echo "Pipeline Execution Summary:"
    echo "=========================="
    local successful_steps=0
    for status in "${PIPELINE_STEP_STATUS[@]}"; do
        if [[ "$status" == "COMPLETED" ]]; then
            ((successful_steps++))
        fi
    done

    echo "✅ Successful Steps: $successful_steps/${#PIPELINE_STEPS[@]}"
    if [[ $failed_steps -gt 0 ]]; then
        echo "❌ Failed Steps: $failed_steps"
    fi
    echo "⏱️  Total Duration: $((total_duration / 60)) minutes"
    echo "📋 Full Report: $report_file"
}

# Main pipeline execution
main() {
    PIPELINE_START_TIME=$(date +%s)

    # Parse arguments
    parse_arguments "$@"

    # Show pipeline header
    print_header "SONGBIRD EVALUATION PIPELINE"

    echo "Pipeline Configuration:"
    echo "======================"
    echo "Resume Mode: $RESUME_MODE"
    echo "Force Mode: $FORCE_MODE"
    echo "Verbose Mode: $VERBOSE_OPERATIONS"
    echo "Skip Setup: $SKIP_SETUP"
    echo "Working Directory: $WORKING_DIR"
    echo ""

    # Validate prerequisites
    validate_pipeline_prerequisites

    # Load checkpoint if resuming
    load_pipeline_checkpoint

    # Show initial progress
    show_pipeline_progress
    estimate_remaining_time

    # Prepare step arguments
    local setup_args=""
    local recording_args=""
    local mfcc_args=""
    local analysis_args=""

    if [[ "$FORCE_MODE" == "true" ]]; then
        setup_args="$setup_args --force"
        recording_args="$recording_args --force"
        mfcc_args="$mfcc_args --force"
        analysis_args="$analysis_args --force"
    fi

    if [[ "$VERBOSE_OPERATIONS" == "true" ]]; then
        setup_args="$setup_args --verbose"
        recording_args="$recording_args --verbose"
        mfcc_args="$mfcc_args --verbose"
        analysis_args="$analysis_args --verbose"
    fi

    if [[ "$RESUME_MODE" == "true" ]]; then
        recording_args="$recording_args --resume"
    fi

    # Execute pipeline steps
    local step_failed=false

    # Step 1: Environment Setup
    if [[ "$SKIP_SETUP" != "true" && "${PIPELINE_STEP_STATUS[0]}" != "COMPLETED" ]]; then
        if ! run_pipeline_step 0 "Environment Setup" "./evaluation-setup-environment.sh" "$setup_args"; then
            step_failed=true
        fi
        save_pipeline_checkpoint
        show_pipeline_progress false
        estimate_remaining_time
    elif [[ "$SKIP_SETUP" == "true" ]]; then
        update_step_status 0 "COMPLETED"
        info "Skipping environment setup as requested"
    else
        info "Environment setup already completed, skipping"
    fi

    # Step 2: Audio Recording
    if [[ "$step_failed" != "true" && "${PIPELINE_STEP_STATUS[1]}" != "COMPLETED" ]]; then
        if ! run_pipeline_step 1 "Audio Recording" "./evaluation-record-modified-audio.sh" "$recording_args"; then
            step_failed=true
        fi
        save_pipeline_checkpoint
        show_pipeline_progress false
        estimate_remaining_time
    else
        info "Audio recording already completed, skipping"
    fi

    # Step 3: MFCC Processing
    if [[ "$step_failed" != "true" && "${PIPELINE_STEP_STATUS[2]}" != "COMPLETED" ]]; then
        if ! run_pipeline_step 2 "MFCC Processing" "./evaluation-process-mfcc.sh" "$mfcc_args"; then
            step_failed=true
        fi
        save_pipeline_checkpoint
        show_pipeline_progress false
        estimate_remaining_time
    else
        info "MFCC processing already completed, skipping"
    fi

    # Step 4: Results Analysis
    if [[ "$step_failed" != "true" && "${PIPELINE_STEP_STATUS[3]}" != "COMPLETED" ]]; then
        if ! run_pipeline_step 3 "Results Analysis" "./evaluation-analyze-results.sh" "$analysis_args"; then
            step_failed=true
        fi
        save_pipeline_checkpoint
        show_pipeline_progress false
    else
        info "Results analysis already completed, skipping"
    fi

    # Generate final report
    generate_pipeline_report

    # Final status
    if [[ "$step_failed" != "true" ]]; then
        success "🎉 Evaluation pipeline completed successfully!"

        echo ""
        echo "NEXT STEPS:"
        echo "=========="
        echo "1. Review results in: $RESULTS_FILE"
        echo "2. Check standardized results: $RESULTS_FILE_STANDARDIZED"
        echo "3. Examine detailed reports in: $WORKING_DIR"
        echo "4. Train your model using the generated data"

        exit 0
    else
        error_log "Pipeline failed at one or more steps"

        echo ""
        echo "RECOVERY OPTIONS:"
        echo "================"
        echo "1. Fix the issues and run: $0 --resume"
        echo "2. Run individual steps manually"
        echo "3. Check logs for detailed error information"

        exit 1
    fi
}

# Cleanup function
cleanup_pipeline() {
    info "Cleaning up pipeline execution..."
    save_pipeline_checkpoint
}

# Register cleanup
register_cleanup_function "cleanup_pipeline"

# Execute main function
main "$@"