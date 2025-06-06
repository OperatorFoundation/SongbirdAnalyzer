#!/bin/bash

# =============================================================================
# SONGBIRD ANALYSIS PIPELINE
# =============================================================================
#
# Master orchestration script for the complete Songbird analysis workflow.
#
# COMMANDS:
# ---------
# training   - Download audio, train model, prepare test files
# evaluation - Record modified audio and analyze results  
# quick      - Re-analyze existing recorded audio
# status     - Show pipeline status and system health
# clean      - Remove all generated files with backup options
# doctor     - Comprehensive system health check and repair
#
# WORKFLOW:
# ---------
# 1. ./songbird-pipeline.sh training
# 2. ./songbird-pipeline.sh evaluation  
# 3. ./songbird-pipeline.sh quick (optional re-analysis)
#
# =============================================================================

set -e  # Exit on any error

# Load core system
if ! source "$(dirname "$0")/songbird-core/songbird-core.sh"; then
    echo "💥 FATAL: Could not load Songbird core modules" >&2
    echo "   Make sure songbird-core directory exists with required modules" >&2
    exit 1
fi

# Initialize error handling
setup_error_handling

# Ensure we're in the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Pipeline-specific configuration (not in songbird-config.sh)
TRAINING_RESULTS_FILE="results/training.csv"
TRAINING_WORKING_DIR="working-training"
TEST_DATA="results/testing"
PIPELINE_CHECKPOINT_FILE="$SCRIPT_DIR/.songbird_pipeline_checkpoint"

# Pipeline state
PIPELINE_START_TIME=""
COMMAND=""
FORCE_FLAG=""
VERBOSE_FLAG=""

# Parse command line arguments
parse_pipeline_arguments() {
    COMMAND=""
    FORCE_FLAG=""
    VERBOSE_FLAG=""

    for arg in "$@"; do
        case $arg in
            --force)
                FORCE_FLAG="--force"
                FORCE_MODE=true
                ;;
            --verbose|-v)
                VERBOSE_FLAG="--verbose"
                VERBOSE_OPERATIONS=true
                ;;
            --help|-h)
                show_pipeline_usage
                exit 0
                ;;
            *)
                if [[ -z "$COMMAND" ]]; then
                    COMMAND="$arg"
                fi
                ;;
        esac
    done

    COMMAND=${COMMAND:-"help"}
}

# Show pipeline usage
show_pipeline_usage() {
    cat << EOF
SONGBIRD ANALYSIS PIPELINE

USAGE:
    $0 [command] [options]

COMMANDS:
    training    Run complete training pipeline (download, split, train model)
    evaluation  Run evaluation with Teensy device (requires training first)
    quick       Re-run evaluation analysis on existing recorded audio
    status      Show current pipeline status and system health
    clean       Remove all generated files with backup options
    doctor      Comprehensive system health check and repair
    help        Show this help message

OPTIONS:
    --force     Skip confirmation prompts and overwrite existing files
    --verbose   Enable verbose output and detailed progress reporting
    --help      Show this help message

WORKFLOW:
    1. $0 training     # Download audio, train model, prepare test files
    2. $0 evaluation   # Record modified audio and analyze results
    3. $0 quick        # Re-analyze existing audio (optional)

EXAMPLES:
    $0 training --verbose           # Verbose training
    $0 evaluation --force          # Force evaluation (overwrite)
    $0 status                      # Check system status
    $0 doctor                      # System health check

For more information, see the project documentation.
EOF
}

# Check comprehensive prerequisites
check_prerequisites()
{
    print_header "PREREQUISITES VALIDATION"

    info "Checking pipeline prerequisites..."

    # Check for required Python scripts
    local required_scripts=("automfcc.py" "train.py" "evaluate.py" "predict.py" "standardize_features.py")
    local missing_scripts=()

    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            missing_scripts+=("$script")
        fi
    done

    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        error_exit "Required Python scripts not found: ${missing_scripts[*]}"
    fi

    # Check for required shell scripts (now using new versions)
    local required_shell_scripts=("splitall.sh")
    for script in "${required_shell_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            error_exit "Required shell script not found: $script"
        elif [[ ! -x "$script" ]]; then
            warning "Script not executable: $script"
            chmod +x "$script" || error_exit "Failed to make executable: $script"
        fi
    done

    # Validate core prerequisites
    local core_requirements=(
        "python3"
        "wget"
        "unzip"
        "working_directory"
        "results_directory"
    )

    if ! validate_prerequisites "${core_requirements[@]}"; then
        error_exit "Core prerequisites validation failed"
    fi

    # Create results directory if it doesn't exist
    check_directory_writable "results" "Cannot create results directory"

    success "Prerequisites validation completed"
}

# Save pipeline checkpoint
save_pipeline_checkpoint()
{
    local stage="$1"
    local status="$2"
    local timestamp=$(date +%s)

    cat > "$PIPELINE_CHECKPOINT_FILE" << EOF
{
    "last_stage": "$stage",
    "status": "$status",
    "timestamp": $timestamp,
    "command": "$COMMAND",
    "force_mode": $FORCE_MODE,
    "verbose_mode": $VERBOSE_OPERATIONS
}
EOF

    info "Pipeline checkpoint saved: $stage ($status)"
}

# Load pipeline checkpoint
load_pipeline_checkpoint()
{
    if [[ -f "$PIPELINE_CHECKPOINT_FILE" ]]; then
        local last_stage=$(python3 -c "
import json
try:
    with open('$PIPELINE_CHECKPOINT_FILE', 'r') as f:
        data = json.load(f)
    print(data.get('last_stage', ''))
except:
    print('')
" 2>/dev/null)

        if [[ -n "$last_stage" ]]; then
            info "Previous pipeline stage: $last_stage"
            return 0
        fi
    fi
    return 1
}

# Training pipeline with enhanced error handling
run_training()
{
    print_header "TRAINING PIPELINE"

    save_pipeline_checkpoint "training" "started"
    local training_start_time=$(date +%s)

    # Step 1: Download and prepare audio data
    info "Step 1: Download and prepare audio data..."

    # Create speaker directories using centralized configuration
    for speaker_id in "${speakers[@]}"; do
        check_directory_writable "$SPEAKERS_DIR/$speaker_id" "Cannot create speaker directory for $speaker_id"
    done

    # Download and extract audio files
    info "Downloading LibriVox audio files..."

    local download_success=true
    for speaker_index in "${!speakers[@]}"; do
        local speaker_id="${speakers[speaker_index]}"
        local speaker_url="${speaker_urls[speaker_index]}"
        local cleanup_files="${speaker_cleanup_files[speaker_index]:-}"

        info "Processing speaker $speaker_id..."

        if [[ -n "$speaker_url" ]]; then
            pushd "$SPEAKERS_DIR/$speaker_id" > /dev/null

            # Download with error handling
            if ! run_with_error_handling "Downloading $speaker_url" wget -nc "$speaker_url"; then
                warning "Download failed for speaker $speaker_id"
                download_success=false
                popd > /dev/null
                continue
            fi

            # Extract zip files
            for zip in *.zip; do
                if [[ -f "$zip" ]]; then
                    if ! run_with_error_handling "Extracting $zip" unzip -u "$zip"; then
                        warning "Extraction failed for $zip"
                    fi
                fi
            done

            # Clean up unwanted files if specified
            # TODO: Consider standardizing the total number of mp3s across speakers or at least a max limit
            if [[ -n "$cleanup_files" ]]; then
                info "Cleaning up unwanted files: $cleanup_files"
                rm -f $cleanup_files 2>/dev/null || true
            fi

            popd > /dev/null
        else
            warning "No URL configured for speaker $speaker_id"
        fi
    done

    if [[ "$download_success" != "true" ]]; then
        warning "Some downloads failed, but continuing with available data"
    fi

    # Step 2: Split audio files into segments
    info "Step 2: Split audio files into segments..."
    if ! run_with_error_handling "Audio splitting" ./splitall.sh "$SPEAKERS_DIR" "$TRAINING_WORKING_DIR" $FORCE_FLAG $VERBOSE_FLAG; then
        error_exit "Audio splitting failed"
    fi

    # Step 3: Extract MFCC features
    info "Step 3: Extract MFCC features..."
    if ! run_with_error_handling "MFCC extraction" python3 automfcc.py "$TRAINING_WORKING_DIR" "$TRAINING_RESULTS_FILE"; then
        error_exit "MFCC extraction failed"
    fi

    # Step 4: Standardize features
    info "Step 4: Standardize features..."
    if ! run_with_error_handling "Feature standardization" python3 standardize_features.py training; then
        error_exit "Feature standardization failed"
    fi

    # Step 5: Train model and create test set
    info "Step 5: Train model and create test set..."
    if ! run_with_error_handling "Model training" python3 train.py "$TRAINING_RESULTS_FILE" "$TEST_DATA" "$MODEL_FILE" "$TRAINING_WORKING_DIR"; then
        error_exit "Model training failed"
    fi

    local training_end_time=$(date +%s)
    local training_duration=$((training_end_time - training_start_time))

    save_pipeline_checkpoint "training" "completed"

    success "🎉 Training pipeline completed in $((training_duration / 60)) minutes!"

    info "Generated files:"
    ls -la results/training* results/testing* "$MODEL_FILE" 2>/dev/null || true

    echo ""
    echo "NEXT STEPS:"
    echo "=========="
    echo "1. Connect your Teensy device"
    echo "2. Run: $0 evaluation $FORCE_FLAG $VERBOSE_FLAG"
}

# Evaluation pipeline with enhanced integration
run_evaluation()
{
    print_header "EVALUATION PIPELINE"

    save_pipeline_checkpoint "evaluation" "started"

    # Check if training has been completed
    if [[ ! -d "$FILES_DIR" ]]; then
        error_exit "No test files found. Run training first with: $0 training"
    fi

    if [[ ! -f "$MODEL_FILE" ]]; then
        error_exit "No trained model found. Run training first with: $0 training"
    fi

    if [[ ! -f "results/feature_dimensions.json" ]]; then
        error_exit "No feature dimensions reference found. Run training first with: $0 training"
    fi

    # Use the new modernized evaluation pipeline
    info "Running complete evaluation pipeline..."

    if ! run_with_error_handling "Complete evaluation pipeline" ./evaluation-run-all.sh $FORCE_FLAG $VERBOSE_FLAG; then
        error_exit "Evaluation pipeline failed"
    fi

    save_pipeline_checkpoint "evaluation" "completed"
    success "🎉 Evaluation pipeline completed successfully!"
}

# Quick evaluation (skip recording, use existing modified audio)
run_evaluation_quick()
{
    print_header "QUICK EVALUATION (Skip Recording)"

    save_pipeline_checkpoint "quick_evaluation" "started"

    # Check prerequisites
    if [[ ! -d "$WORKING_DIR" ]] || [[ -z "$(ls -A "$WORKING_DIR" 2>/dev/null)" ]]; then
        error_exit "No modified audio found in $WORKING_DIR/. Run full evaluation first."
    fi

    info "Step 1: Extract MFCC features from existing modified audio..."
    if ! run_with_error_handling "MFCC processing" ./evaluation-process-mfcc.sh $FORCE_FLAG $VERBOSE_FLAG; then
        error_exit "MFCC processing failed"
    fi

    info "Step 2: Standardize evaluation features..."
    if ! run_with_error_handling "Feature standardization" python3 standardize_features.py evaluation; then
        error_exit "Feature standardization failed"
    fi

    info "Step 3: Analyze results..."
    if ! run_with_error_handling "Results analysis" ./evaluation-analyze-results.sh $FORCE_FLAG $VERBOSE_FLAG; then
        error_exit "Results analysis failed"
    fi

    save_pipeline_checkpoint "quick_evaluation" "completed"
    success "🎉 Quick evaluation completed successfully!"
}

# Enhanced cleanup with backup options
cleanup() {
    print_header "CLEANUP"

    echo "This will remove all generated files and directories:"
    echo "  - Working directories: $TRAINING_WORKING_DIR, $WORKING_DIR"
    echo "  - Result files: results/*.csv, results/*.json"
    echo "  - Model file: $MODEL_FILE"
    echo "  - Tracking files: $TRACKING_FILE"
    echo "  - Checkpoint files: $PIPELINE_CHECKPOINT_FILE"
    echo ""

    if [[ "$FORCE_MODE" != "true" ]]; then
        read -p "Create backup before cleanup? (Y/n): " -n 1 -r
        echo

        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            info "Creating backup before cleanup..."

            # Create comprehensive backup
            local backup_name="songbird-pipeline-cleanup-$(date +%Y%m%d-%H%M%S)"
            local backup_dir="$BACKUP_ROOT_DIR/$backup_name"

            mkdir -p "$backup_dir"

            # Backup working directories
            if [[ -d "$TRAINING_WORKING_DIR" ]]; then
                cp -r "$TRAINING_WORKING_DIR" "$backup_dir/" 2>/dev/null || true
            fi

            if [[ -d "$WORKING_DIR" ]]; then
                cp -r "$WORKING_DIR" "$backup_dir/" 2>/dev/null || true
            fi

            # Backup results
            if [[ -d "results" ]]; then
                cp -r "results" "$backup_dir/" 2>/dev/null || true
            fi

            # Backup model
            if [[ -f "$MODEL_FILE" ]]; then
                cp "$MODEL_FILE" "$backup_dir/" 2>/dev/null || true
            fi

            success "Backup created: $backup_dir"
        fi

        echo ""
        read -p "Continue with cleanup? (y/N): " -n 1 -r
        echo

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Cleanup cancelled"
            return 0
        fi
    fi

    info "Removing generated files and directories..."

    # Remove working directories
    rm -rf "$TRAINING_WORKING_DIR" "$WORKING_DIR"

    # Remove result files
    rm -f results/*.csv results/*.json

    # Remove model
    rm -f "$MODEL_FILE"

    # Remove tracking files
    rm -f "$TRACKING_FILE"

    # Remove checkpoint files
    rm -f "$PIPELINE_CHECKPOINT_FILE"

    # Remove Python cache
    find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.pyc" -type f -delete 2>/dev/null || true

    success "🗑️  Cleanup completed!"
}

# Enhanced status with health monitoring
show_status() {
    print_header "PIPELINE STATUS & SYSTEM HEALTH"

    # Show system information
    show_system_info false

    echo ""
    echo "📂 Pipeline File Status:"
    echo "======================"

    # Check training data
    local training_ready=false
    for speaker in "${speakers[@]}"; do
        if [[ -d "$SPEAKERS_DIR/$speaker" ]] && [[ -n "$(ls -A "$SPEAKERS_DIR/$speaker" 2>/dev/null)" ]]; then
            training_ready=true
            break
        fi
    done

    echo "  Training data ready: $(if $training_ready; then echo "✅"; else echo "❌"; fi)"
    echo "  Model trained: $(if [[ -f "$MODEL_FILE" ]]; then echo "✅"; else echo "❌"; fi)"
    echo "  Test files prepared: $(if [[ -d "$FILES_DIR" ]]; then echo "✅"; else echo "❌"; fi)"
    echo "  Feature dimensions set: $(if [[ -f "results/feature_dimensions.json" ]]; then echo "✅"; else echo "❌"; fi)"
    echo "  Modified audio recorded: $(if [[ -d "$WORKING_DIR" ]] && [[ -n "$(ls -A "$WORKING_DIR" 2>/dev/null)" ]]; then echo "✅"; else echo "❌"; fi)"

    echo ""
    echo "📊 Available Files:"
    echo "=================="
    if [[ -d "results" ]]; then
        local result_files=$(ls -la results/ 2>/dev/null)
        if [[ -n "$result_files" ]]; then
            echo "$result_files"
        else
            echo "  No results files found"
        fi
    else
        echo "  No results directory found"
    fi

    if [[ -f "$MODEL_FILE" ]]; then
        local model_size=$(get_file_size "$MODEL_FILE")
        echo "  Model: $MODEL_FILE ($model_size)"
    fi

    echo ""
    echo "🔧 Configuration:"
    echo "================"
    echo "  Speakers configured: ${#speakers[@]}"
    echo "  Audio segment length: ${MAX_TIME}s"
    echo "  Device name: $DEVICE_NAME"
    echo "  Songbird version: $SONGBIRD_VERSION"

    # Show speaker configuration
    show_speaker_info

    # Show checkpoint status
    echo ""
    echo "📋 Pipeline Checkpoint:"
    echo "======================"
    if load_pipeline_checkpoint; then
        if [[ -f "$PIPELINE_CHECKPOINT_FILE" ]]; then
            cat "$PIPELINE_CHECKPOINT_FILE" | jq -r '
                "  Last stage: \(.last_stage)",
                "  Status: \(.status)",
                "  Timestamp: \(.timestamp | strftime("%Y-%m-%d %H:%M:%S"))",
                "  Force mode: \(.force_mode)",
                "  Verbose mode: \(.verbose_mode)"
            ' 2>/dev/null || cat "$PIPELINE_CHECKPOINT_FILE"
        fi
    else
        echo "  No checkpoint found"
    fi

    # Hardware status (if applicable)
    echo ""
    echo "🔌 Hardware Status:"
    echo "=================="
    if [[ "$REQUIRE_HARDWARE_VALIDATION" == "true" ]]; then
        if validate_hardware_setup 1 false; then
            echo "  Teensy device: ✅ Connected and responsive"
            if [[ -n "$TEENSY_DEVICE_PATH" ]]; then
                get_teensy_device_info "$TEENSY_DEVICE_PATH"
            fi
        else
            echo "  Teensy device: ❌ Not found or not responsive"
        fi

        if validate_audio_system false; then
            echo "  Audio system: ✅ Available"
        else
            echo "  Audio system: ❌ Not available or not configured"
        fi
    else
        echo "  Hardware validation disabled"
    fi
}

# Comprehensive system health check and repair
run_doctor() {
    print_header "SONGBIRD SYSTEM DOCTOR"

    info "Running comprehensive system health check..."

    # Check 1: Core prerequisites
    echo ""
    echo "🔍 Checking Core Prerequisites:"
    echo "=============================="

    local core_requirements=(
        "python3"
        "sox"
        "wget"
        "unzip"
        "jq"
        "SwitchAudioSource"
    )

    local failed_requirements=()
    for req in "${core_requirements[@]}"; do
        if validate_single_prerequisite "$req" false; then
            echo "  ✅ $req: Available"
        else
            echo "  ❌ $req: Missing"
            failed_requirements+=("$req")
        fi
    done

    # Check 2: Python packages
    echo ""
    echo "🐍 Checking Python Environment:"
    echo "==============================="

    local python_packages=("librosa" "pandas" "numpy" "scikit-learn" "matplotlib")
    local missing_packages=()

    for package in "${python_packages[@]}"; do
        if python3 -c "import $package" 2>/dev/null; then
            echo "  ✅ $package: Available"
        else
            echo "  ❌ $package: Missing"
            missing_packages+=("$package")
        fi
    done

    # Check 3: File permissions and directory structure
    echo ""
    echo "📁 Checking File System:"
    echo "======================="

    local directories=("results" "$SPEAKERS_DIR" "$BACKUP_ROOT_DIR")
    for dir in "${directories[@]}"; do
        if check_directory_writable "$dir" "" false; then
            echo "  ✅ $dir: Writable"
        else
            echo "  ❌ $dir: Not writable"
            info "  Attempting to create: $dir"
            mkdir -p "$dir" 2>/dev/null && echo "  ✅ Created successfully" || echo "  ❌ Failed to create"
        fi
    done

    # Check 4: Hardware (if enabled)
    if [[ "$REQUIRE_HARDWARE_VALIDATION" == "true" ]]; then
        echo ""
        echo "🔌 Checking Hardware:"
        echo "===================="

        if validate_hardware_setup 1 false; then
            echo "  ✅ Teensy device: Connected and responsive"
        else
            echo "  ❌ Teensy device: Not found or not responsive"
            echo "  💡 Solutions:"
            echo "     - Check USB connection"
            echo "     - Press reset button on Teensy"
            echo "     - Verify firmware is loaded"
        fi

        if validate_audio_system false; then
            echo "  ✅ Audio system: Available"
        else
            echo "  ❌ Audio system: Issues detected"
            echo "  💡 Solutions:"
            echo "     - Check audio device connections"
            echo "     - Restart audio services"
            echo "     - Verify SwitchAudioSource installation"
        fi
    fi

    # Generate repair suggestions
    echo ""
    echo "🛠️  Repair Suggestions:"
    echo "======================"

    if [[ ${#failed_requirements[@]} -gt 0 ]]; then
        echo "Missing system prerequisites:"
        for req in "${failed_requirements[@]}"; do
            case "$req" in
                "SwitchAudioSource")
                    echo "  Install: brew install switchaudio-osx"
                    ;;
                "sox")
                    echo "  Install: brew install sox"
                    ;;
                "jq")
                    echo "  Install: brew install jq"
                    ;;
                *)
                    echo "  Install: $req (check your package manager)"
                    ;;
            esac
        done
    fi

    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        echo "Missing Python packages:"
        echo "  Install: pip3 install ${missing_packages[*]}"
    fi

    # Overall health status
    echo ""
    local total_issues=$((${#failed_requirements[@]} + ${#missing_packages[@]}))

    if [[ $total_issues -eq 0 ]]; then
        success "🎉 System health check passed! No issues found."
    else
        warning "⚠️  System health check found $total_issues issues that need attention."
        echo ""
        echo "After fixing the issues above, run:"
        echo "  $0 doctor"
        echo "to verify the fixes."
    fi
}

# Main script logic
main()
{
    PIPELINE_START_TIME=$(date +%s)

    # Parse command line arguments
    parse_pipeline_arguments "$@"

    # Show pipeline header
    print_header "SONGBIRD ANALYSIS PIPELINE"

    echo "Pipeline Configuration:"
    echo "======================"
    echo "Command: $COMMAND"
    echo "Force Mode: $FORCE_MODE"
    echo "Verbose Mode: $VERBOSE_OPERATIONS"
    echo "Songbird Version: $SONGBIRD_VERSION"
    echo ""

    case $COMMAND in
        "training")
            check_prerequisites
            run_training
            ;;
        "evaluation")
            check_prerequisites
            run_evaluation
            ;;
        "eval-quick"|"quick")
            check_prerequisites
            run_evaluation_quick
            ;;
        "status")
            show_status
            ;;
        "clean"|"cleanup")
            cleanup
            ;;
        "doctor")
            run_doctor
            ;;
        "help"|*)
            show_pipeline_usage
            ;;
    esac
}

# Cleanup function
cleanup_pipeline()
{
    info "Cleaning up pipeline execution..."
    # Save final checkpoint if needed
    if [[ -n "$COMMAND" && "$COMMAND" != "help" && "$COMMAND" != "status" ]]; then
        save_pipeline_checkpoint "$COMMAND" "interrupted"
    fi
}

# Register cleanup
register_cleanup_function "cleanup_pipeline"

# Execute main function
main "$@"