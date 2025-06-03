
#!/bin/bash
# =============================================================================
# SONGBIRD ANALYSIS PIPELINE
# =============================================================================
#
# Master orchestration script for the complete Songbird analysis workflow.
# Uses centralized configuration from songbird-common.sh.
#
# COMMANDS:
# ---------
# training   - Download audio, train model, prepare test files
# evaluation - Record modified audio and analyze results  
# quick      - Re-analyze existing recorded audio
# status     - Show pipeline status
# clean      - Remove all generated files
#
# WORKFLOW:
# ---------
# 1. ./songbird-pipeline.sh training
# 2. ./songbird-pipeline.sh evaluation  
# 3. ./songbird-pipeline.sh quick (optional re-analysis)
#
# =============================================================================

set -e  # Exit on any error

# Source centralized configuration and functions
source songbird-common.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Training-specific constants (different from evaluation)
TRAINING_RESULTS_FILE="results/training.csv"
TRAINING_WORKING_DIR="working-training"
TEST_DATA="results/testing"

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check for required Python scripts
    local required_scripts=("automfcc.py" "train.py" "evaluate.py" "predict.py")
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            print_error "Required script not found: $script"
            exit 1
        fi
    done
    
    # Check for required shell scripts
    local required_shell_scripts=("splitall.sh")
    for script in "${required_shell_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            print_error "Required shell script not found: $script"
            exit 1
        fi
    done
    
    # Create results directory if it doesn't exist
    mkdir -p results
    
    print_success "Prerequisites check passed"
}

# Training pipeline
run_training() {
    print_header "TRAINING PIPELINE"
    
    print_status "Step 1: Download and prepare audio data..."
    
    # Create speaker directories using centralized configuration
    for speaker_id in $(get_speakers); do
        mkdir -p "$SPEAKERS_DIR/$speaker_id"
    done

    # Download and extract audio files using centralized configuration
    print_status "Downloading LibriVox audio files..."
    
    for speaker_id in $(get_speakers); do
        speaker_url=$(get_speaker_url "$speaker_id")
        cleanup_files=$(get_speaker_cleanup_files "$speaker_id")
        
        if [ -n "$speaker_url" ]; then
            pushd "$SPEAKERS_DIR/$speaker_id" > /dev/null
            wget -nc "$speaker_url"
            for zip in *.zip; do
                if [ -f "$zip" ]; then
                    unzip -u "$zip"
                fi
            done
            
            # Clean up unwanted files if specified
            if [ -n "$cleanup_files" ]; then
                rm -f $cleanup_files
            fi
            
            popd > /dev/null
        fi
    done

    print_status "Step 2: Split audio files into segments..."
    ./splitall.sh "$SPEAKERS_DIR" "$TRAINING_WORKING_DIR"
    
    print_status "Step 3: Extract MFCC features..."
    python3 automfcc.py "$TRAINING_WORKING_DIR" "$TRAINING_RESULTS_FILE"
    
    print_status "Step 4: Standardize features..."
    python3 standardize_features.py training
    
    print_status "Step 5: Train model and create test set..."
    python3 train.py "$TRAINING_RESULTS_FILE" "$TEST_DATA" "$MODEL_FILE" "$TRAINING_WORKING_DIR"
    
    print_success "Training pipeline completed!"
    print_status "Generated files:"
    ls -la results/training* results/testing* "$MODEL_FILE" 2>/dev/null || true
}

# Evaluation pipeline
run_evaluation() {
    print_header "EVALUATION PIPELINE"
    
    # Check if training has been completed
    if [ ! -d "$FILES_DIR" ]; then
        print_error "No test files found. Run training first with: $0 training"
        exit 1
    fi
    
    if [ ! -f "$MODEL_FILE" ]; then
        print_error "No trained model found. Run training first with: $0 training"
        exit 1
    fi
    
    if [ ! -f "results/feature_dimensions.json" ]; then
        print_error "No feature dimensions reference found. Run training first with: $0 training"
        exit 1
    fi
    
    print_status "Step 1: Setup evaluation environment..."
    ./evaluation-setup-environment.sh
    
    print_status "Step 2: Record modified audio..."
    if command -v SwitchAudioSource &>/dev/null; then
        ./evaluation-record-modified-audio.sh
    else
        print_warning "SwitchAudioSource not found. Skipping audio recording."
        print_warning "Install with: brew install switchaudio-osx"
        print_warning "Or manually place recorded files in $WORKING_DIR/"
    fi
    
    print_status "Step 3: Extract MFCC features from modified audio..."
    ./evaluation-process-mfcc.sh
    
    print_status "Step 4: Standardize evaluation features..."
    python3 standardize_features.py evaluation
    
    print_status "Step 5: Analyze results..."
    ./evaluation-analyze-results.sh
    
    print_success "Evaluation pipeline completed!"
}

# Quick evaluation (skip recording, use existing modified audio)
run_evaluation_quick() {
    print_header "QUICK EVALUATION (Skip Recording)"
    
    # Check prerequisites
    if [ ! -d "$WORKING_DIR" ] || [ -z "$(ls -A "$WORKING_DIR" 2>/dev/null)" ]; then
        print_error "No modified audio found in $WORKING_DIR/. Run full evaluation first."
        exit 1
    fi
    
    print_status "Step 1: Extract MFCC features from existing modified audio..."
    ./evaluation-process-mfcc.sh
    
    print_status "Step 2: Standardize evaluation features..."
    python3 standardize_features.py evaluation
    
    print_status "Step 3: Analyze results..."
    ./evaluation-analyze-results.sh
    
    print_success "Quick evaluation completed!"
}

# Clean up generated files
cleanup() {
    print_header "CLEANUP"
    
    print_status "Removing generated files and directories..."
    
    # Remove working directories
    rm -rf "$TRAINING_WORKING_DIR" "$WORKING_DIR"
    
    # Remove result files
    rm -f results/*.csv results/*.json
    
    # Remove model
    rm -f "$MODEL_FILE"
    
    # Remove tracking files
    rm -f "$TRACKING_FILE"
    
    print_success "Cleanup completed!"
}

# Show status of the pipeline
show_status() {
    print_header "PIPELINE STATUS"
    
    echo "📂 File Status:"
    echo "  Training data ready: $([ -d "$SPEAKERS_DIR/$(echo $(get_speakers) | cut -d' ' -f1)" ] && echo "✅" || echo "❌")"
    echo "  Model trained: $([ -f "$MODEL_FILE" ] && echo "✅" || echo "❌")"
    echo "  Test files prepared: $([ -d "$FILES_DIR" ] && echo "✅" || echo "❌")"
    echo "  Feature dimensions set: $([ -f "results/feature_dimensions.json" ] && echo "✅" || echo "❌")"
    echo "  Modified audio recorded: $([ -d "$WORKING_DIR" ] && [ -n "$(ls -A "$WORKING_DIR" 2>/dev/null)" ] && echo "✅" || echo "❌")"
    
    echo ""
    echo "📊 Available Files:"
    if [ -d "results" ]; then
        ls -la results/ 2>/dev/null || echo "  No results files found"
    else
        echo "  No results directory found"
    fi
    
    if [ -f "$MODEL_FILE" ]; then
        echo "  Model: $MODEL_FILE ($(stat -f%z "$MODEL_FILE" 2>/dev/null || stat --format=%s "$MODEL_FILE" 2>/dev/null || echo "unknown") bytes)"
    fi
    
    echo ""
    echo "🔧 Configuration:"
    echo "  Speakers configured: $(get_speaker_count)"
    echo "  Audio segment length: ${MAX_TIME}s"
    echo "  Device name: $DEVICE_NAME"
    show_speaker_config
}

# Main script logic
main() {
    COMMAND=${1:-"help"}
    
    case $COMMAND in
        "full")
            check_prerequisites
            run_training
            echo ""
            print_warning "Ready for evaluation! Connect your Teensy device and run:"
            print_warning "  $0 evaluation"
            ;;
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
        "help"|*)
            echo "Songbird Analysis Pipeline"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  full       - Run complete training pipeline (stops before evaluation)"
            echo "  training   - Run only the training pipeline"
            echo "  evaluation - Run evaluation with Teensy device (requires training first)"
            echo "  quick      - Re-run evaluation analysis on existing recorded audio"
            echo "  status     - Show current pipeline status"
            echo "  clean      - Remove all generated files and start fresh"
            echo "  help       - Show this help message"
            echo ""
            echo "Typical workflow:"
            echo "  1. $0 training          # Download, process, and train model"
            echo "  2. $0 evaluation        # Record and analyze modified audio"
            echo "  3. $0 quick             # Re-analyze if needed"
            echo ""
            echo "For a fresh start:"
            echo "  $0 clean && $0 full"
            ;;
    esac
}

# Run the main function
main "$@"