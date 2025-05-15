#!/bin/bash

# Source common functions
source ./common-functions.sh

print_header "Environment Setup"

# Check if SwitchAudioSource is installed
if ! command -v SwitchAudioSource &>/dev/null; then
  echo "ERROR: SwitchAudioSource not found. Install it with: brew install switchaudio-osx"
  exit 1
fi

# Save original audio sources before changing anything
save_original_audio_sources

# Create directory structure
setup_working_directory

echo "Environment setup complete!"