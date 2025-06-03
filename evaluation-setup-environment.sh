#!/bin/bash

# =============================================================================
# EVALUATION ENVIRONMENT SETUP
# =============================================================================
#
# Prepares the environment for recording modified audio with Teensy device.
#
# FUNCTION:
# ---------
# - Checks for SwitchAudioSource installation
# - Saves original audio device settings
# - Creates working directory structure for recordings
#
# SAFETY:
# -------
# 🟢 SAFE - Only sets up environment, no recording yet
# 📝 Saves original audio settings for restoration
# ✅ PROTECTED - Automatic backup of existing recordings
#
# USAGE:
# ------
# ./evaluation-setup-environment.sh [--force]
#
# FLAGS:
# ------
# --force    Skip interactive prompts and automatically create backups
#
# REQUIREMENTS:
# -------------
# - macOS with SwitchAudioSource: brew install switchaudio-osx
# - Common functions sourced from songbird-common.sh
#
# DIRECTORY STRUCTURE CREATED:
# ----------------------------
# working-evaluation/Noise/21525/
# working-evaluation/Noise/23723/
# working-evaluation/Noise/19839/
# working-evaluation/PitchShift/[speakers]/
# working-evaluation/Wave/[speakers]/
# working-evaluation/All/[speakers]/
#
# BACKUP PROTECTION:
# ------------------
# - Automatically backs up existing data
# - Keeps last 2 backups per configuration
# - User confirmation required unless --force used
#
# AUTOMATIC INTEGRATION:
# ----------------------
# Called by evaluation pipeline - rarely used directly
#
# =============================================================================

# Source common functions
source songbird-common.sh

# Parse command line arguments
FORCE_MODE=false
for arg in "$@"; do
    case $arg in
        --force)
            FORCE_MODE=true
            shift
            ;;
        *)
            # Unknown option
            echo "Unknown option: $arg"
            echo "Usage: $0 [--force]"
            exit 1
            ;;
    esac
done

print_header "Environment Setup"

# Check if SwitchAudioSource is installed
if ! command -v SwitchAudioSource &>/dev/null; then
  echo "ERROR: SwitchAudioSource not found. Install it with: brew install switchaudio-osx"
  exit 1
fi

# Check if sox is installed (needed for hardware validation)
if ! command -v sox &>/dev/null; then
  echo "WARNING: sox not found. Install it with: brew install sox"
  echo "Hardware validation will be limited without sox."
fi

# Save original audio sources before changing anything
save_original_audio_sources

# Create directory structure with safety features
if setup_working_directory "$FORCE_MODE"; then
    echo "Environment setup complete!"
else
    echo "Environment setup failed or was cancelled."
    exit 1
fi