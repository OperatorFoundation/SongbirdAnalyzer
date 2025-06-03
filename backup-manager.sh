#!/bin/bash
# =============================================================================
# BACKUP MANAGEMENT UTILITY
# =============================================================================
#
# Provides backup and restore capabilities for Songbird evaluation data.
#
# COMMANDS:
# ---------
# list                    - List all available backups
# stats                   - Show backup statistics and disk usage
# restore <backup> <dir>  - Restore a specific backup to directory
# create <source> [name]  - Manually create backup of source directory
# cleanup [pattern]       - Remove old backups beyond retention limit
#
# EXAMPLES:
# ---------
# ./backup-manager.sh list
# ./backup-manager.sh restore working-evaluation_20241203_143022 working-evaluation
# ./backup-manager.sh create working-evaluation my-important-session
# ./backup-manager.sh stats
#
# INTEGRATION:
# ------------
# Automatically called by evaluation scripts for data protection
# Can be used manually for backup management
#
# =============================================================================

# Source common functions to get backup functionality
source songbird-common.sh

show_usage() {
    echo "Backup Manager for Songbird Evaluation Data"
    echo ""
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  list                     List all available backups"
    echo "  stats                    Show backup statistics and disk usage"
    echo "  restore <backup> <dir>   Restore backup to specified directory"
    echo "  create <source> [name]   Create backup of source directory"
    echo "  cleanup [pattern]        Clean up old backups (optional pattern filter)"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 restore working-evaluation_20241203_143022 working-evaluation"
    echo "  $0 create working-evaluation my-important-session"
    echo "  $0 stats"
    echo ""
}

case "${1:-}" in
    "list")
        pattern="${2:-*}"
        list_backups "$pattern"
        ;;

    "stats")
        show_backup_stats
        ;;

    "restore")
        if [ $# -lt 3 ]; then
            echo "ERROR: restore command requires backup name and target directory"
            echo "Usage: $0 restore <backup_name> <target_directory>"
            echo ""
            echo "Available backups:"
            list_backups
            exit 1
        fi
        restore_backup "$2" "$3"
        ;;

    "create")
        if [ $# -lt 2 ]; then
            echo "ERROR: create command requires source directory"
            echo "Usage: $0 create <source_directory> [backup_name]"
            exit 1
        fi
        backup_name="${3:-$(basename "$2")}"
        create_backup "$2" "$backup_name"
        ;;

    "cleanup")
        pattern="${2:-*}"
        echo "Cleaning up old backups for pattern: ${pattern}"
        cleanup_old_backups "$pattern"
        ;;

    "help"|"--help"|"-h")
        show_usage
        ;;

    "")
        echo "ERROR: No command specified"
        echo ""
        show_usage
        exit 1
        ;;

    *)
        echo "ERROR: Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac