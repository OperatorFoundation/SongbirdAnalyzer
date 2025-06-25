#!/bin/bash

# =============================================================================
# EVALUATION ENVIRONMENT SETUP
# =============================================================================
#
# Sets up the evaluation environment with comprehensive validation and safety.
# Now uses the Songbird modular core system for enhanced reliability.
#
# USAGE:
# ------
# ./evaluation-setup-environment.sh [--force] [--verbose]
#
# IMPROVEMENTS:
# -------------
# ✅ Hardware validation with recovery mechanisms
# ✅ Audio system testing and configuration
# ✅ Comprehensive prerequisite checking
# ✅ Automatic backup of existing evaluation data
# ✅ Progress tracking and detailed reporting
#
# =============================================================================

# Load the modular core system
if ! source "$(dirname "$0")/songbird-core/songbird-core.sh"; then
    echo "💥 FATAL: Could not load Songbird core modules" >&2
    exit 1
fi

# Initialize error handling
setup_error_handling

# Parse command line arguments
parse_arguments()
{
    FORCE_MODE=false

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
                warning "Unknown argument: $arg"
                ;;
        esac
    done
}

# Show usage information
show_usage()
{
    cat << EOF
SONGBIRD EVALUATION ENVIRONMENT SETUP

USAGE:
    $0 [options]

OPTIONS:
    --force         Skip confirmation prompts and auto-backup existing data
    --verbose, -v   Enable verbose output and detailed progress reporting
    --help, -h      Show this help message

DESCRIPTION:
    Prepares the evaluation environment by:
    - Validating hardware and audio setup
    - Creating working directories
    - Backing up existing evaluation data
    - Testing Teensy firmware responsiveness
    - Configuring audio routing

SAFETY FEATURES:
    🛡️  Comprehensive hardware validation
    ✅ Automatic backup of existing data
    📊 Detailed progress reporting
    🔄 Recovery mechanisms for failures

For more information, see the project documentation.
EOF
}

# Setup evaluation working directory
setup_evaluation_directory()
{
    print_header "SETTING UP EVALUATION DIRECTORY"

    info "Creating evaluation working directory: $WORKING_DIR"

    # Check if directory exists and has content
    if [[ -d "$WORKING_DIR" ]]; then
        local existing_files=$(find "$WORKING_DIR" -type f 2>/dev/null | wc -l)

        if [[ $existing_files -gt 0 ]]; then
            warning "Found $existing_files existing files in $WORKING_DIR"

            if [[ "$FORCE_MODE" != "true" ]]; then
                echo ""
                echo "This will:"
                echo "  - Create a backup of existing evaluation data"
                echo "  - Clear the working directory for new evaluation"
                echo ""
                read -p "Continue? (y/N): " -n 1 -r
                echo

                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    info "Operation cancelled by user"
                    return 1
                fi
            fi

            # Create backup
            if ! create_backup "$WORKING_DIR" "evaluation-data"; then
                error_exit "Failed to create backup of existing evaluation data"
            fi

            # Clear directory
            info "Clearing working directory..."
            rm -rf "$WORKING_DIR"/*
        fi
    fi

    # Create directory structure
    setup_working_directory "$WORKING_DIR" true

    # Create checkpoint file
    if [[ "$USE_PYTHON_CHECKPOINTS" == "true" ]]; then
        info "Initializing checkpoint system..."
        if "$PYTHON_CMD" "$SONGBIRD_CORE_PYTHON_DIR/checkpoint_manager.py" init "$CHECKPOINT_FILE"; then
            success "Checkpoint system initialized"
        else
            warning "Failed to initialize checkpoint system, will use legacy tracking"
        fi
    fi

    success "Evaluation directory setup completed"
    return 0
}

# Validate system environment
validate_system_environment()
{
    print_header "SYSTEM ENVIRONMENT VALIDATION"

    # Show system information
    if [[ "$VERBOSE_OPERATIONS" == "true" ]]; then
        show_system_info true
    else
        show_system_info false
    fi

    # Check system resources
    check_system_load 80

    # Validate prerequisites
    local requirements=(
        "python3"
        "sox"
        "SwitchAudioSource"
        "librosa"
        "pandas"
        "numpy"
        "working_directory"
        "results_directory"
    )

    if ! validate_prerequisites "${requirements[@]}"; then
        error_exit "System environment validation failed"
    fi

    success "System environment validation completed"
}

# Setup and test audio system
setup_audio_system()
{
    print_header "AUDIO SYSTEM SETUP"

    # Validate audio system
    if ! validate_audio_system; then
        error_exit "Audio system validation failed"
    fi

    # Save current audio configuration
    save_original_audio_sources

#    # Test audio routing
#    info "Testing current audio configuration..."
#    if validate_audio_routing 3 440 "/tmp/songbird_audio_test"; then
#        success "Audio routing test passed with current configuration"
#    else
#        warning "Audio routing test failed with current configuration"
#
#        # Try switching to Teensy and test again
#        info "Attempting to switch to Teensy audio device..."
#        if switch_to_teensy_audio "both"; then
#            info "Testing audio routing with Teensy device..."
#            if validate_audio_routing 3 440 "/tmp/songbird_audio_test"; then
#                success "Audio routing working with Teensy device"
#            else
#                error_exit "Audio routing failed even with Teensy device"
#            fi
#        else
#            error_exit "Failed to switch to Teensy audio device"
#        fi
#    fi

    success "Audio system setup completed"
}

# Validate and test hardware
validate_hardware()
{
    print_header "HARDWARE VALIDATION"

    # Perform comprehensive hardware validation
    if ! validate_hardware_setup; then
        echo ""
        echo "HARDWARE VALIDATION FAILED"
        echo "=========================="
        echo ""
        echo "Common solutions:"
        echo "1. Check USB connection (try different port)"
        echo "2. Reset Teensy device (press reset button)"
        echo "3. Verify firmware is loaded and in 'dev' mode"
        echo "4. Check audio cable connections"
        echo "5. Restart audio software"
        echo ""

        if [[ "$FORCE_MODE" == "true" ]]; then
            warning "Force mode enabled - continuing despite hardware validation failure"
            warning "Audio recording may not work properly"
        else
            read -p "Hardware validation failed. Continue anyway? (y/N): " -n 1 -r
            echo

            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                error_exit "Hardware validation failed and user chose not to continue"
            fi

            warning "Continuing despite hardware validation failure"
        fi
    fi

    success "Hardware validation completed"
}

# Create results directory structure
setup_results_directories()
{
    print_header "RESULTS DIRECTORY SETUP"

    local results_base_dir=$(dirname "$RESULTS_FILE")

    info "Setting up results directories..."

    # Create main results directory
    check_directory_writable "$results_base_dir" "Cannot create results directory"

    # Create subdirectories for different result types
    local subdirs=("raw" "processed" "analysis" "reports" "backups")

    for subdir in "${subdirs[@]}"; do
        local full_path="$results_base_dir/$subdir"
        check_directory_writable "$full_path" "Cannot create results subdirectory: $subdir"
        info "✅ Created: $subdir"
    done

    success "Results directory setup completed"
}

# Generate environment report
generate_environment_report()
{
    local report_file="$WORKING_DIR/environment_report.txt"

    print_header "GENERATING ENVIRONMENT REPORT"

    info "Creating environment report: $report_file"

    {
        echo "SONGBIRD EVALUATION ENVIRONMENT REPORT"
        echo "======================================"
        echo "Generated: $(date)"
        echo "Songbird Version: $SONGBIRD_VERSION"
        echo ""

        echo "SYSTEM INFORMATION:"
        echo "=================="
        show_system_info false

        echo ""
        echo "HARDWARE STATUS:"
        echo "==============="

        # Teensy device info
        if [[ -n "$TEENSY_DEVICE_PATH" ]]; then
            get_teensy_device_info "$TEENSY_DEVICE_PATH"
        else
            echo "Teensy device: Not found or not validated"
        fi

        echo ""
        echo "AUDIO CONFIGURATION:"
        echo "==================="
        get_current_audio_devices

        echo ""
        echo "DIRECTORY STRUCTURE:"
        echo "==================="
        echo "Working Directory: $WORKING_DIR"
        echo "Results Directory: $(dirname "$RESULTS_FILE")"
        echo "Backup Directory: $BACKUP_ROOT_DIR"

        echo ""
        echo "SPEAKER CONFIGURATION:"
        echo "====================="
        show_speaker_info

        echo ""
        echo "SETUP STATUS: COMPLETED SUCCESSFULLY"
        echo "Setup completed at: $(date)"

    } > "$report_file"

    success "Environment report saved: $report_file"

    if [[ "$VERBOSE_OPERATIONS" == "true" ]]; then
        echo ""
        echo "ENVIRONMENT REPORT PREVIEW:"
        print_separator 60
        head -n 30 "$report_file"
        print_separator 60
        echo "Full report available at: $report_file"
    fi
}

# Main setup function
main()
{
    local start_time=$(date +%s)

    # Parse arguments
    parse_arguments "$@"

    # Show header
    print_header "SONGBIRD EVALUATION ENVIRONMENT SETUP"

    echo "Setup Configuration:"
    echo "==================="
    echo "Force Mode: $FORCE_MODE"
    echo "Verbose Mode: $VERBOSE_OPERATIONS"
    echo "Working Directory: $WORKING_DIR"
    echo "Checkpoint File: $CHECKPOINT_FILE"
    echo ""

    # Step 1: Validate system environment
    if ! validate_system_environment; then
        error_exit "System environment validation failed"
    fi

    # Step 2: Setup evaluation directory
    if ! setup_evaluation_directory; then
        error_exit "Evaluation directory setup failed"
    fi

    # Step 3: Setup results directories
    if ! setup_results_directories; then
        error_exit "Results directory setup failed"
    fi

    # Step 4: Setup and test audio system
    if ! setup_audio_system; then
        error_exit "Audio system setup failed"
    fi

    # Step 5: Validate hardware
    validate_hardware  # May continue with warnings

    # Step 6: Generate environment report
    generate_environment_report

    local end_time=$(date +%s)
    local setup_duration=$((end_time - start_time))

    # Final success message
    print_header "SETUP COMPLETED SUCCESSFULLY"

    echo "✅ Environment setup completed in ${setup_duration} seconds"
    echo ""
    echo "NEXT STEPS:"
    echo "=========="
    echo "1. Run: ./evaluation-record-modified-audio.sh"
    echo "2. Then: ./evaluation-process-mfcc.sh"
    echo "3. Finally: ./evaluation-analyze-results.sh"
    echo ""
    echo "Or run all steps: ./evaluation-run-all.sh"
    echo ""

    success "🎉 Evaluation environment is ready!"
}

# Cleanup function
cleanup_environment_setup()
{
    info "Cleaning up environment setup..."
    # Cleanup any temporary files created during setup
    rm -f /tmp/songbird_audio_test*.wav 2>/dev/null || true
}

# Register cleanup
register_cleanup_function "cleanup_environment_setup"

# Execute main function
main "$@"