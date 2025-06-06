#!/bin/bash
# =============================================================================
# SONGBIRD HARDWARE VALIDATION MODULE
# =============================================================================
#
# Hardware detection, validation, and testing for Teensy devices.
# Provides hardware interaction and validation mechanisms.
#
# USAGE:
# ------
# source songbird-core/songbird-hardware.sh
#
# FUNCTIONS:
# ----------
# find_teensy_device()                 - Locate Teensy USB device
# test_serial_communication()          - Test serial device connectivity
# test_firmware_responsiveness()       - Test firmware mode switching
# validate_hardware_setup()            - Comprehensive hardware validation
# check_hardware_during_recording()    - Quick hardware check during operation
# reset_teensy_device()               - Attempt to reset Teensy device
#
# =============================================================================

# Source required modules
if [[ -z "$SONGBIRD_VERSION" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/songbird-config.sh"
fi

if [[ -z "$ERROR_HANDLING_INITIALIZED" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/songbird-errors.sh"
fi

if [[ -z "$AUDIO_BACKUP_CREATED" ]] && [[ -f "$(dirname "${BASH_SOURCE[0]}")/songbird-audio.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/songbird-audio.sh"
fi

# HARDWARE STATE
# ==============
TEENSY_DEVICE_PATH=""
HARDWARE_VALIDATION_PASSED=false
FIRMWARE_RESPONSIVE=false

# TEENSY DEVICE DETECTION
# =======================

# Find Teensy device using multiple detection methods
find_teensy_device() {
    local device_path=""

    info "Searching for Teensy device..."

    # Method 1: Use ioreg to find Teensy device
    local ioreg_device=$(ioreg -p IOUSB -l -w 0 2>/dev/null | grep -i teensy -A10 | grep "IODialinDevice" | sed -e 's/.*= "//' -e 's/".*//' | head -n1)

    if [[ -n "$ioreg_device" && -e "$ioreg_device" ]]; then
        device_path="$ioreg_device"
        info "Found Teensy via ioreg: $device_path"
    else
        # Method 2: Look for USB modem devices (Teensy pattern)
        local usb_devices=($(ls /dev/cu.usbmodem* 2>/dev/null))

        if [[ ${#usb_devices[@]} -gt 0 ]]; then
            # If multiple devices, try to identify the most likely Teensy
            for device in "${usb_devices[@]}"; do
                if [[ -e "$device" ]]; then
                    device_path="$device"
                    info "Found potential Teensy via USB scan: $device_path"
                    break
                fi
            done
        fi
    fi

    # Method 3: Check for any tty USB devices
    if [[ -z "$device_path" ]]; then
        local tty_devices=($(ls /dev/tty.usbmodem* 2>/dev/null))

        if [[ ${#tty_devices[@]} -gt 0 ]]; then
            for device in "${tty_devices[@]}"; do
                if [[ -e "$device" ]]; then
                    device_path="$device"
                    info "Found potential Teensy via tty scan: $device_path"
                    break
                fi
            done
        fi
    fi

    if [[ -n "$device_path" ]]; then
        TEENSY_DEVICE_PATH="$device_path"
        success "Teensy device found: $device_path"
        echo "$device_path"
        return 0
    else
        error_log "No Teensy device found"
        echo ""
        return 1
    fi
}

# Get detailed device information
get_teensy_device_info() {
    local device_path="$1"

    if [[ -z "$device_path" ]]; then
        device_path="$TEENSY_DEVICE_PATH"
    fi

    if [[ -z "$device_path" ]]; then
        error_log "No device path specified for device info"
        return 1
    fi

    echo "Teensy Device Information:"
    echo "========================="
    echo "Device Path: $device_path"

    # Check device permissions
    if [[ -r "$device_path" ]]; then
        echo "Readable: ✅ Yes"
    else
        echo "Readable: ❌ No"
    fi

    if [[ -w "$device_path" ]]; then
        echo "Writable: ✅ Yes"
    else
        echo "Writable: ❌ No"
    fi

    # Get device details from system
    if command -v stat >/dev/null; then
        local device_stat=$(stat "$device_path" 2>/dev/null)
        if [[ -n "$device_stat" ]]; then
            echo ""
            echo "Device Statistics:"
            echo "$device_stat"
        fi
    fi

    # Try to get USB device info
    local device_basename=$(basename "$device_path")
    local usb_info=$(ioreg -p IOUSB -l -w 0 2>/dev/null | grep -A20 -B5 "$device_basename" | grep -E "(Product|Vendor|USB Product Name)" || echo "No USB info available")

    if [[ "$usb_info" != "No USB info available" ]]; then
        echo ""
        echo "USB Information:"
        echo "$usb_info"
    fi
}

# SERIAL COMMUNICATION TESTING
# =============================

# Test basic serial communication with device
test_serial_communication() {
    local device_path="$1"
    local timeout="${2:-$SERIAL_TIMEOUT_SECONDS}"

    if [[ -z "$device_path" ]]; then
        error_log "No device path specified for serial communication test"
        return 1
    fi

    info "Testing serial communication with: $device_path"

    # Check device accessibility
    if [[ ! -e "$device_path" ]]; then
        error_log "Device does not exist: $device_path"
        return 1
    fi

    if [[ ! -w "$device_path" ]]; then
        error_log "Device not writable: $device_path"
        return 1
    fi

    # Configure serial settings
    info "Configuring serial communication..."
    if ! stty -f "$device_path" 115200 cs8 -cstopb -parenb 2>/dev/null; then
        error_log "Failed to configure serial settings for: $device_path"
        return 1
    fi

    # Test write operation with timeout
    info "Testing serial write operation..."
    if ! timeout "$timeout" sh -c "echo 'n' > '$device_path'" 2>/dev/null; then
        error_log "Serial write operation failed or timed out"
        return 1
    fi

    # Give device time to process
    sleep 0.5

    success "Serial communication test passed"
    return 0
}

# Test serial communication with retry logic
test_serial_communication_robust() {
    local device_path="$1"
    local max_retries="${2:-$HARDWARE_VALIDATION_RETRY_COUNT}"
    local retry_delay="${3:-$HARDWARE_VALIDATION_RETRY_DELAY_SECONDS}"

    local attempt=1

    while [[ $attempt -le $max_retries ]]; do
        if [[ $attempt -gt 1 ]]; then
            info "Serial communication test attempt $attempt of $max_retries..."
            sleep "$retry_delay"
        fi

        if test_serial_communication "$device_path"; then
            if [[ $attempt -gt 1 ]]; then
                success "Serial communication established after $attempt attempts"
            fi
            return 0
        fi

        ((attempt++))
    done

    error_log "Serial communication failed after $max_retries attempts"
    return 1
}

# FIRMWARE RESPONSIVENESS TESTING
# ================================

# Test firmware responsiveness across all modes
test_firmware_responsiveness() {
    local device_path="$1"
    local test_output_dir="${2:-/tmp/songbird_firmware_test}"
    local timeout="${3:-$FIRMWARE_TEST_TIMEOUT_SECONDS}"

    if [[ -z "$device_path" ]]; then
        error_log "No device path specified for firmware test"
        return 1
    fi

    info "Testing firmware responsiveness..."
    echo "IMPORTANT: Ensure Teensy firmware is in 'dev' mode to receive serial commands"

    # Create test directory
    mkdir -p "$test_output_dir"

    # Generate test tone for firmware validation
    local test_tone_file="$test_output_dir/firmware_test_tone.wav"
    info "Generating test tone for firmware validation..."

    if ! sox -n -r 44100 -c 1 "$test_tone_file" synth "$FIRMWARE_TEST_TONE_DURATION_SECONDS" sine "$FIRMWARE_TEST_TONE_FREQUENCY_HZ" vol 0.5 2>/dev/null; then
        error_log "Failed to generate test tone for firmware validation"
        return 1
    fi

    # Test each firmware mode
    local modes_tested=0
    local modes_passed=0
    local test_results=()

    for mode_index in "${!modes[@]}"; do
        local mode="${modes[mode_index]}"
        local mode_name="${mode_names[mode_index]}"
        local test_recording_file="$test_output_dir/firmware_test_${mode}.wav"

        info "Testing firmware mode: $mode_name ($mode)"
        ((modes_tested++))

        # Send mode command to firmware
        if ! echo "$mode" > "$device_path" 2>/dev/null; then
            warning "Failed to send mode command '$mode' to firmware"
            test_results+=("❌ $mode_name: Command failed")
            continue
        fi

        # Give firmware time to process mode change
        sleep 1

        # Test audio processing with this mode
        info "Testing audio processing in $mode_name mode..."

        # Start recording in background
        timeout "$timeout" rec "$test_recording_file" trim 0 "$FIRMWARE_TEST_TONE_DURATION_SECONDS" 2>/dev/null &
        local rec_pid=$!

        # Play test tone
        afplay "$test_tone_file" &
        local play_pid=$!

        # Wait for both processes
        wait "$play_pid" 2>/dev/null
        wait "$rec_pid" 2>/dev/null
        local rec_exit_code=$?

        # Validate recording
        if [[ $rec_exit_code -eq 0 && -f "$test_recording_file" ]]; then
            local file_size
            if command -v stat >/dev/null; then
                if stat --version 2>/dev/null | grep -q GNU; then
                    file_size=$(stat --format="%s" "$test_recording_file" 2>/dev/null || echo "0")
                else
                    file_size=$(stat -f%z "$test_recording_file" 2>/dev/null || echo "0")
                fi
            else
                file_size=$(wc -c < "$test_recording_file" 2>/dev/null || echo "0")
            fi

            if [[ "$file_size" -gt "$MINIMUM_VALID_AUDIO_FILE_SIZE_BYTES" ]]; then
                success "✅ $mode_name mode test passed (${file_size} bytes recorded)"
                test_results+=("✅ $mode_name: Working (${file_size} bytes)")
                ((modes_passed++))
            else
                warning "❌ $mode_name mode test failed (file too small: ${file_size} bytes)"
                test_results+=("❌ $mode_name: File too small (${file_size} bytes)")
            fi
        else
            warning "❌ $mode_name mode test failed (recording failed or no file created)"
            test_results+=("❌ $mode_name: Recording failed")
        fi

        # Clean up test recording
        rm -f "$test_recording_file"
    done

    # Clean up test tone
    rm -f "$test_tone_file"

    # Report results
    echo ""
    echo "Firmware Responsiveness Test Results:"
    echo "====================================="
    for result in "${test_results[@]}"; do
        echo "  $result"
    done

    local success_rate=$((modes_passed * 100 / modes_tested))
    echo ""
    echo "Overall Result: $modes_passed/$modes_tested modes working (${success_rate}%)"

    if [[ $modes_passed -eq $modes_tested ]]; then
        success "🎉 All firmware modes are responsive and working correctly"
        FIRMWARE_RESPONSIVE=true
        return 0
    elif [[ $modes_passed -gt 0 ]]; then
        warning "⚠️  Partial firmware functionality ($modes_passed/$modes_tested modes working)"
        echo "Some firmware modes may not be functioning correctly."
        FIRMWARE_RESPONSIVE=false
        return 1
    else
        error_log "💥 No firmware modes are responding correctly"
        echo ""
        echo "TROUBLESHOOTING STEPS:"
        echo "1. Ensure Teensy firmware is running and in 'dev' mode"
        echo "2. Check audio cable connections between Teensy and computer"
        echo "3. Verify firmware has not crashed (try resetting Teensy)"
        echo "4. Confirm audio routing is working properly"
        echo "5. Check that both input and output are set to Teensy device"
        FIRMWARE_RESPONSIVE=false
        return 1
    fi
}

# COMPREHENSIVE HARDWARE VALIDATION
# ==================================

# Perform complete hardware validation with retry logic
validate_hardware_setup() {
    local max_retries="${1:-$HARDWARE_VALIDATION_RETRY_COUNT}"
    local retry_delay="${2:-$HARDWARE_VALIDATION_RETRY_DELAY_SECONDS}"
    local test_output_dir="${3:-/tmp/songbird_hardware_validation}"

    info "🔍 Starting comprehensive hardware validation..."

    local attempt=1

    while [[ $attempt -le $max_retries ]]; do
        if [[ $attempt -gt 1 ]]; then
            info "🔄 Hardware validation attempt $attempt of $max_retries..."
            sleep "$retry_delay"
        fi

        local validation_passed=true

        # Step 1: Find Teensy device
        info "Step 1/5: Locating Teensy device..."
        local teensy_device_path=$(find_teensy_device)

        if [[ -z "$teensy_device_path" ]]; then
            error_log "❌ No Teensy device found"
            validation_passed=false
        else
            success "✅ Teensy device located: $teensy_device_path"

            # Show device information if verbose
            if [[ "$VERBOSE_OPERATIONS" == "true" ]]; then
                get_teensy_device_info "$teensy_device_path"
            fi
        fi

        # Step 2: Test serial communication
        if [[ "$validation_passed" == "true" ]]; then
            info "Step 2/5: Testing serial communication..."
            if test_serial_communication_robust "$teensy_device_path"; then
                success "✅ Serial communication verified"
            else
                error_log "❌ Serial communication failed"
                validation_passed=false
            fi
        fi

        # Step 3: Validate audio device availability
        if [[ "$validation_passed" == "true" ]]; then
            info "Step 3/5: Checking audio device availability..."
            if check_audio_device; then
                success "✅ Audio device '$DEVICE_NAME' found and available"
            else
                error_log "❌ Audio device '$DEVICE_NAME' not found"
                echo ""
                echo "Available audio devices:"
                list_available_audio_devices
                validation_passed=false
            fi
        fi

        # Step 4: Test audio system
        if [[ "$validation_passed" == "true" ]]; then
            info "Step 4/5: Testing audio routing..."
            if validate_audio_routing 2 440 "$test_output_dir"; then
                success "✅ Audio routing test passed"
            else
                error_log "❌ Audio routing test failed"
                validation_passed=false
            fi
        fi

        # Step 5: Test firmware responsiveness
        if [[ "$validation_passed" == "true" ]]; then
            info "Step 5/5: Testing firmware responsiveness..."
            if test_firmware_responsiveness "$teensy_device_path" "$test_output_dir"; then
                success "✅ Firmware responsiveness verified"
            else
                error_log "❌ Firmware responsiveness test failed"
                validation_passed=false
            fi
        fi

        # Clean up test directory
        rm -rf "$test_output_dir"

        # Check overall validation result
        if [[ "$validation_passed" == "true" ]]; then
            echo ""
            success "🎉 Hardware validation SUCCESSFUL!"
            echo "   All systems are ready for audio recording operations"
            HARDWARE_VALIDATION_PASSED=true
            return 0
        fi

        ((attempt++))
    done

    # All validation attempts failed
    echo ""
    error_log "💥 Hardware validation FAILED after $max_retries attempts"
    echo ""
    echo "HARDWARE REQUIREMENTS CHECKLIST:"
    echo "================================="
    echo "❓ Teensy device connected via USB"
    echo "❓ Songbird firmware loaded and running in 'dev' mode"
    echo "❓ Audio cables properly connected (Teensy ↔ Computer)"
    echo "❓ '$DEVICE_NAME' audio device available in macOS"
    echo "❓ Audio input/output routing configured correctly"
    echo ""
    echo "TROUBLESHOOTING STEPS:"
    echo "====================="
    echo "1. Check USB connection and try a different USB port"
    echo "2. Reset the Teensy device (press reset button)"
    echo "3. Verify firmware is loaded and in development mode"
    echo "4. Check audio cable connections"
    echo "5. Restart audio software or reboot if necessary"
    echo ""
    echo "Please resolve hardware issues and try again."

    HARDWARE_VALIDATION_PASSED=false
    return 1
}

# RUNTIME HARDWARE MONITORING
# ============================

# Quick hardware check during recording operations
check_hardware_during_recording() {
    local device_path="${1:-$TEENSY_DEVICE_PATH}"
    local quick_check="${2:-true}"

    if [[ -z "$device_path" ]]; then
        warning "No Teensy device path available for runtime check"
        return 1
    fi

    # Quick connectivity check
    if [[ ! -w "$device_path" ]]; then
        error_log "⚠️  Teensy device no longer accessible: $device_path"
        return 1
    fi

    # Quick audio device check
    if ! check_audio_device; then
        error_log "⚠️  Audio device '$DEVICE_NAME' no longer available"
        return 1
    fi

    # Extended check if requested
    if [[ "$quick_check" != "true" ]]; then
        info "Performing extended hardware check..."

        # Test serial communication
        if ! test_serial_communication "$device_path" 1; then
            warning "Serial communication check failed during recording"
            return 1
        fi

        info "Extended hardware check passed"
    fi

    return 0
}

# HARDWARE RECOVERY FUNCTIONS
# ============================

# Attempt to reset/recover Teensy device
reset_teensy_device() {
    local device_path="${1:-$TEENSY_DEVICE_PATH}"

    info "Attempting to reset/recover Teensy device..."

    if [[ -n "$device_path" && -w "$device_path" ]]; then
        # Try sending a reset command
        info "Sending reset command to Teensy..."
        echo "r" > "$device_path" 2>/dev/null || true
        sleep 2

        # Try to re-establish communication
        if test_serial_communication "$device_path" 3; then
            success "Teensy device reset successfully"
            return 0
        fi
    fi

    # Try to rediscover device
    info "Attempting to rediscover Teensy device..."
    local new_device_path=$(find_teensy_device)

    if [[ -n "$new_device_path" ]]; then
        TEENSY_DEVICE_PATH="$new_device_path"
        info "Teensy device rediscovered at: $new_device_path"

        if test_serial_communication "$new_device_path"; then
            success "Teensy device recovery successful"
            return 0
        fi
    fi

    error_log "Teensy device reset/recovery failed"
    return 1
}

# Monitor hardware status continuously
monitor_hardware_status() {
    local monitoring_duration="${1:-60}"  # seconds
    local check_interval="${2:-10}"       # seconds

    info "Monitoring hardware status for ${monitoring_duration} seconds (checking every ${check_interval}s)..."

    local start_time=$(date +%s)
    local end_time=$((start_time + monitoring_duration))
    local check_count=0
    local failure_count=0

    while [[ $(date +%s) -lt $end_time ]]; do
        ((check_count++))

        info "Hardware check #$check_count..."

        if check_hardware_during_recording "$TEENSY_DEVICE_PATH" "false"; then
            success "Hardware status: OK"
        else
            ((failure_count++))
            warning "Hardware status: FAILED (failure #$failure_count)"

            # Attempt recovery after multiple failures
            if [[ $failure_count -ge 2 ]]; then
                warning "Multiple hardware failures detected, attempting recovery..."
                if reset_teensy_device; then
                    info "Hardware recovery successful, resetting failure count"
                    failure_count=0
                else
                    error_log "Hardware recovery failed"
                fi
            fi
        fi

        sleep "$check_interval"
    done

    echo ""
    echo "Hardware Monitoring Summary:"
    echo "============================"
    echo "Total checks: $check_count"
    echo "Failures: $failure_count"
    echo "Success rate: $(((check_count - failure_count) * 100 / check_count))%"

    if [[ $failure_count -eq 0 ]]; then
        success "Hardware monitoring completed with no failures"
        return 0
    else
        warning "Hardware monitoring completed with $failure_count failures"
        return 1
    fi
}
