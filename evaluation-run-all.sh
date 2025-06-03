#!/bin/bash
# =============================================================================
# COMPLETE EVALUATION ORCHESTRATOR
# =============================================================================
#
# ⚠️  DESTRUCTIVE - Runs complete evaluation pipeline including recording
#
# PIPELINE STAGES:
# ----------------
# 1. Setup environment (safe)
# 2. Record modified audio (⚠️  DESTRUCTIVE - overwrites existing)
# 3. Process MFCC features (safe)
# 4. Analyze results (safe)
#
# CRITICAL WARNING:
# -----------------
# 🔴 OVERWRITES all existing recordings in working-evaluation/
# 🔴 20-45 minute process requiring hardware interaction
# 🔴 Cannot be undone
#
# RECOMMENDATION:
# ---------------
# Use songbird-pipeline.sh evaluation instead - better error handling
# and user guidance.
#
# ERROR HANDLING:
# ---------------
# - Stops on first failure
# - Reports which stage failed
# - Allows manual recovery
#
# HARDWARE REQUIREMENTS:
# ----------------------
# - Teensy device connected and functional
# - SwitchAudioSource installed
# - Proper audio routing setup
#
# =============================================================================

# Source common functions
source songbird-common.sh

print_header "Full Evaluation Process"

# Run each step in sequence
echo "Step 1: Setup environment"
./evaluation-setup-environment.sh
if [ $? -ne 0 ]; then
  echo "Environment setup failed. Aborting."
  exit 1
fi

echo "Step 2: Record audio"
./evaluation-record-modified-audio.sh
if [ $? -ne 0 ]; then
  echo "Audio recording failed. Aborting."
  exit 1
fi

echo "Step 3: Process MFCC features"
./evaluation-process-mfcc.sh
if [ $? -ne 0 ]; then
  echo "MFCC processing failed. Aborting."
  exit 1
fi

echo "Step 4: Analyze results"
./evaluation-analyze-results.sh
if [ $? -ne 0 ]; then
  echo "Results analysis failed. Aborting."
  exit 1
fi

echo "Full evaluation process completed successfully!"