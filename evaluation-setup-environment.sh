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
# AUTOMATIC INTEGRATION:
# ----------------------
# Called by evaluation pipeline - rarely used directly
#
# =============================================================================

# Source common functions
source songbird-common.sh

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

# Create directory structure
setup_working_directory

echo "Environment setup complete!"