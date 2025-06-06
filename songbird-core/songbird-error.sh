#!/bin/bash
# =============================================================================
# SONGBIRD ERROR HANDLING MODULE
# =============================================================================
#
# Provides comprehensive error handling, logging, and recovery mechanisms.
# Standardizes error reporting across all Songbird scripts.
#
# USAGE:
# ------
# source songbird-core/songbird-errors.sh
#
# FUNCTIONS:
# ----------
# error_exit <message> [exit_code]     - Report error and exit
# error_log <message>                  - Log error without exiting
# warning <message>                    - Report warning
# validate_prerequisites <requirements> - Check prerequisites
# handle_interrupt                     - Handle Ctrl+C gracefully
# setup_error_handling                 - Initialize error handling
#
# =============================================================================

# Source configuration if not already loaded
if [[ -z "$SONGBIRD_VERSION" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/songbird-config.sh"
fi

# ERROR HANDLING STATE
# ====================
ERROR_HANDLING_INITIALIZED=false
ORIGINAL_EXIT_HANDLER=""
CLEANUP_FUNCTIONS=()

# LOGGING CONFIGURATION
# =====================
ERROR_LOG_PATH="$PROJECT_ROOT/$ERROR_LOG_FILE"

# Ensure error log directory exists
mkdir -p "$(dirname "$ERROR_LOG_PATH")"

# CORE ERROR FUNCTIONS
# ====================

# Log message with timestamp and level
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local script_name=$(basename "${BASH_SOURCE[2]}")

    # Format: [TIMESTAMP] [LEVEL] [SCRIPT] MESSAGE
    local formatted_message="[$timestamp] [$level] [$script_name] $message"

    # Always log to file
    echo "$formatted_message" >> "$ERROR_LOG_PATH"

    # Also output to stderr for ERROR and WARNING
    if [[ "$level" == "ERROR" || "$level" == "WARNING" ]]; then
        echo "$formatted_message" >&2
    elif [[ "$VERBOSE_OPERATIONS" == "true" && "$level" == "INFO" ]]; then
        echo "$formatted_message" >&2
    fi
}

# Report error and exit with specified code
error_exit() {
    local message="$1"
    local exit_code="${2:-$EXIT_CODE_GENERAL_ERROR}"

    log_message "ERROR" "$message"
    echo "💥 FATAL ERROR: $message" >&2
    echo "   Check $ERROR_LOG_PATH for detailed logs" >&2

    # Run cleanup functions
    run_cleanup_functions

    exit "$exit_code"
}

# Log error without exiting
error_log() {
    local message="$1"
    log_message "ERROR" "$message"
    echo "❌ ERROR: $message" >&2
}

# Report warning
warning() {
    local message="$1"
    log_message "WARNING" "$message"
    echo "⚠️  WARNING: $message" >&2
}

# Report info message
info() {
    local message="$1"
    log_message "INFO" "$message"
    if [[ "$VERBOSE_OPERATIONS" == "true" ]]; then
        echo "ℹ️  INFO: $message" >&2
    fi
}

# Report success message
success() {
    local message="$1"
    log_message "SUCCESS" "$message"
    echo "✅ SUCCESS: $message" >&2
}

# PREREQUISITE VALIDATION
# =======================

# Check if command exists
check_command() {
    local command="$1"
    local error_message="$2"

    if ! command -v "$command" &>/dev/null; then
        if [[ -n "$error_message" ]]; then
            error_exit "$error_message"
        else
            error_exit "Required command not found: $command"
        fi
    fi
}

# Check if file exists and is readable
check_file_readable() {
    local file_path="$1"
    local error_message="$2"

    if [[ ! -f "$file_path" ]]; then
        error_exit "${error_message:-File not found: $file_path}"
    fi

    if [[ ! -r "$file_path" ]]; then
        error_exit "${error_message:-File not readable: $file_path}"
    fi
}

# Check if directory exists and is writable
check_directory_writable() {
    local dir_path="$1"
    local error_message="$2"

    if [[ ! -d "$dir_path" ]]; then
        if ! mkdir -p "$dir_path" 2>/dev/null; then
            error_exit "${error_message:-Cannot create directory: $dir_path}"
        fi
    fi

    if [[ ! -w "$dir_path" ]]; then
        error_exit "${error_message:-Directory not writable: $dir_path}"
    fi
}

# Check if Python module is available
check_python_module() {
    local module_name="$1"
    local error_message="$2"

    if ! "$PYTHON_CMD" -c "import $module_name" &>/dev/null; then
        error_exit "${error_message:-Python module not available: $module_name. Try: pip install $module_name}"
    fi
}

# Comprehensive prerequisite validation
validate_prerequisites() {
    local requirements=("$@")
    local validation_errors=()

    info "Validating prerequisites..."

    for requirement in "${requirements[@]}"; do
        case "$requirement" in
            "python3")
                if ! check_command "$PYTHON_CMD" ""; then
                    validation_errors+=("Python 3 not found")
                fi
                ;;
            "sox")
                if ! check_command "sox" ""; then
                    validation_errors+=("SoX audio processing tool not found. Install with: brew install sox")
                fi
                ;;
            "ffmpeg")
                if ! check_command "ffmpeg" ""; then
                    validation_errors+=("FFmpeg not found. Install with: brew install ffmpeg")
                fi
                ;;
            "SwitchAudioSource")
                if ! check_command "SwitchAudioSource" ""; then
                    validation_errors+=("SwitchAudioSource not found. Install with: brew install switchaudio-osx")
                fi
                ;;
            "librosa")
                if ! check_python_module "librosa" ""; then
                    validation_errors+=("Python librosa module not found. Install with: pip install librosa")
                fi
                ;;
            "pandas")
                if ! check_python_module "pandas" ""; then
                    validation_errors+=("Python pandas module not found. Install with: pip install pandas")
                fi
                ;;
            "numpy")
                if ! check_python_module "numpy" ""; then
                    validation_errors+=("Python numpy module not found. Install with: pip install numpy")
                fi
                ;;
            "working_directory")
                check_directory_writable "$WORKING_DIR" "Cannot access working directory"
                ;;
            "results_directory")
                check_directory_writable "$(dirname "$RESULTS_FILE")" "Cannot access results directory"
                ;;
            *)
                warning "Unknown prerequisite: $requirement"
                ;;
        esac
    done

    # Report validation results
    if [[ ${#validation_errors[@]} -eq 0 ]]; then
        success "All prerequisites validated successfully"
        return 0
    else
        error_log "Prerequisite validation failed:"
        for error in "${validation_errors[@]}"; do
            error_log "  - $error"
        done

        echo "" >&2
        echo "MISSING PREREQUISITES:" >&2
        for error in "${validation_errors[@]}"; do
            echo "  ❌ $error" >&2
        done
        echo "" >&2
        echo "Please install missing prerequisites and try again." >&2

        return 1
    fi
}

# CLEANUP SYSTEM
# ==============

# Register cleanup function to run on exit
register_cleanup_function() {
    local cleanup_func="$1"
    CLEANUP_FUNCTIONS+=("$cleanup_func")
}

# Run all registered cleanup functions
run_cleanup_functions() {
    if [[ ${#CLEANUP_FUNCTIONS[@]} -gt 0 ]]; then
        info "Running cleanup functions..."
        for cleanup_func in "${CLEANUP_FUNCTIONS[@]}"; do
            if type "$cleanup_func" >/dev/null 2>&1 && [[ "$(type -t "$cleanup_func")" == "function" ]]; then
              info "Running cleanup: $cleanup_func"
              "$cleanup_func" || warning "Cleanup function failed: $cleanup_func"
            fi
        done
    fi
}

# SIGNAL HANDLING
# ===============

# Handle interruption signals (Ctrl+C, etc.)
handle_interrupt() {
    local signal="$1"
    warning "Received signal: $signal"
    echo "" >&2
    echo "🛑 Operation interrupted by user" >&2

    # Run cleanup functions
    run_cleanup_functions

    # Exit with appropriate code
    exit "$EXIT_CODE_USER_CANCELLED"
}

# RECOVERY MECHANISMS
# ===================

# Attempt to recover from common errors
attempt_error_recovery() {
    local error_type="$1"
    local context="$2"

    case "$error_type" in
        "audio_device_missing")
            warning "Audio device '$DEVICE_NAME' not found, attempting to refresh device list..."
            sleep 2
            if check_audio_device; then
                success "Audio device recovered"
                return 0
            fi
            ;;
        "teensy_disconnected")
            warning "Teensy device disconnected, checking for reconnection..."
            sleep 3
            local teensy_device=$(find_teensy_device)
            if [[ -n "$teensy_device" ]]; then
                success "Teensy device recovered at: $teensy_device"
                return 0
            fi
            ;;
        "disk_space")
            local available_space=$(df . | awk 'NR==2 {print $4}')
            if [[ "$available_space" -gt 1000000 ]]; then  # More than 1GB
                success "Disk space appears sufficient now"
                return 0
            fi
            ;;
    esac

    return 1
}

# VALIDATION WITH RECOVERY
# ========================

# Validate operation with automatic retry and recovery
validate_with_recovery() {
    local validation_function="$1"
    local error_recovery_type="$2"
    local max_retries="${3:-3}"
    local retry_delay="${4:-2}"

    local attempt=1

    while [[ $attempt -le $max_retries ]]; do
        if [[ $attempt -gt 1 ]]; then
            info "Validation attempt $attempt of $max_retries..."

            # Attempt recovery before retry
            if [[ -n "$error_recovery_type" ]]; then
                if attempt_error_recovery "$error_recovery_type" "validation_retry"; then
                    info "Recovery attempt successful, retrying validation..."
                else
                    warning "Recovery attempt failed"
                fi
            fi

            sleep "$retry_delay"
        fi

        # Run validation function
        if "$validation_function"; then
            if [[ $attempt -gt 1 ]]; then
                success "Validation successful after $attempt attempts"
            fi
            return 0
        fi

        ((attempt++))
    done

    error_exit "Validation failed after $max_retries attempts"
}

# ERROR HANDLING SETUP
# ====================

# Initialize comprehensive error handling
setup_error_handling() {
    if [[ "$ERROR_HANDLING_INITIALIZED" == "true" ]]; then
        return 0
    fi

    # Set up signal handlers
    trap 'handle_interrupt SIGINT' INT
    trap 'handle_interrupt SIGTERM' TERM

    # Set up exit handler
    trap 'run_cleanup_functions' EXIT

    # Enable strict error handling
    set -eE  # Exit on error, inherit ERR trap

    # Set up ERR trap for automatic error reporting
    trap 'error_log "Command failed at line $LINENO: $BASH_COMMAND"' ERR

    ERROR_HANDLING_INITIALIZED=true
    info "Error handling system initialized"
}

# UTILITY FUNCTIONS
# =================

# Check if we're running with sufficient privileges
check_privileges() {
    # Check if we can write to system directories if needed
    if [[ "$EUID" -eq 0 ]]; then
        warning "Running as root - this may not be necessary and could be dangerous"
    fi
}

# Validate system resources
check_system_resources() {
    # Check available disk space (require at least 1GB)
    local available_kb=$(df . | awk 'NR==2 {print $4}')
    local required_kb=1048576  # 1GB in KB

    if [[ "$available_kb" -lt "$required_kb" ]]; then
        error_exit "Insufficient disk space. Available: $(($available_kb/1024))MB, Required: $(($required_kb/1024))MB"
    fi

    # Check if system is too heavily loaded
    if command -v uptime >/dev/null; then
        local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        local num_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "4")

        # Warn if load average is more than 2x number of cores
        if (( $(echo "$load_avg > ($num_cores * 2)" | bc -l) )); then
            warning "System appears heavily loaded (load: $load_avg, cores: $num_cores). Performance may be affected."
        fi
    fi
}

# INTEGRATION HELPERS
# ===================

# Run command with error handling and logging
run_with_error_handling() {
    local description="$1"
    shift
    local command=("$@")

    info "Starting: $description"

    if "${command[@]}"; then
        success "Completed: $description"
        return 0
    else
        local exit_code=$?
        error_log "Failed: $description (exit code: $exit_code)"
        return $exit_code
    fi
}

# Validate file with Python validation system
validate_audio_file_robust() {
    local file_path="$1"
    local expected_duration="${2:-$EXPECTED_AUDIO_DURATION_SECONDS}"
    local tolerance="${3:-$AUDIO_VALIDATION_TOLERANCE_SECONDS}"

    if [[ "$USE_PYTHON_VALIDATION" == "true" ]]; then
        local validation_script="$SONGBIRD_CORE_PYTHON_DIR/validation.py"

        if [[ -f "$validation_script" ]]; then
            info "Validating audio file: $(basename "$file_path")"

            if "$PYTHON_CMD" "$validation_script" "$file_path" "$expected_duration" "$tolerance" >/dev/null; then
                success "Audio file validation passed: $(basename "$file_path")"
                return 0
            else
                error_log "Audio file validation failed: $(basename "$file_path")"
                return 1
            fi
        else
            warning "Python validation script not found, skipping robust validation"
            return 0
        fi
    else
        # Fall back to basic validation
        check_file_readable "$file_path"
        return 0
    fi
}
