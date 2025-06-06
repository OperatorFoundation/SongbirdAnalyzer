#!/bin/bash

# =============================================================================
# EVALUATION RESULTS ANALYSIS
# =============================================================================
#
# Analyzes MFCC features and evaluates speaker identification performance
# using trained machine learning models. This script represents the final
# stage of the evaluation pipeline, providing comprehensive analysis and
# reporting of system performance.
#
# FUNCTION:
# ---------
# - Loads MFCC features from evaluation.csv
# - Applies trained speaker identification models
# - Generates performance metrics and analysis reports
# - Creates visualizations and statistical summaries
# - Evaluates impact of audio modifications on accuracy
#
# PREREQUISITES:
# --------------
# - results/evaluation.csv with extracted MFCC features
# - Trained machine learning models (songbird.pkl)
# - Python environment with scikit-learn and analysis libraries
#
# OUTPUT:
# -------
# - Detailed performance analysis reports
# - Statistical summaries and metrics
# - Visualization outputs (if enabled)
# - Standardized feature datasets
#
# INTEGRATION:
# ------------
# Final stage of evaluation pipeline
# Called by evaluation-run-all.sh after MFCC processing
# Integrates with trained models from training pipeline
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
readonly EVALUATION_SCRIPT_NAME="evaluate.py"
readonly STANDARDIZE_SCRIPT_NAME="standardize_features.py"
readonly PREDICT_SCRIPT_NAME="predict.py"
readonly MINIMUM_SAMPLES_THRESHOLD=10
readonly ANALYSIS_REPORT_SUFFIX="_analysis_report.txt"

# Analysis configuration
GENERATE_STANDARDIZED_FEATURES=true
RUN_PREDICTION_ANALYSIS=true
CREATE_DETAILED_REPORTS=true

# Parse command line arguments
parse_arguments()
{
    FORCE_MODE=false
    VERBOSE_OPERATIONS=false

    for arg in "$@"
    do
        case $arg in
            --force)
                FORCE_MODE=true
                ;;
            --verbose|-v)
                VERBOSE_OPERATIONS=true
                ;;
            --no-standardize)
                GENERATE_STANDARDIZED_FEATURES=false
                ;;
            --no-predict)
                RUN_PREDICTION_ANALYSIS=false
                ;;
            --basic)
                CREATE_DETAILED_REPORTS=false
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
SONGBIRD EVALUATION RESULTS ANALYSIS

USAGE:
    $0 [options]

OPTIONS:
    --force          Skip confirmation prompts and overwrite existing results
    --verbose, -v    Enable verbose output and detailed progress reporting
    --no-standardize Skip feature standardization step
    --no-predict     Skip prediction analysis step
    --basic          Generate basic reports only (skip detailed analysis)
    --help, -h       Show this help message

DESCRIPTION:
    Analyzes MFCC features extracted from modified audio recordings and
    evaluates speaker identification performance. Generates comprehensive
    reports on system accuracy and the impact of audio modifications.

PREREQUISITES:
    📊 results/evaluation.csv - MFCC features from evaluation-process-mfcc.sh
    🤖 Trained machine learning models (songbird.pkl)
    🐍 Python environment with required analysis libraries

ANALYSIS FEATURES:
    📈 Performance metrics calculation
    📊 Statistical analysis and reporting
    🎯 Accuracy evaluation across modification modes
    📋 Detailed breakdown by speaker and mode
    🔄 Feature standardization and normalization

OUTPUT FILES:
    📊 Standardized feature datasets
    📈 Performance analysis reports
    🎯 Prediction accuracy summaries
    📋 Detailed statistical breakdowns

For more information, see the project documentation.
EOF
}

# Validate environment and prerequisites
validate_environment()
{
    print_header "ANALYSIS PREREQUISITES VALIDATION"

    # Check core prerequisites
    local requirements=(
        "python3"
        "working_directory"
    )

    if ! validate_prerequisites "${requirements[@]}"
    then
        error_exit "Environment validation failed. Please install missing prerequisites."
    fi

    # Validate required Python scripts
    local required_scripts=("$EVALUATION_SCRIPT_NAME")

    if [[ "$GENERATE_STANDARDIZED_FEATURES" == "true" ]]
    then
        required_scripts+=("$STANDARDIZE_SCRIPT_NAME")
    fi

    if [[ "$RUN_PREDICTION_ANALYSIS" == "true" ]]
    then
        required_scripts+=("$PREDICT_SCRIPT_NAME")
    fi

    for script in "${required_scripts[@]}"
    do
        if [[ ! -f "./$script" ]]
        then
            error_exit "Required script not found: $script. This script is needed for analysis."
        fi

        if [[ ! -x "./$script" ]]
        then
            warning "$script is not executable. Attempting to fix..."
            if ! chmod +x "./$script"
            then
                error_exit "Failed to make $script executable"
            fi
            success "Made $script executable"
        fi
    done

    success "Environment validation completed successfully"
}

# Validate input results file
validate_results_file()
{
    local results_file="$1"

    info "Validating results file: $results_file"

    # Check if results file exists
    check_file_readable "$results_file" "Results file not accessible"

    # Validate file format and content
    local line_count
    line_count=$(wc -l < "$results_file" 2>/dev/null || echo "0")

    if [[ $line_count -le 1 ]]
    then
        error_exit "Results file appears to be empty or only contains header: $line_count lines"
    fi

    if [[ $line_count -lt $MINIMUM_SAMPLES_THRESHOLD ]]
    then
        warning "Results file has very few samples: $line_count lines"
        warning "Analysis may not be statistically significant"

        if [[ "$FORCE_MODE" != "true" ]]
        then
            if ! confirm_action "Continue with analysis despite low sample count?"
            then
                error_exit "Analysis cancelled due to insufficient data"
            fi
        fi
    fi

    info "✅ Results file contains $line_count lines (including header)"

    # Validate CSV structure
    local header_line
    header_line=$(head -n 1 "$results_file" 2>/dev/null)

    # Check for expected columns
    local required_columns=("speaker")
    local missing_columns=()

    for column in "${required_columns[@]}"
    do
        if [[ "$header_line" != *"$column"* ]]
        then
            missing_columns+=("$column")
        fi
    done

    if [[ ${#missing_columns[@]} -gt 0 ]]
    then
        error_exit "Missing required columns in results file: ${missing_columns[*]}"
    fi

    success "Results file validation completed"
}

# Validate trained model availability
validate_model_file()
{
    local model_file="$1"

    if [[ "$RUN_PREDICTION_ANALYSIS" != "true" ]]
    then
        info "Skipping model validation (prediction analysis disabled)"
        return 0
    fi

    info "Validating trained model: $model_file"

    check_file_readable "$model_file" "Trained model file not accessible"

    # Check model file size (basic validation)
    local model_size
    model_size=$(get_file_size "$model_file")

    if [[ $model_size -lt 1024 ]]
    then
        warning "Model file seems very small: $model_size bytes"
        warning "Model may be corrupted or incomplete"
    else
        info "✅ Model file size: $model_size bytes"
    fi

    success "Model file validation completed"
}

# Execute basic evaluation and data preparation
execute_basic_evaluation()
{
    local results_file="$1"
    local output_prefix="$2"

    print_header "BASIC EVALUATION AND DATA PREPARATION"

    info "Executing basic evaluation with evaluate.py..."
    info "Input: $results_file"
    info "Output prefix: $output_prefix"

    # Run evaluate.py to prepare data for analysis
    if run_with_error_handling "Basic evaluation" \
        python3 "./$EVALUATION_SCRIPT_NAME" "$results_file" "$output_prefix"
    then
        success "Basic evaluation completed successfully"

        # Validate generated files
        local expected_files=("${output_prefix}_mfccs.csv" "${output_prefix}_speakers.csv")

        for expected_file in "${expected_files[@]}"
        do
            if [[ -f "$expected_file" ]]
            then
                local file_info
                file_info=$(get_file_info "$expected_file" false)
                info "✅ Generated: $expected_file ($file_info)"
            else
                warning "Expected file not generated: $expected_file"
            fi
        done
    else
        error_exit "Basic evaluation failed. Check evaluate.py output for details."
    fi
}

# Execute feature standardization
execute_feature_standardization()
{
    local results_file="$1"
    local standardized_file="$2"

    if [[ "$GENERATE_STANDARDIZED_FEATURES" != "true" ]]
    then
        info "Skipping feature standardization (disabled)"
        return 0
    fi

    print_header "FEATURE STANDARDIZATION"

    info "Executing feature standardization..."
    info "Input: $results_file"
    info "Output: $standardized_file"

    # Run standardize_features.py
    if run_with_error_handling "Feature standardization" \
        python3 "./$STANDARDIZE_SCRIPT_NAME" "$results_file" "$standardized_file"
    then
        success "Feature standardization completed successfully"

        # Validate standardized file
        if [[ -f "$standardized_file" ]]
        then
            local file_info
            file_info=$(get_file_info "$standardized_file" false)
            info "✅ Generated standardized features: $standardized_file ($file_info)"

            # Compare line counts
            local original_lines standardized_lines
            original_lines=$(wc -l < "$results_file" 2>/dev/null || echo "0")
            standardized_lines=$(wc -l < "$standardized_file" 2>/dev/null || echo "0")

            if [[ $original_lines -eq $standardized_lines ]]
            then
                info "✅ Line count preserved: $standardized_lines lines"
            else
                warning "Line count mismatch: $original_lines → $standardized_lines"
            fi
        else
            error_exit "Standardized features file was not created"
        fi
    else
        error_exit "Feature standardization failed. Check standardize_features.py output for details."
    fi
}

# Execute prediction analysis
execute_prediction_analysis()
{
    local features_file="$1"
    local model_file="$2"

    if [[ "$RUN_PREDICTION_ANALYSIS" != "true" ]]
    then
        info "Skipping prediction analysis (disabled)"
        return 0
    fi

    print_header "PREDICTION ANALYSIS"

    info "Executing prediction analysis..."
    info "Features: $features_file"
    info "Model: $model_file"

    # Run predict.py for analysis
    if run_with_error_handling "Prediction analysis" \
        python3 "./$PREDICT_SCRIPT_NAME" "$features_file" "$model_file"
    then
        success "Prediction analysis completed successfully"
    else
        warning "Prediction analysis failed. This may indicate model compatibility issues."
        warning "Check that the model was trained with compatible feature extraction settings."
    fi
}

# Generate comprehensive analysis report
generate_analysis_report()
{
    local results_file="$1"
    local output_prefix="$2"
    local report_file="${output_prefix}${ANALYSIS_REPORT_SUFFIX}"

    if [[ "$CREATE_DETAILED_REPORTS" != "true" ]]
    then
        info "Skipping detailed report generation (disabled)"
        return 0
    fi

    print_header "GENERATING ANALYSIS REPORT"

    info "Creating comprehensive analysis report..."
    info "Report file: $report_file"

    {
        echo "SONGBIRD EVALUATION ANALYSIS REPORT"
        echo "==================================="
        echo "Generated: $(date)"
        echo "Analysis performed on: $results_file"
        echo ""

        echo "ANALYSIS CONFIGURATION:"
        echo "======================"
        echo "Feature standardization: $GENERATE_STANDARDIZED_FEATURES"
        echo "Prediction analysis: $RUN_PREDICTION_ANALYSIS"
        echo "Detailed reports: $CREATE_DETAILED_REPORTS"
        echo ""

        echo "DATA SUMMARY:"
        echo "============="
        if [[ -f "$results_file" ]]
        then
            local total_samples
            total_samples=$(($(wc -l < "$results_file") - 1))
            echo "Total samples: $total_samples"

            # Analyze data distribution if possible
            if command -v python3 &>/dev/null
            then
                echo ""
                echo "Data distribution analysis:"
                python3 -c "
import pandas as pd
import sys
try:
    df = pd.read_csv('$results_file')
    if 'speaker' in df.columns:
        print('Samples per speaker:')
        speaker_counts = df['speaker'].value_counts()
        for speaker, count in speaker_counts.items():
            print(f'  Speaker {speaker}: {count} samples')

    if 'mode' in df.columns:
        print('\nSamples per mode:')
        mode_counts = df['mode'].value_counts()
        for mode, count in mode_counts.items():
            print(f'  Mode {mode}: {count} samples')

    print(f'\nFeature columns: {len([col for col in df.columns if col not in [\"speaker\", \"wav_file\", \"mode\"]])}')
except Exception as e:
    print(f'Error analyzing data: {e}')
" 2>/dev/null || echo "Could not analyze data distribution"
            fi
        fi

        echo ""
        echo "GENERATED FILES:"
        echo "==============="

        # List all generated files
        local output_dir
        output_dir=$(dirname "$output_prefix")
        local base_name
        base_name=$(basename "$output_prefix")

        find "$output_dir" -name "${base_name}*" -type f 2>/dev/null | while read -r file
        do
            local file_info
            file_info=$(get_file_info "$file" false)
            echo "📄 $(basename "$file"): $file_info"
        done

        echo ""
        echo "ANALYSIS SUMMARY:"
        echo "================="
        echo "Analysis completed successfully at $(date)"
        echo "All evaluation pipeline stages have been executed."
        echo ""
        echo "For detailed performance metrics, review the generated CSV files"
        echo "and any prediction analysis output."

        echo ""
        echo "Generated by Songbird Evaluation Pipeline v$SONGBIRD_VERSION"

    } > "$report_file"

    if [[ -f "$report_file" ]]
    then
        success "Analysis report generated: $report_file"

        if [[ "$VERBOSE_OPERATIONS" == "true" ]]
        then
            info "Report preview:"
            head -20 "$report_file" | while IFS= read -r line
            do
                echo "  $line"
            done
        fi
    else
        warning "Failed to generate analysis report"
    fi
}

# Display final results summary
show_final_summary()
{
    local results_file="$1"
    local output_prefix="$2"

    print_header "EVALUATION ANALYSIS COMPLETE"

    echo "Analysis Summary:"
    echo "================="

    # Show processed data info
    if [[ -f "$results_file" ]]
    then
        local sample_count
        sample_count=$(($(wc -l < "$results_file") - 1))
        echo "📊 Processed samples: $sample_count"
    fi

    # Show generated files
    echo ""
    echo "Generated Files:"
    echo "================"

    local output_dir
    output_dir=$(dirname "$output_prefix")
    local base_name
    base_name=$(basename "$output_prefix")

    local file_count=0
    find "$output_dir" -name "${base_name}*" -type f 2>/dev/null | sort | while read -r file
    do
        local file_info
        file_info=$(get_file_info "$file" false)
        echo "📄 $(basename "$file"): $file_info"
        ((file_count++))
    done

    # Show next steps
    echo ""
    echo "Next Steps:"
    echo "==========="
    echo "🔍 Review generated CSV files for detailed feature data"
    echo "📊 Examine prediction results for accuracy analysis"
    echo "📈 Use analysis reports for performance evaluation"
    echo "🔄 Run additional analysis with different parameters if needed"

    if [[ -f "${output_prefix}${ANALYSIS_REPORT_SUFFIX}" ]]
    then
        echo "📋 Check comprehensive report: ${output_prefix}${ANALYSIS_REPORT_SUFFIX}"
    fi
}

# Main execution function
main()
{
    parse_arguments "$@"

    print_header "EVALUATION RESULTS ANALYSIS"

    # Validate environment and prerequisites
    validate_environment

    # Validate input files
    validate_results_file "$RESULTS_FILE"
    validate_model_file "$MODEL_FILE"

    # Prepare output paths
    local output_prefix
    output_prefix=$(basename "$RESULTS_FILE" .csv)
    output_prefix="$(dirname "$RESULTS_FILE")/$output_prefix"

    # Execute analysis pipeline
    execute_basic_evaluation "$RESULTS_FILE" "$output_prefix"
    execute_feature_standardization "$RESULTS_FILE" "$RESULTS_FILE_STANDARDIZED"
    execute_prediction_analysis "$RESULTS_FILE_STANDARDIZED" "$MODEL_FILE"

    # Generate reports and summaries
    generate_analysis_report "$RESULTS_FILE" "$output_prefix"
    show_final_summary "$RESULTS_FILE" "$output_prefix"

    success "Evaluation analysis pipeline completed successfully"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
    main "$@"
fi