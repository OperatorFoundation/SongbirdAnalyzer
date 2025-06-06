#!/bin/bash
# =============================================================================
# SONGBIRD CORE MODULE LOADER
# =============================================================================
#
# Master loader for all Songbird core modules. Provides a single entry point
# for loading the entire modular system with dependency management.
#
# USAGE:
# ------
# source songbird-core/songbird-core.sh [modules...]
#
# EXAMPLES:
# ---------
# source songbird-core/songbird-core.sh                    # Load all modules
# source songbird-core/songbird-core.sh config errors      # Load specific modules
# source songbird-core/songbird-core.sh config audio hardware errors utils
#
# =============================================================================

# Get the directory where this script is located
SONGBIRD_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Available modules (in dependency order)
AVAILABLE_MODULES=(
    "config"        # Core configuration (no dependencies)
    "error"        # Error handling (depends on config)
    "audio"         # Audio management (depends on config, errors)
    "hardware"      # Hardware validation (depends on config, errors, audio)
    "utils"         # Utilities (depends on config, errors)
)

# Track loaded modules
LOADED_MODULES=""

# Helper functions for module tracking
is_module_loaded() {
    local module="$1"
    [[ " $LOADED_MODULES " == *" $module "* ]]
}

mark_module_loaded() {
    local module="$1"
    if ! is_module_loaded "$module"; then
        LOADED_MODULES="$LOADED_MODULES $module"
    fi
}

load_module() {
    local module_name="$1"
    local module_file="$SONGBIRD_CORE_DIR/songbird-${module_name}.sh"

    # Check if module already loaded
    if is_module_loaded "$module_name"; then
        return 0
    fi

    # Check if module file exists
    if [[ ! -f "$module_file" ]]; then
        echo "ERROR: Module file not found: $module_file" >&2
        return 1
    fi

    # Load module dependencies first
    case "$module_name" in
        "error")
            load_module "config"
            ;;
        "audio")
            load_module "config"
            load_module "error"
            ;;
        "hardware")
            load_module "config"
            load_module "error"
            load_module "audio"
            ;;
        "utils")
            load_module "config"
            load_module "error"
            ;;
    esac

    # Source the module
    if source "$module_file"; then
        mark_module_loaded "$module_name"
        if [[ "$VERBOSE_OPERATIONS" == "true" ]]; then
            echo "✅ Loaded module: $module_name" >&2
        fi
        return 0
    else
        echo "ERROR: Failed to load module: $module_name" >&2
        return 1
    fi
}

# Load all modules
load_all_modules() {
    local failed_modules=()

    for module in "${AVAILABLE_MODULES[@]}"; do
        if ! load_module "$module"; then
            failed_modules+=("$module")
        fi
    done

    if [[ ${#failed_modules[@]} -eq 0 ]]; then
        if [[ "$VERBOSE_OPERATIONS" == "true" ]]; then
            echo "✅ All Songbird core modules loaded successfully" >&2
        fi
        return 0
    else
        echo "ERROR: Failed to load modules: ${failed_modules[*]}" >&2
        return 1
    fi
}

# Show available modules
show_available_modules() {
    echo "Available Songbird Core Modules:"
    echo "================================"
    for module in "${AVAILABLE_MODULES[@]}"; do
        local module_file="$SONGBIRD_CORE_DIR/songbird-${module}.sh"
        if [[ -f "$module_file" ]]; then
            echo "  ✅ $module"
        else
            echo "  ❌ $module (file missing)"
        fi
    done
}

# Show loaded modules
show_loaded_modules() {
    echo "Loaded Modules:"
    echo "==============="
    for module in "${AVAILABLE_MODULES[@]}"; do
        if is_module_loaded "$module"; then
            echo "  ✅ $module"
        else
            echo "  ❌ $module"
        fi
    done
}

# Main loading logic
main()
{
    local modules_to_load=("$@")

    # If no modules specified, load all
    if [[ ${#modules_to_load[@]} -eq 0 ]]; then
        load_all_modules
        return $?
    fi

    # Load specified modules
    local failed_modules=()
    for module in "${modules_to_load[@]}"; do
        if [[ " ${AVAILABLE_MODULES[*]} " =~ " $module " ]]; then
            if ! load_module "$module"; then
                failed_modules+=("$module")
            fi
        else
            echo "ERROR: Unknown module: $module" >&2
            echo "Available modules: ${AVAILABLE_MODULES[*]}" >&2
            failed_modules+=("$module")
        fi
    done

    if [[ ${#failed_modules[@]} -eq 0 ]]; then
        return 0
    else
        echo "ERROR: Failed to load modules: ${failed_modules[*]}" >&2
        return 1
    fi
}

# Only process arguments if this script is being executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    if [[ $# -gt 0 ]]; then
        if [[ "$1" == "--list" ]]; then
            show_available_modules
            exit 0
        elif [[ "$1" == "--status" ]]; then
            show_loaded_modules
            exit 0
        else
            main "$@"
            exit $?
        fi
    else
        load_all_modules
        exit $?
    fi
else
    # Script is being sourced, just load all modules
    load_all_modules
fi