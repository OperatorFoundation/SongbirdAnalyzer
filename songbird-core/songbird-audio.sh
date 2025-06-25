#!/bin/bash

# =============================================================================
# SONGBIRD AUDIO DEVICE MANAGEMENT MODULE
# =============================================================================
#
# Handles audio device detection, configuration, and management.
# Provides audio device switching and validation.
#
# USAGE:
# ------
# source songbird-core/songbird-audio.sh
#
# FUNCTIONS:
# ----------
# save_original_audio_sources()        - Backup current audio devices
# restore_original_audio_sources()     - Restore original audio devices
# check_audio_device()                 - Verify Teensy device exists
# switch_to_teensy_audio()             - Switch to Teensy audio device
# list_available_audio_devices()       - List all available audio devices
# validate_audio_routing()             - Test audio routing
#
# =============================================================================

# Source required modules
if [[ -z "$SONGBIRD_VERSION" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/songbird-config.sh"
fi

if [[ -z "$ERROR_HANDLING_INITIALIZED" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/songbird-errors.sh"
fi

# AUDIO DEVICE STATE
# ==================
ORIGINAL_INPUT=""
ORIGINAL_OUTPUT=""
AUDIO_BACKUP_CREATED=false

# AUDIO DEVICE FUNCTIONS
# ======================

# Save current audio device configuration
save_original_audio_sources() {
    if ! command -v SwitchAudioSource &>/dev/null; then
        error_exit "SwitchAudioSource not found. Install with: brew install switchaudio-osx"
    fi

    info "Saving current audio device configuration..."

    ORIGINAL_INPUT=$(SwitchAudioSource -c -t input 2>/dev/null || echo "")
    ORIGINAL_OUTPUT=$(SwitchAudioSource -c -t output 2>/dev/null || echo "")

    if [[ -n "$ORIGINAL_INPUT" && -n "$ORIGINAL_OUTPUT" ]]; then
        AUDIO_BACKUP_CREATED=true
        success "Audio configuration saved:"
        info "  - Input: $ORIGINAL_INPUT"
        info "  - Output: $ORIGINAL_OUTPUT"

        # Register cleanup function
        register_cleanup_function "restore_original_audio_sources"
    else
        warning "Could not determine current audio devices"
        AUDIO_BACKUP_CREATED=false
    fi
}

# Restore original audio device configuration
restore_original_audio_sources() {
    if [[ "$AUDIO_BACKUP_CREATED" != "true" ]]; then
        info "No audio backup to restore"
        return 0
    fi

    if ! command -v SwitchAudioSource &>/dev/null; then
        warning "SwitchAudioSource not available for audio restoration"
        return 1
    fi

    info "Restoring original audio devices..."

    local restore_success=true

    # Restore input device
    if [[ -n "$ORIGINAL_INPUT" ]]; then
        info "Restoring input device: $ORIGINAL_INPUT"
        if SwitchAudioSource -t "input" -s "$ORIGINAL_INPUT" 2>/dev/null; then
            success "Input device restored"
        else
            warning "Failed to restore input device: $ORIGINAL_INPUT"
            # Try fallback
            if SwitchAudioSource -t "input" -s "Built-in Microphone" 2>/dev/null; then
                info "Fallback to Built-in Microphone successful"
            else
                error_log "Failed to restore any input device"
                restore_success=false
            fi
        fi
    fi

    # Restore output device
    if [[ -n "$ORIGINAL_OUTPUT" ]]; then
        info "Restoring output device: $ORIGINAL_OUTPUT"
        if SwitchAudioSource -t "output" -s "$ORIGINAL_OUTPUT" 2>/dev/null; then
            success "Output device restored"
        else
            warning "Failed to restore output device: $ORIGINAL_OUTPUT"
            # Try fallback
            if SwitchAudioSource -t "output" -s "Built-in Output" 2>/dev/null; then
                info "Fallback to Built-in Output successful"
            else
                error_log "Failed to restore any output device"
                restore_success=false
            fi
        fi
    fi

    if [[ "$restore_success" == "true" ]]; then
        success "Audio devices restored successfully"
    else
        warning "Audio device restoration completed with some failures"
    fi

    return 0
}

# Check if Teensy audio device is available
check_audio_device() {
    if ! command -v SwitchAudioSource &>/dev/null; then
        error_log "SwitchAudioSource not available"
        return 1
    fi

    if SwitchAudioSource -a 2>/dev/null | grep -q "$DEVICE_NAME"; then
        return 0
    else
        return 1
    fi
}

# List all available audio devices
list_available_audio_devices() {
    if ! command -v SwitchAudioSource &>/dev/null; then
        error_log "SwitchAudioSource not available"
        return 1
    fi

    echo "Available Audio Devices:"
    echo "========================"

    echo ""
    echo "Input Devices:"
    SwitchAudioSource -a -t input 2>/dev/null | sed 's/^/  - /' || echo "  Could not list input devices"

    echo ""
    echo "Output Devices:"
    SwitchAudioSource -a -t output 2>/dev/null | sed 's/^/  - /' || echo "  Could not list output devices"

    echo ""
    echo "All Devices:"
    SwitchAudioSource -a 2>/dev/null | sed 's/^/  - /' || echo "  Could not list all devices"
}

# Switch to Teensy audio device
switch_to_teensy_audio() {
    local device_type="$1"  # "input", "output", or "both"

    if [[ -z "$device_type" ]]; then
        device_type="both"
    fi

    # Validate device is available
    if ! check_audio_device; then
        error_log "Teensy audio device '$DEVICE_NAME' not found"
        echo "" >&2
        echo "Available devices:" >&2
        list_available_audio_devices >&2
        return 1
    fi

    local switch_success=true

    # Switch input device
    if [[ "$device_type" == "input" || "$device_type" == "both" ]]; then
        info "Switching audio input to: $DEVICE_NAME"
        if SwitchAudioSource -t "input" -s "$DEVICE_NAME" 2>/dev/null; then
            success "Audio input switched to Teensy"
        else
            error_log "Failed to switch audio input to: $DEVICE_NAME"
            switch_success=false
        fi
    fi

    # Switch output device
    if [[ "$device_type" == "output" || "$device_type" == "both" ]]; then
        info "Switching audio output to: $DEVICE_NAME"
        if SwitchAudioSource -t "output" -s "$DEVICE_NAME" 2>/dev/null; then
            success "Audio output switched to Teensy"
        else
            error_log "Failed to switch audio output to: $DEVICE_NAME"
            switch_success=false
        fi
    fi

    if [[ "$switch_success" == "true" ]]; then
        success "Audio device switching completed successfully"
        return 0
    else
        error_log "Audio device switching failed"
        return 1
    fi
}

# Test audio routing by playing a test tone
validate_audio_routing() {
    local test_duration="${1:-2}"
    local test_frequency="${2:-440}"
    local test_output_dir="${3:-/tmp}"

    info "Testing audio routing..."

    # Create test files
    local test_tone_file="$test_output_dir/audio_test_tone.wav"
    local test_recording_file="$test_output_dir/audio_test_recording.wav"

    # Clean up any existing test files
    rm -f "$test_tone_file" "$test_recording_file"

    # TODO: Generate test tone
#    info "Generating test tone ($test_frequency Hz for ${test_duration}s)..."
#    if ! sox -n -r 44100 -c 1 "$test_tone_file" synth "$test_duration" sine "$test_frequency" vol 0.3 2>/dev/null; then
#        error_log "Failed to generate test tone"
#        return 1
#    fi

    # TODO: Test playback capability
#    info "Testing audio playback..."
#    if ! afplay "$test_tone_file" 2>/dev/null; then
#        error_log "Audio playback test failed"
#        rm -f "$test_tone_file"
#        return 1
#    fi
#
#    # Test recording capability
#    info "Testing audio recording..."
#    local recording_pid
#    rec "$test_recording_file" trim 0 "$test_duration" 2>/dev/null &
#    recording_pid=$!
#
#    # Wait for recording to complete
#    sleep "$((test_duration + 1))"
#
#    # Check if recording process is still running and kill if necessary
#    if kill -0 "$recording_pid" 2>/dev/null; then
#        kill "$recording_pid" 2>/dev/null
#        wait "$recording_pid" 2>/dev/null
#    fi
#
#    # Validate recorded file
#    if [[ -f "$test_recording_file" ]]; then
#        local file_size
#        if command -v stat >/dev/null; then
#            if stat --version 2>/dev/null | grep -q GNU; then
#                file_size=$(stat --format="%s" "$test_recording_file" 2>/dev/null || echo "0")
#            else
#                file_size=$(stat -f%z "$test_recording_file" 2>/dev/null || echo "0")
#            fi
#        else
#            file_size=$(wc -c < "$test_recording_file" 2>/dev/null || echo "0")
#        fi
#
#        if [[ "$file_size" -gt "$MINIMUM_VALID_AUDIO_FILE_SIZE_BYTES" ]]; then
#            success "Audio routing test passed (recorded ${file_size} bytes)"
#            rm -f "$test_tone_file" "$test_recording_file"
#            return 0
#        else
#            error_log "Audio recording test failed (file too small: ${file_size} bytes)"
#        fi
#    else
#        error_log "Audio recording test failed (no file created)"
#    fi

    # Clean up test files
    rm -f "$test_tone_file" "$test_recording_file"
    return 1
}

# Get current audio device configuration
get_current_audio_devices() {
    if ! command -v SwitchAudioSource &>/dev/null; then
        error_log "SwitchAudioSource not available"
        return 1
    fi

    echo "Current Audio Configuration:"
    echo "==========================="

    local current_input=$(SwitchAudioSource -c -t input 2>/dev/null || echo "Unknown")
    local current_output=$(SwitchAudioSource -c -t output 2>/dev/null || echo "Unknown")

    echo "Input Device:  $current_input"
    echo "Output Device: $current_output"

    # Check if Teensy is currently active
    if [[ "$current_input" == "$DEVICE_NAME" || "$current_output" == "$DEVICE_NAME" ]]; then
        echo ""
        echo "✅ Teensy audio device is currently active"
    else
        echo ""
        echo "ℹ️  Teensy audio device is not currently active"
    fi
}

# Comprehensive audio system validation
validate_audio_system() {
    info "Performing comprehensive audio system validation..."

    local validation_errors=()

    # Check SwitchAudioSource availability
    if ! command -v SwitchAudioSource &>/dev/null; then
        validation_errors+=("SwitchAudioSource not found - install with: brew install switchaudio-osx")
    fi

    # Check for audio processing tools
    if ! command -v sox &>/dev/null; then
        validation_errors+=("SoX not found - install with: brew install sox")
    fi

    if ! command -v afplay &>/dev/null; then
        validation_errors+=("afplay not found - should be included with macOS")
    fi

    if ! command -v rec &>/dev/null; then
        validation_errors+=("rec (from SoX) not found - install with: brew install sox")
    fi

    # Check Teensy device availability
    if ! check_audio_device; then
        validation_errors+=("Teensy audio device '$DEVICE_NAME' not found")
    fi

    # Report validation results
    if [[ ${#validation_errors[@]} -eq 0 ]]; then
        success "Audio system validation passed"

        # Show current configuration
        get_current_audio_devices

        return 0
    else
        error_log "Audio system validation failed:"
        for error in "${validation_errors[@]}"; do
            error_log "  - $error"
        done

        echo "" >&2
        echo "AUDIO SYSTEM ISSUES:" >&2
        for error in "${validation_errors[@]}"; do
            echo "  ❌ $error" >&2
        done
        echo "" >&2

        # Show available devices for troubleshooting
        echo "TROUBLESHOOTING - Available Devices:" >&2
        list_available_audio_devices >&2

        return 1
    fi
}