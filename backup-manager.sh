#!/bin/bash

# =============================================================================
# BACKUP MANAGEMENT SYSTEM
# =============================================================================
#
# Backup and recovery system for Songbird project data.
# Provides automated backup creation, restoration, and management with
# configurable retention policies and integrity validation.
#
# USAGE:
# ------
# ./backup-manager.sh create [target]     # Create backup
# ./backup-manager.sh restore <backup>    # Restore backup
# ./backup-manager.sh list                # List backups
# ./backup-manager.sh cleanup              # Clean old backups
# ./backup-manager.sh verify <backup>     # Verify backup integrity
#
# BACKUP STRUCTURE:
# -----------------
# backups/
# ├── 20240101_120000_full/              # Full system backup
# ├── 20240101_120500_models/            # Models only backup
# ├── 20240101_121000_results/           # Results only backup
# └── checksums.md5                      # Integrity verification
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
readonly BACKUP_ROOT_DIRECTORY="backups"
readonly BACKUP_TIMESTAMP_FORMAT="%Y%m%d_%H%M%S"
readonly CHECKSUM_FILE_NAME="checksums.md5"
readonly DEFAULT_MAX_BACKUPS_TO_KEEP=5
readonly BACKUP_COMPRESSION_LEVEL=6

# Backup target definitions (parallel arrays for bash 3.x compatibility)
BACKUP_TARGET_NAMES=("full" "models" "results" "working" "audio")
BACKUP_TARGET_DIRS=(
    "models results audio working-training working-evaluation"  # full
    "models"                                                    # models
    "results"                                                   # results
    "working-training working-evaluation"                       # working
    "audio"                                                     # audio
)

# Get directories for a backup target
get_backup_target_dirs() {
    local target="$1"
    local i

    for i in "${!BACKUP_TARGET_NAMES[@]}"; do
        if [[ "${BACKUP_TARGET_NAMES[i]}" == "$target" ]]; then
            echo "${BACKUP_TARGET_DIRS[i]}"
            return 0
        fi
    done
    return 1
}

# Check if backup target is valid
is_valid_backup_target() {
    local target="$1"
    local valid_target

    for valid_target in "${BACKUP_TARGET_NAMES[@]}"; do
        if [[ "$valid_target" == "$target" ]]; then
            return 0
        fi
    done
    return 1
}

# Backup operation modes
BACKUP_MODE=""
BACKUP_TARGET=""
RESTORE_SOURCE=""
VERIFICATION_TARGET=""
FORCE_MODE=false
VERBOSE_OPERATIONS=false

# Parse command line arguments
parse_arguments()
{
    if [[ $# -lt 1 ]]
    then
        show_usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        create)
            BACKUP_MODE="create"
            BACKUP_TARGET="${1:-full}"
            ;;
        restore)
            BACKUP_MODE="restore"
            if [[ $# -lt 1 ]]
            then
                error_exit "Restore command requires backup directory argument"
            fi
            RESTORE_SOURCE="$1"
            shift
            ;;
        list)
            BACKUP_MODE="list"
            ;;
        cleanup)
            BACKUP_MODE="cleanup"
            ;;
        verify)
            BACKUP_MODE="verify"
            if [[ $# -lt 1 ]]
            then
                error_exit "Verify command requires backup directory argument"
            fi
            VERIFICATION_TARGET="$1"
            shift
            ;;
        *)
            error_exit "Unknown command: $command. Use --help for usage information."
            ;;
    esac

    # Parse additional options
    for arg in "$@"
    do
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
SONGBIRD BACKUP MANAGEMENT SYSTEM

USAGE:
    $0 <command> [options]

COMMANDS:
    create [target]    Create a new backup (default: full)
    restore <backup>   Restore from specified backup directory
    list              List all available backups
    cleanup           Remove old backups according to retention policy
    verify <backup>   Verify backup integrity using checksums

BACKUP TARGETS:
    full              Complete system backup (default)
    models            Machine learning models only
    results           Results and analysis data only
    working           Working directories only
    audio             Audio training data only

OPTIONS:
    --force           Skip confirmation prompts
    --verbose, -v     Enable verbose output
    --help, -h        Show this help message

EXAMPLES:
    $0 create                    # Create full system backup
    $0 create models             # Backup models directory only
    $0 restore 20240101_120000_full  # Restore from specific backup
    $0 list                      # Show all available backups
    $0 cleanup                   # Clean old backups
    $0 verify 20240101_120000_full   # Verify backup integrity

BACKUP LOCATION:
    All backups are stored in: $BACKUP_ROOT_DIRECTORY/

RETENTION POLICY:
    Maximum backups kept: $DEFAULT_MAX_BACKUPS_TO_KEEP
    Oldest backups are automatically removed during cleanup.

For more information, see the project documentation.
EOF
}

# Validate backup target
validate_backup_target()
{
    local target="$1"
    local target_dirs

    if ! is_valid_backup_target "$target"
    then
        error_exit "Invalid backup target: $target
Valid targets: ${BACKUP_TARGET_NAMES[*]}"
    fi

    target_dirs=$(get_backup_target_dirs "$target")

    # Check if target directories exist
    local missing_dirs=()
    for dir in $target_dirs
    do
        if [[ ! -d "$dir" ]]
        then
            missing_dirs+=("$dir")
        fi
    done

    if [[ ${#missing_dirs[@]} -gt 0 ]]
    then
        warning "Some target directories do not exist: ${missing_dirs[*]}"
        if [[ "$FORCE_MODE" != "true" ]]
        then
            if ! confirm_action "Continue backup without missing directories?"
            then
                error_exit "Backup cancelled due to missing directories"
            fi
        fi
    fi

    info "✅ Backup target '$target' validated"
}

# Create backup directory structure
create_backup_directory()
{
    local backup_name="$1"
    local backup_dir="$BACKUP_ROOT_DIRECTORY/$backup_name"

    info "Creating backup directory: $backup_dir"

    # Ensure backup root exists
    if ! mkdir -p "$BACKUP_ROOT_DIRECTORY"
    then
        error_exit "Failed to create backup root directory: $BACKUP_ROOT_DIRECTORY"
    fi

    # Check if backup already exists
    if [[ -d "$backup_dir" ]]
    then
        if [[ "$FORCE_MODE" == "true" ]]
        then
            warning "Overwriting existing backup: $backup_name"
            if ! rm -rf "$backup_dir"
            then
                error_exit "Failed to remove existing backup directory"
            fi
        else
            if ! confirm_action "Backup '$backup_name' already exists. Overwrite?"
            then
                error_exit "Backup cancelled to avoid overwriting existing data"
            fi
            if ! rm -rf "$backup_dir"
            then
                error_exit "Failed to remove existing backup directory"
            fi
        fi
    fi

    # Create new backup directory
    if ! mkdir -p "$backup_dir"
    then
        error_exit "Failed to create backup directory: $backup_dir"
    fi

    echo "$backup_dir"
}

# Copy directory with progress reporting
copy_directory_with_progress()
{
    local source_dir="$1"
    local destination_dir="$2"
    local description="$3"

    if [[ ! -d "$source_dir" ]]
    then
        warning "Source directory does not exist, skipping: $source_dir"
        return 0
    fi

    info "Copying $description: $source_dir → $destination_dir"

    # Count files for progress reporting
    local total_files
    total_files=$(find "$source_dir" -type f 2>/dev/null | wc -l)
    info "  Files to copy: $total_files"

    # Copy with rsync for better progress and error handling
    if command -v rsync &>/dev/null
    then
        local rsync_options="-av"
        if [[ "$VERBOSE_OPERATIONS" == "true" ]]
        then
            rsync_options="${rsync_options} --progress"
        fi

        if run_with_error_handling "Copying $description" \
            rsync $rsync_options "$source_dir/" "$destination_dir/"
        then
            local copied_files
            copied_files=$(find "$destination_dir" -type f 2>/dev/null | wc -l)
            success "✅ Copied $copied_files files for $description"
        else
            error_exit "Failed to copy $description from $source_dir"
        fi
    else
        # Fallback to cp if rsync is not available
        warning "rsync not available, using cp (no progress reporting)"
        if run_with_error_handling "Copying $description" \
            cp -r "$source_dir" "$(dirname "$destination_dir")"
        then
            success "✅ Copied $description"
        else
            error_exit "Failed to copy $description from $source_dir"
        fi
    fi
}

# Generate checksums for backup verification
generate_backup_checksums()
{
    local backup_dir="$1"
    local checksum_file="$backup_dir/$CHECKSUM_FILE_NAME"

    info "Generating checksums for backup verification..."

    # Generate MD5 checksums for all files
    if command -v find &>/dev/null && command -v md5sum &>/dev/null
    then
        find "$backup_dir" -type f ! -name "$CHECKSUM_FILE_NAME" -exec md5sum {} + > "$checksum_file" 2>/dev/null
    elif command -v find &>/dev/null && command -v md5 &>/dev/null
    then
        # macOS fallback
        find "$backup_dir" -type f ! -name "$CHECKSUM_FILE_NAME" -exec md5 -r {} + | sed 's/MD5 (\(.*\)) = \(.*\)/\2  \1/' > "$checksum_file" 2>/dev/null
    else
        warning "No suitable checksum tool found. Backup verification will not be available."
        return 1
    fi

    if [[ -f "$checksum_file" ]]
    then
        local checksum_count
        checksum_count=$(wc -l < "$checksum_file" 2>/dev/null || echo "0")
        success "✅ Generated checksums for $checksum_count files"
        return 0
    else
        warning "Failed to generate checksums"
        return 1
    fi
}

# Create backup
execute_backup_creation()
{
    local target="$1"
    local timestamp
    timestamp=$(date +"$BACKUP_TIMESTAMP_FORMAT")
    local backup_name="${timestamp}_${target}"

    print_header "CREATING BACKUP: $backup_name"

    # Validate target and create backup directory
    validate_backup_target "$target"
    local backup_dir
    backup_dir=$(create_backup_directory "$backup_name")

    # Track backup statistics
    local backup_start_time
    backup_start_time=$(date +%s)
    local total_size=0

    # Copy each target directory
    local copied_targets=()
    local target_dirs
    target_dirs=$(get_backup_target_dirs "$target")
    for source_dir in $target_dirs
    do
        if [[ -d "$source_dir" ]]
        then
            local destination_dir="$backup_dir/$source_dir"
            copy_directory_with_progress "$source_dir" "$destination_dir" "$source_dir"
            copied_targets+=("$source_dir")

            # Calculate size
            local dir_size
            dir_size=$(du -s "$destination_dir" 2>/dev/null | cut -f1 || echo "0")
            total_size=$((total_size + dir_size))
        else
            warning "Target directory not found, skipping: $source_dir"
        fi
    done

    # Generate checksums
    generate_backup_checksums "$backup_dir"

    # Calculate backup completion time
    local backup_end_time
    backup_end_time=$(date +%s)
    local backup_duration=$((backup_end_time - backup_start_time))

    # Create backup metadata
    local metadata_file="$backup_dir/backup_metadata.txt"
    {
        echo "SONGBIRD BACKUP METADATA"
        echo "========================"
        echo "Backup name: $backup_name"
        echo "Target: $target"
        echo "Created: $(date)"
        echo "Duration: $backup_duration seconds"
        echo "Total size: $total_size KB"
        echo "Copied targets: ${copied_targets[*]}"
        echo "Checksum file: $CHECKSUM_FILE_NAME"
        echo ""
        echo "Generated by Songbird Backup Manager v$SONGBIRD_VERSION"
    } > "$metadata_file"

    success "Backup created successfully: $backup_name"
    info "Backup location: $backup_dir"
    info "Backup size: $total_size KB"
    info "Duration: $backup_duration seconds"
}

# List available backups
list_available_backups()
{
    print_header "AVAILABLE BACKUPS"

    if [[ ! -d "$BACKUP_ROOT_DIRECTORY" ]]
    then
        info "No backups found. Backup directory does not exist: $BACKUP_ROOT_DIRECTORY"
        return 0
    fi

    local backup_dirs=()
    while IFS= read -r -d '' dir
    do
        backup_dirs+=("$dir")
    done < <(find "$BACKUP_ROOT_DIRECTORY" -maxdepth 1 -type d ! -path "$BACKUP_ROOT_DIRECTORY" -print0 2>/dev/null | sort -z)

    if [[ ${#backup_dirs[@]} -eq 0 ]]
    then
        info "No backups found in $BACKUP_ROOT_DIRECTORY"
        return 0
    fi

    echo "Found ${#backup_dirs[@]} backup(s):"
    echo "============================"

    for backup_dir in "${backup_dirs[@]}"
    do
        local backup_name
        backup_name=$(basename "$backup_dir")

        # Get backup information
        local backup_size="unknown"
        local backup_date="unknown"
        local backup_target="unknown"

        if [[ -d "$backup_dir" ]]
        then
            backup_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1 || echo "unknown")

            # Extract info from metadata if available
            local metadata_file="$backup_dir/backup_metadata.txt"
            if [[ -f "$metadata_file" ]]
            then
                backup_date=$(grep "^Created:" "$metadata_file" 2>/dev/null | cut -d: -f2- | xargs || echo "unknown")
                backup_target=$(grep "^Target:" "$metadata_file" 2>/dev/null | cut -d: -f2 | xargs || echo "unknown")
            fi
        fi

        echo "📁 $backup_name"
        echo "   Size: $backup_size"
        echo "   Target: $backup_target"
        echo "   Created: $backup_date"

        # Check for checksum file
        if [[ -f "$backup_dir/$CHECKSUM_FILE_NAME" ]]
        then
            echo "   Verification: ✅ Available"
        else
            echo "   Verification: ❌ No checksums"
        fi
        echo ""
    done
}

# Verify backup integrity
verify_backup_integrity()
{
    local backup_name="$1"
    local backup_dir="$BACKUP_ROOT_DIRECTORY/$backup_name"
    local checksum_file="$backup_dir/$CHECKSUM_FILE_NAME"

    print_header "VERIFYING BACKUP: $backup_name"

    # Validate backup directory exists
    if [[ ! -d "$backup_dir" ]]
    then
        error_exit "Backup directory not found: $backup_dir"
    fi

    # Check for checksum file
    if [[ ! -f "$checksum_file" ]]
    then
        error_exit "Checksum file not found: $checksum_file
Backup verification is not possible without checksums."
    fi

    info "Verifying backup integrity using checksums..."

    # Verify checksums
    local verification_result
    if command -v md5sum &>/dev/null
    then
        if cd "$backup_dir" && md5sum -c "$CHECKSUM_FILE_NAME" >/dev/null 2>&1
        then
            verification_result=0
        else
            verification_result=1
        fi
    elif command -v md5 &>/dev/null
    then
        # macOS verification
        local failed_files=0
        while IFS= read -r line
        do
            if [[ -n "$line" ]]
            then
                local expected_hash file_path
                expected_hash=$(echo "$line" | cut -d' ' -f1)
                file_path=$(echo "$line" | cut -d' ' -f3-)

                if [[ -f "$backup_dir/$file_path" ]]
                then
                    local actual_hash
                    actual_hash=$(md5 -q "$backup_dir/$file_path" 2>/dev/null)
                    if [[ "$actual_hash" != "$expected_hash" ]]
                    then
                        ((failed_files++))
                        if [[ "$VERBOSE_OPERATIONS" == "true" ]]
                        then
                            warning "Checksum mismatch: $file_path"
                        fi
                    fi
                else
                    ((failed_files++))
                    if [[ "$VERBOSE_OPERATIONS" == "true" ]]
                    then
                        warning "Missing file: $file_path"
                    fi
                fi
            fi
        done < "$checksum_file"

        verification_result=$failed_files
    else
        error_exit "No suitable checksum verification tool found"
    fi

    # Report verification results
    if [[ $verification_result -eq 0 ]]
    then
        success "✅ Backup verification passed: $backup_name"
        success "All files are intact and match expected checksums"
    else
        error_exit "❌ Backup verification failed: $backup_name
$verification_result file(s) failed verification or are missing"
    fi
}

# Restore from backup
execute_backup_restoration()
{
    local backup_name="$1"
    local backup_dir="$BACKUP_ROOT_DIRECTORY/$backup_name"

    print_header "RESTORING FROM BACKUP: $backup_name"

    # Validate backup directory exists
    if [[ ! -d "$backup_dir" ]]
    then
        error_exit "Backup directory not found: $backup_dir"
    fi

    # Verify backup integrity before restoration
    info "Verifying backup integrity before restoration..."
    if [[ -f "$backup_dir/$CHECKSUM_FILE_NAME" ]]
    then
        verify_backup_integrity "$backup_name"
    else
        warning "No checksums available for verification"
        if [[ "$FORCE_MODE" != "true" ]]
        then
            if ! confirm_action "Continue restoration without verification?"
            then
                error_exit "Restoration cancelled for safety"
            fi
        fi
    fi

    # Get list of directories to restore
    local restore_dirs=()
    while IFS= read -r -d '' dir
    do
        local dir_name
        dir_name=$(basename "$dir")
        # Skip metadata and checksum files
        if [[ "$dir_name" != "$CHECKSUM_FILE_NAME" && "$dir_name" != "backup_metadata.txt" ]]
        then
            restore_dirs+=("$dir")
        fi
    done < <(find "$backup_dir" -maxdepth 1 -type d ! -path "$backup_dir" -print0 2>/dev/null)

    if [[ ${#restore_dirs[@]} -eq 0 ]]
    then
        error_exit "No directories found to restore in backup: $backup_name"
    fi

    # Confirm restoration
    if [[ "$FORCE_MODE" != "true" ]]
    then
        echo "The following directories will be restored:"
        for dir in "${restore_dirs[@]}"
        do
            local dir_name
            dir_name=$(basename "$dir")
            echo "  - $dir_name"
        done
        echo ""

        if ! confirm_action "This will overwrite existing files. Continue with restoration?"
        then
            error_exit "Restoration cancelled by user"
        fi
    fi

    # Restore each directory
    local restoration_start_time
    restoration_start_time=$(date +%s)
    local restored_count=0

    for source_dir in "${restore_dirs[@]}"
    do
        local dir_name
        dir_name=$(basename "$source_dir")
        local destination_dir="./$dir_name"

        info "Restoring: $dir_name"

        # Create backup of existing directory if it exists
        if [[ -d "$destination_dir" ]]
        then
            local backup_suffix
            backup_suffix=$(date +"$BACKUP_TIMESTAMP_FORMAT")
            local existing_backup="${destination_dir}.backup_${backup_suffix}"

            info "  Creating backup of existing directory: $existing_backup"
            if ! mv "$destination_dir" "$existing_backup"
            then
                error_exit "Failed to backup existing directory: $destination_dir"
            fi
        fi

        # Copy from backup
        if copy_directory_with_progress "$source_dir" "$destination_dir" "$dir_name"
        then
            ((restored_count++))
            success "✅ Restored: $dir_name"
        else
            error_exit "Failed to restore directory: $dir_name"
        fi
    done

    # Calculate restoration completion time
    local restoration_end_time
    restoration_end_time=$(date +%s)
    local restoration_duration=$((restoration_end_time - restoration_start_time))

    success "Restoration completed successfully"
    info "Restored directories: $restored_count"
    info "Duration: $restoration_duration seconds"
    info "Source backup: $backup_name"
}

# Clean old backups according to retention policy
cleanup_old_backups()
{
    print_header "CLEANING OLD BACKUPS"

    if [[ ! -d "$BACKUP_ROOT_DIRECTORY" ]]
    then
        info "No backup directory found. Nothing to clean."
        return 0
    fi

    # Get list of backup directories sorted by modification time (oldest first)
    local backup_dirs=()
    while IFS= read -r -d '' dir
    do
        backup_dirs+=("$dir")
    done < <(find "$BACKUP_ROOT_DIRECTORY" -maxdepth 1 -type d ! -path "$BACKUP_ROOT_DIRECTORY" -print0 2>/dev/null | xargs -0 ls -dt | tac)

    local total_backups=${#backup_dirs[@]}

    if [[ $total_backups -le $DEFAULT_MAX_BACKUPS_TO_KEEP ]]
    then
        success "No cleanup needed. Current backups: $total_backups, limit: $DEFAULT_MAX_BACKUPS_TO_KEEP"
        return 0
    fi

    local backups_to_remove=$((total_backups - DEFAULT_MAX_BACKUPS_TO_KEEP))

    info "Found $total_backups backups, keeping $DEFAULT_MAX_BACKUPS_TO_KEEP newest"
    info "Will remove $backups_to_remove old backup(s)"

    # Show backups that will be removed
    echo ""
    echo "Backups to be removed:"
    for ((i=0; i<backups_to_remove; i++))
    do
        local backup_name
        backup_name=$(basename "${backup_dirs[i]}")
        local backup_size
        backup_size=$(du -sh "${backup_dirs[i]}" 2>/dev/null | cut -f1 || echo "unknown")
        echo "  - $backup_name ($backup_size)"
    done

    # Confirm removal
    if [[ "$FORCE_MODE" != "true" ]]
    then
        echo ""
        if ! confirm_action "Remove these $backups_to_remove old backup(s)?"
        then
            info "Cleanup cancelled by user"
            return 0
        fi
    fi

    # Remove old backups
    local removed_count=0
    for ((i=0; i<backups_to_remove; i++))
    do
        local backup_dir="${backup_dirs[i]}"
        local backup_name
        backup_name=$(basename "$backup_dir")

        info "Removing old backup: $backup_name"

        if run_with_error_handling "Removing backup $backup_name" \
            rm -rf "$backup_dir"
        then
            ((removed_count++))
            success "✅ Removed: $backup_name"
        else
            warning "Failed to remove: $backup_name"
        fi
    done

    success "Cleanup completed. Removed $removed_count backup(s)"

    # Show remaining backups
    local remaining_backups=$((total_backups - removed_count))
    info "Remaining backups: $remaining_backups"
}

# Main execution function
main()
{
    parse_arguments "$@"

    case "$BACKUP_MODE" in
        create)
            execute_backup_creation "$BACKUP_TARGET"
            ;;
        restore)
            execute_backup_restoration "$RESTORE_SOURCE"
            ;;
        list)
            list_available_backups
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        verify)
            verify_backup_integrity "$VERIFICATION_TARGET"
            ;;
        *)
            error_exit "Invalid backup mode: $BACKUP_MODE"
            ;;
    esac

    success "Backup operation completed successfully"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
    main "$@"
fi