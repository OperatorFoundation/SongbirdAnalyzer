#!/bin/bash
# =============================================================================
# SONGBIRD CORE CONFIGURATION
# =============================================================================
#
# Central configuration for all Songbird scripts.
# Should only contain configuration variables and constants.
#
# USAGE:
# ------
# source songbird-core/songbird-config.sh
#
# =============================================================================

# CORE PROJECT CONFIGURATION
# ===========================
SONGBIRD_VERSION="2.0.0"
SONGBIRD_CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SONGBIRD_CORE_DIR")"

# AUDIO PROCESSING CONFIGURATION
# ===============================
MAX_TIME=10                                    # Audio segment length (seconds)
EXPECTED_AUDIO_DURATION_SECONDS=$MAX_TIME      # Expected duration for validation
AUDIO_VALIDATION_TOLERANCE_SECONDS=2           # Allow ±2 seconds variance

# HARDWARE CONFIGURATION
# ======================
DEVICE_NAME="Teensy MIDI_Audio"                # Hardware device name as it appears on macOS
SERIAL_TIMEOUT_SECONDS=2                       # Serial communication timeout
FIRMWARE_TEST_TIMEOUT_SECONDS=5                # Firmware responsiveness test timeout
HARDWARE_VALIDATION_RETRY_COUNT=3              # Number of hardware validation attempts
HARDWARE_VALIDATION_RETRY_DELAY_SECONDS=1      # Delay between validation retries

# AUDIO VALIDATION THRESHOLDS
# ============================
MINIMUM_VALID_AUDIO_FILE_SIZE_BYTES=1024       # Minimum file size for valid audio
FIRMWARE_TEST_TONE_DURATION_SECONDS=3          # Test tone duration for validation
FIRMWARE_TEST_TONE_FREQUENCY_HZ=440            # Test tone frequency

# TEENSY MODIFICATION MODES
# =========================
modes=("n" "p" "w" "a")                        # Teensy firmware mode commands
mode_names=("Noise" "PitchShift" "Wave" "All") # Human-readable mode names

# SPEAKER CONFIGURATION
# =====================
speakers=("21525" "23723" "19839")             # LibriVox speaker IDs

# Speaker download URLs (parallel array - maintain order with speakers array)
speaker_urls=(
    "https://www.archive.org/download/man_who_knew_librivox/man_who_knew_librivox_64kb_mp3.zip"
    "https://www.archive.org/download/man_thursday_zach_librivox/man_thursday_zach_librivox_64kb_mp3.zip"
    "https://www.archive.org/download/emma_solo_librivox/emma_solo_librivox_64kb_mp3.zip"
)

# Speaker-specific cleanup patterns (parallel array)
speaker_cleanup_patterns=(
    "NONE"
    "NONE"
    "emma_01_04_austen_64kb.mp3 emma_02_11_austen_64kb.mp3"
)

# DIRECTORY STRUCTURE
# ===================
SPEAKERS_DIR="audio/training"                  # Training audio storage
WORKING_DIR="working-evaluation"               # Working directory for evaluation
FILES_DIR="results/testing_wav"                # Test audio files
RESULTS_FILE="results/evaluation.csv"          # MFCC results file
RESULTS_FILE_STANDARDIZED="results/evaluation_standardized.csv"  # Standardized MFCC results
MODEL_FILE="songbird.pkl"                      # Trained model file

# BACKUP AND RECOVERY CONFIGURATION
# ==================================
BACKUP_ROOT_DIR="backups"                      # Root directory for backups
BACKUP_TIMESTAMP_FORMAT="%Y%m%d_%H%M%S"        # Timestamp format for backup directories
MAX_BACKUPS_TO_KEEP=10                         # Maximum number of backups to retain

# CHECKPOINT SYSTEM CONFIGURATION
# ================================
CHECKPOINT_FILE="$WORKING_DIR/.recording_progress.json"  # JSON checkpoint file
LEGACY_CHECKPOINT_FILE="$WORKING_DIR/.recording_progress.state"  # Legacy text checkpoint

# REPORTING AND TRACKING
# ======================
TRACKING_FILE="modified_audio_tracking_report.txt"  # Legacy tracking report
LOG_LEVEL="INFO"                                     # Default logging level

# PYTHON ENVIRONMENT CONFIGURATION
# =================================
PYTHON_CMD="python3"                           # Python command to use
SONGBIRD_CORE_PYTHON_DIR="$SONGBIRD_CORE_DIR"  # Location of Python modules

# ERROR HANDLING CONFIGURATION
# =============================
ERROR_LOG_FILE="songbird_errors.log"           # Error log file
EXIT_CODE_SUCCESS=0                             # Success exit code
EXIT_CODE_GENERAL_ERROR=1                      # General error exit code
EXIT_CODE_HARDWARE_ERROR=2                     # Hardware-related error exit code
EXIT_CODE_FILE_ERROR=3                         # File-related error exit code
EXIT_CODE_VALIDATION_ERROR=4                   # Validation error exit code
EXIT_CODE_USER_CANCELLED=5                     # User cancelled operation exit code

# VALIDATION AND SAFETY FLAGS
# ============================
REQUIRE_HARDWARE_VALIDATION=true               # Require hardware validation before recording
ENABLE_AUTOMATIC_BACKUPS=true                  # Enable automatic backups
ENABLE_CHECKPOINT_SYSTEM=true                  # Enable checkpoint/resume system
VERBOSE_OPERATIONS=false                       # Enable verbose output by default

# FEATURE FLAGS
# =============
USE_PYTHON_VALIDATION=true                     # Use Python-based audio validation
USE_PYTHON_CHECKPOINTS=true                    # Use Python-based checkpoint management
ENABLE_PROGRESS_REPORTING=true                 # Enable detailed progress reporting

# ENVIRONMENT VALIDATION
# ======================
# Export variables that Python scripts might need
export SONGBIRD_CORE_DIR
export SONGBIRD_CORE_PYTHON_DIR
export PROJECT_ROOT
export PYTHON_CMD