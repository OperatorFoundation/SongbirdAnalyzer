#!/bin/bash
# =============================================================================
# MFCC FEATURE EXTRACTION FOR EVALUATION
# =============================================================================
#
# Extracts MFCC features from recorded modified audio files.
#
# FUNCTION:
# ---------
# - Processes all audio in working-evaluation/
# - Extracts MFCC, Delta, and Delta2 features
# - Outputs to results/evaluation.csv
#
# PREREQUISITES:
# --------------
# - working-evaluation/ must contain recorded modified audio
# - Python environment with librosa and pandas
#
# SAFETY:
# -------
# 🟢 SAFE - Read-only operation on recordings
# 📝 Creates new CSV file, doesn't modify audio
#
# OUTPUT:
# -------
# results/evaluation.csv - MFCC features for all recorded files
#
# INTEGRATION:
# ------------
# Called by songbird-pipeline.sh evaluation and quick
# Uses automfcc.py for feature extraction
#
# =============================================================================

# Source common functions
source songbird-common.sh

print_header "MFCC Processing"

# Check if working directory exists and has content
if [ ! -d "$WORKING_DIR" ] || [ -z "$(ls -A "$WORKING_DIR" 2>/dev/null)" ]; then
  echo "Error: Working directory '$WORKING_DIR' doesn't exist or is empty."
  echo "Run setup-evaluation-env.sh and record-modified-audio.sh first, or copy existing recorded files to $WORKING_DIR."
  exit 1
fi

echo "Processing audio features from $WORKING_DIR..."
echo "Output will be written to $RESULTS_FILE"

# Run automfcc.py to extract features
python3 automfcc.py $WORKING_DIR $RESULTS_FILE

# Check if successful
if [ $? -ne 0 ]; then
  echo "Error: MFCC processing failed!"
  exit 1
fi

echo "MFCC processing completed successfully!"
echo "Generated files:"
ls -la $RESULTS_FILE*

echo ""
echo "You can now run analyze-results.sh to evaluate the processed data."