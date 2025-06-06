#!/bin/bash
# =============================================================================
# SONGBIRD UTILITIES MODULE
# =============================================================================
#
# General utility functions for directory management, file operations,
# progress reporting, and system utilities.
#
# USAGE:
# ------
# source songbird-core/songbird-utils.sh
#
# FUNCTIONS:
# ----------
# print_header()                       - Format section headers
# print_progress()                     - Show progress indicators
# setup_working_directory()            - Create/setup working directories
# cleanup_old_files()                  - Clean up temporary files
# get_file_info()                      - Get detailed file information
# show_system_info()                   - Display system information
# create_directory_backup()            - Backup directories safely
#
# =============================================================================

# Source required modules
if [[ -z "$SONGBIRD_VERSION" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/songbird-config.sh"
fi

if [[ -z "$ERROR_HANDLING_INITIALIZED" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/songbird-errors.sh"
fi

# DISPLAY AND FORMATTING FUNCTIONS
# =================================

# Print formatted section header
print_header()
{
    local title="$1"
    local width="${2:-80}"
    local char="${3:-=}"

    echo ""
    # Create header line
    printf "%${width}s\n" | tr ' ' "$char"

    # Center title
    local title_length=${#title}
    local padding=$(( (width - title_length - 2) / 2 ))
    printf "%${padding}s %s %${padding}s\n" "" "$title" ""

    # Create footer line
    printf "%${width}s\n" | tr ' ' "$char"
    echo ""
}

# Print progress indicator
print_progress()
{
    local current="$1"
    local total="$2"
    local description="$3"
    local width="${4:-50}"

    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    # Build progress bar
    local bar=""
    for ((i=0; i<filled; i++)); do
        bar+="█"
    done
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done

    # Print progress line
    printf "\r🔄 [%s] %3d%% (%d/%d) %s" "$bar" "$percentage" "$current" "$total" "$description"

    # Add newline if complete
    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

# Show spinner animation
show_spinner()
{
    local pid=$1
    local description="$2"
    local delay=0.1
    local spinstr='|/-\'

    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r🔄 [%c] %s" "$spinstr" "$description"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done

    printf "\r✅ [✓] %s\n" "$description"
}

# Create a visual separator
print_separator()
{
    local width="${1:-80}"
    local char="${2:--}"
    printf "%${width}s\n" | tr ' ' "$char"
}

# DIRECTORY AND FILE MANAGEMENT
# ==============================

# Setup working directory with proper structure
setup_working_directory()
{
    local working_dir="$1"
    local create_subdirs="${2:-true}"

    info "Setting up working directory: $working_dir"

    # Create main working directory
    if ! mkdir -p "$working_dir" 2>/dev/null; then
        error_exit "Failed to create working directory: $working_dir"
    fi

    # Set proper permissions
    chmod 755 "$working_dir" 2>/dev/null || warning "Could not set permissions on $working_dir"

    # Create subdirectories if requested
    if [[ "$create_subdirs" == "true" ]]; then
        for speaker in "${speakers[@]}"; do
            local speaker_dir="$working_dir/$speaker"
            info "Creating speaker directory: $speaker_dir"

            if ! mkdir -p "$speaker_dir" 2>/dev/null; then
                error_exit "Failed to create speaker directory: $speaker_dir"
            fi

            chmod 755 "$speaker_dir" 2>/dev/null || warning "Could not set permissions on $speaker_dir"
        done
    fi

    success "Working directory setup complete"
    return 0
}

# Safe training directory setup with backup handling
setup_training_working_directory()
{
    local working_dir="$1"
    local force_mode="${2:-false}"

    info "Setting up training working directory: $working_dir"

    # Check if directory exists and has content
    if [[ -d "$working_dir" ]]; then
        # Check for existing WAV files
        local existing_wavs=$(find "$working_dir" -name "*.wav" 2>/dev/null | wc -l)

        if [[ $existing_wavs -gt 0 ]]; then
            echo "Found $existing_wavs existing WAV files in $working_dir"

            if [[ "$force_mode" != "true" ]]; then
                echo ""
                echo "This will:"
                echo "  - Create a backup of existing training data"
                echo "  - Clear the working directory for new training data"
                echo ""
                read -p "Continue? (y/N): " -n 1 -r
                echo

                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    info "Operation cancelled by user"
                    return 1
                fi
            fi

            # Create backup
            if ! create_backup "$working_dir" "training-data"; then
                error_exit "Failed to create backup of existing training data"
            fi

            # Clear directory
            info "Clearing working directory..."
            rm -rf "$working_dir"/*
        fi
    fi

    # Create directory structure
    setup_working_directory "$working_dir" true

    return 0
}

# Get comprehensive file information
get_file_info()
{
    local file_path="$1"
    local show_audio_info="${2:-false}"

    if [[ ! -f "$file_path" ]]; then
        error_log "File not found: $file_path"
        return 1
    fi

    echo "File Information: $(basename "$file_path")"
    echo "============================================="
    echo "Full Path: $file_path"

    # Basic file statistics
    if command -v stat >/dev/null; then
        if stat --version 2>/dev/null | grep -q GNU; then
            # GNU stat (Linux)
            echo "Size: $(stat --format="%s bytes" "$file_path")"
            echo "Modified: $(stat --format="%y" "$file_path")"
            echo "Permissions: $(stat --format="%A" "$file_path")"
        else
            # BSD stat (macOS)
            echo "Size: $(stat -f%z "$file_path") bytes"
            echo "Modified: $(stat -f%Sm "$file_path")"
            echo "Permissions: $(stat -f%Sp "$file_path")"
        fi
    else
        # Fallback using ls
        local ls_output=$(ls -la "$file_path")
        echo "Details: $ls_output"
    fi

    # Audio-specific information
    if [[ "$show_audio_info" == "true" && "${file_path,,}" =~ \.(wav|mp3|aiff|flac)$ ]]; then
        echo ""
        echo "Audio Information:"
        echo "=================="

        # Try with soxi (from SoX)
        if command -v soxi >/dev/null; then
            soxi "$file_path" 2>/dev/null || echo "Could not read audio info with soxi"
        # Try with ffprobe (from FFmpeg)
        elif command -v ffprobe >/dev/null; then
            ffprobe -v quiet -show_format -show_streams "$file_path" 2>/dev/null || echo "Could not read audio info with ffprobe"
        else
            echo "No audio analysis tools available (install sox or ffmpeg)"
        fi
    fi
}

# Clean up temporary and old files
cleanup_old_files()
{
    local directory="$1"
    local age_days="${2:-7}"
    local pattern="${3:-*.tmp}"
    local dry_run="${4:-false}"

    if [[ ! -d "$directory" ]]; then
        warning "Directory not found for cleanup: $directory"
        return 1
    fi

    info "Cleaning up files older than $age_days days in: $directory"
    info "Pattern: $pattern"

    local find_cmd="find \"$directory\" -name \"$pattern\" -type f -mtime +$age_days"

    if [[ "$dry_run" == "true" ]]; then
        echo "DRY RUN - Files that would be deleted:"
        eval "$find_cmd" -ls 2>/dev/null || echo "No matching files found"
    else
        local file_count=$(eval "$find_cmd" 2>/dev/null | wc -l)

        if [[ $file_count -gt 0 ]]; then
            info "Found $file_count files to delete"
            eval "$find_cmd" -delete 2>/dev/null
            success "Cleanup completed - $file_count files removed"
        else
            info "No files found matching cleanup criteria"
        fi
    fi

    return 0
}

# BACKUP SYSTEM INTEGRATION
# ==========================

# Create directory backup using the backup system
create_backup()
{
    local source_dir="$1"
    local backup_name="${2:-$(basename "$source_dir")}"

    if [[ ! -d "$source_dir" ]]; then
        warning "No existing directory to backup: $source_dir"
        return 0
    fi

    # Check if directory has content
    if [[ -z "$(find "$source_dir" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
        info "Directory $source_dir is empty, skipping backup"
        return 0
    fi

    # Create backup root directory
    mkdir -p "$BACKUP_ROOT_DIR"

    # Generate timestamp and backup path
    local timestamp=$(date +"$BACKUP_TIMESTAMP_FORMAT")
    local backup_dir="$BACKUP_ROOT_DIR/${backup_name}_${timestamp}"

    # Calculate size
    local source_size
    if command -v du >/dev/null 2>&1; then
        source_size=$(du -sh "$source_dir" 2>/dev/null | cut -f1 || echo "unknown")
    else
        source_size="unknown"
    fi

    info "Creating backup of $source_dir (${source_size})..."
    info "Backup location: $backup_dir"

    # Create the backup
    if cp -R "$source_dir" "$backup_dir" 2>/dev/null; then
        success "Backup created successfully: $backup_dir"

        # Log backup creation
        echo "$(date): Backup created - $backup_dir (source: $source_dir, size: $source_size)" >> "$BACKUP_ROOT_DIR/backup_log.txt"

        # Clean up old backups
        cleanup_old_backups "$backup_name"

        return 0
    else
        error_log "Failed to create backup of $source_dir"
        return 1
    fi
}

# Clean up old backups
cleanup_old_backups()
{
    local backup_prefix="$1"

    # Find all backups for this prefix and sort by creation time (newest first)
    local backup_dirs=($(find "$BACKUP_ROOT_DIR" -maxdepth 1 -type d -name "${backup_prefix}_*" 2>/dev/null | sort -r))

    # If we have more backups than the limit, remove the oldest ones
    if [[ ${#backup_dirs[@]} -gt $MAX_BACKUPS_TO_KEEP ]]; then
        info "Found ${#backup_dirs[@]} backups for $backup_prefix, keeping newest $MAX_BACKUPS_TO_KEEP..."

        # Remove backups beyond the limit
        for (( i=$MAX_BACKUPS_TO_KEEP; i<${#backup_dirs[@]}; i++ )); do
            local old_backup="${backup_dirs[$i]}"
            info "Removing old backup: $(basename "$old_backup")"
            rm -rf "$old_backup"

            # Log cleanup
            echo "$(date): Old backup removed - $old_backup" >> "$BACKUP_ROOT_DIR/backup_log.txt"
        done
    fi
}

# SYSTEM INFORMATION AND DIAGNOSTICS
# ===================================

# Show comprehensive system information
show_system_info() {
    local show_detailed="${1:-false}"

    print_header "System Information"

    # Basic system info
    echo "Operating System: $(uname -s) $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Hostname: $(hostname)"
    echo "User: $(whoami)"
    echo "Current Directory: $(pwd)"
    echo ""

    # Hardware information (macOS specific)
    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "Hardware Information:"
        echo "===================="

        if command -v system_profiler >/dev/null; then
            # CPU information
            echo "CPU: $(system_profiler SPHardwareDataType | grep "Processor Name" | cut -d: -f2 | xargs)"
            echo "CPU Cores: $(sysctl -n hw.ncpu)"
            echo "Memory: $(system_profiler SPHardwareDataType | grep "Memory" | cut -d: -f2 | xargs)"
        fi

        if command -v sysctl >/dev/null; then
            echo "CPU Cores: $(sysctl -n hw.ncpu)"
            echo "Memory: $(echo "$(sysctl -n hw.memsize) / 1024 / 1024 / 1024" | bc) GB"
        fi
        echo ""
    fi

    # Disk space information
    echo "Disk Space Information:"
    echo "======================"
    df -h . 2>/dev/null || echo "Could not retrieve disk space information"
    echo ""

    # Audio system information
    echo "Audio System:"
    echo "============="
    if command -v SwitchAudioSource >/dev/null; then
        echo "Current Input: $(SwitchAudioSource -c -t input 2>/dev/null || echo "Unknown")"
        echo "Current Output: $(SwitchAudioSource -c -t output 2>/dev/null || echo "Unknown")"
    else
        echo "SwitchAudioSource not available"
    fi
    echo ""

    # Python environment
    echo "Python Environment:"
    echo "=================="
    if command -v "$PYTHON_CMD" >/dev/null; then
        echo "Python Version: $("$PYTHON_CMD" --version 2>&1)"
        echo "Python Path: $(which "$PYTHON_CMD")"

        # Check for key modules
        local modules=("numpy" "pandas" "librosa" "matplotlib")
        echo ""
        echo "Python Modules:"
        for module in "${modules[@]}"; do
            if "$PYTHON_CMD" -c "import $module" 2>/dev/null; then
                local version=$("$PYTHON_CMD" -c "import $module; print($module.__version__)" 2>/dev/null || echo "unknown")
                echo "  ✅ $module ($version)"
            else
                echo "  ❌ $module (not installed)"
            fi
        done
    else
        echo "Python not found"
    fi
    echo ""

    # Songbird-specific information
    echo "Songbird Configuration:"
    echo "======================"
    echo "Version: $SONGBIRD_VERSION"
    echo "Core Directory: $SONGBIRD_CORE_DIR"
    echo "Project Root: $PROJECT_ROOT"
    echo "Working Directory: $WORKING_DIR"
    echo "Max Audio Time: ${MAX_TIME}s"
    echo "Speakers: ${speakers[*]}"
    echo "Modes: ${mode_names[*]}"
    echo ""

    # Show detailed information if requested
    if [[ "$show_detailed" == "true" ]]; then
        echo "Detailed Environment Variables:"
        echo "=============================="
        env | grep -E "(SONGBIRD|PYTHON|PATH)" | sort
        echo ""

        echo "Available Commands:"
        echo "=================="
        local commands=("sox" "ffmpeg" "SwitchAudioSource" "afplay" "rec")
        for cmd in "${commands[@]}"; do
            if command -v "$cmd" >/dev/null; then
                echo "  ✅ $cmd: $(which "$cmd")"
            else
                echo "  ❌ $cmd: not found"
            fi
        done
    fi
}

# Check system load and resources
check_system_load() {
    local warn_threshold="${1:-80}"  # Warn if CPU/memory usage > 80%

    echo "System Resource Check:"
    echo "====================="

    # Check CPU load
    if command -v uptime >/dev/null; then
        local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        local num_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "1")
        local load_percent=$(echo "scale=0; $load_avg * 100 / $num_cores" | bc 2>/dev/null || echo "0")

        echo "CPU Load: $load_avg (${load_percent}% of $num_cores cores)"

        if [[ $load_percent -gt $warn_threshold ]]; then
            warning "High CPU load detected (${load_percent}%)"
        fi
    fi

    # Check memory usage (macOS)
    if command -v vm_stat >/dev/null; then
        local vm_info=$(vm_stat)
        local pages_free=$(echo "$vm_info" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        local pages_active=$(echo "$vm_info" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
        local pages_inactive=$(echo "$vm_info" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
        local pages_wired=$(echo "$vm_info" | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')

        if [[ -n "$pages_free" && -n "$pages_active" ]]; then
            local total_pages=$((pages_free + pages_active + pages_inactive + pages_wired))
            local used_pages=$((total_pages - pages_free))
            local memory_percent=$((used_pages * 100 / total_pages))

            echo "Memory Usage: ${memory_percent}%"

            if [[ $memory_percent -gt $warn_threshold ]]; then
                warning "High memory usage detected (${memory_percent}%)"
            fi
        fi
    fi

    # Check disk space
    local disk_usage=$(df . | awk 'NR==2 {print $5}' | sed 's/%//')
    echo "Disk Usage: ${disk_usage}%"

    if [[ $disk_usage -gt $warn_threshold ]]; then
        warning "High disk usage detected (${disk_usage}%)"
    fi

    echo ""
}

# SPEAKER MANAGEMENT UTILITIES
# =============================

# Validate speaker configuration
validate_speaker_config() {
    info "Validating speaker configuration..."

    local config_errors=()

    # Check if arrays have matching lengths
    if [[ ${#speakers[@]} -ne ${#speaker_urls[@]} ]]; then
        config_errors+=("Speaker IDs and URLs arrays have different lengths")
    fi

    if [[ ${#speakers[@]} -ne ${#speaker_cleanup_patterns[@]} ]]; then
        config_errors+=("Speaker IDs and cleanup patterns arrays have different lengths")
    fi

    # Validate each speaker configuration
    for i in "${!speakers[@]}"; do
        local speaker_id="${speakers[$i]}"
        local speaker_url="${speaker_urls[$i]}"
        local cleanup_pattern="${speaker_cleanup_patterns[$i]}"

        # Check speaker ID format
        if [[ ! "$speaker_id" =~ ^[0-9]+$ ]]; then
            config_errors+=("Invalid speaker ID format: $speaker_id")
        fi

        # Check URL format
        if [[ ! "$speaker_url" =~ ^https?:// ]]; then
            config_errors+=("Invalid URL format for speaker $speaker_id: $speaker_url")
        fi

        # Cleanup pattern is just validated for being non-empty
        if [[ -z "$cleanup_pattern" ]]; then
            config_errors+=("Empty cleanup pattern for speaker $speaker_id")
        fi
    done

    # Report validation results
    if [[ ${#config_errors[@]} -eq 0 ]]; then
        success "Speaker configuration validation passed"

        echo "Configured Speakers:"
        for i in "${!speakers[@]}"; do
            echo "  ${speakers[$i]}: ${speaker_urls[$i]}"
        done

        return 0
    else
        error_log "Speaker configuration validation failed:"
        for error in "${config_errors[@]}"; do
            error_log "  - $error"
        done
        return 1
    fi
}

# Show detailed speaker information
show_speaker_info() {
    print_header "Speaker Configuration"

    echo "Total Speakers: ${#speakers[@]}"
    echo ""

    for i in "${!speakers[@]}"; do
        local speaker_id="${speakers[$i]}"
        echo "Speaker #$((i+1)): $speaker_id"
        echo "  URL: ${speaker_urls[$i]}"
        echo "  Cleanup: ${speaker_cleanup_patterns[$i]}"

        # Check if speaker directory exists
        local speaker_dir="$SPEAKERS_DIR/$speaker_id"
        if [[ -d "$speaker_dir" ]]; then
            local file_count=$(find "$speaker_dir" -name "*.mp3" 2>/dev/null | wc -l)
            echo "  Status: ✅ Directory exists ($file_count MP3 files)"
        else
            echo "  Status: ❌ Directory not found"
        fi
        echo ""
    done
}
