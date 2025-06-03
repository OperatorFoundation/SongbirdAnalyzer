#!/bin/bash
# =============================================================================
# RESULTS ANALYSIS ENGINE
# =============================================================================
#
# Runs evaluation and prediction analysis on processed MFCC features.
#
# FUNCTION:
# ---------
# - Runs evaluate.py on standardized evaluation features
# - Runs predict.py using trained songbird.pkl model
# - Generates analysis reports and predictions
#
# PREREQUISITES:
# --------------
# - results/evaluation_standardized.csv (from MFCC processing)
# - songbird.pkl (trained model)
# - Training completed successfully
#
# SAFETY:
# -------
# 🟢 SAFE - Analysis only, no recording or file modification
#
# OUTPUT:
# -------
# - Statistical evaluation reports
# - Model predictions on modified audio
# - Performance metrics and analysis
#
# INTEGRATION:
# ------------
# Final step in evaluation pipeline
# Called by songbird-pipeline.sh evaluation and quick
#
# =============================================================================

# Source common functions
source songbird-common.sh

print_header "Results Analysis"

# Check if required files exist
if [ ! -f "$RESULTS_FILE_STANDARDIZED" ]; then
  echo "Error: Results file '$RESULTS_FILE_STANDARDIZED' not found!"
  echo "Run process-mfcc.sh first to generate the MFCC features."
  exit 1
fi

# Check if model file exists
if [ ! -f "$MODEL_FILE" ]; then
  echo "Error: Model file '$MODEL_FILE' not found!"
  exit 1
fi

# Run evaluation script
echo "Running evaluation..."
python3 evaluate.py $RESULTS_FILE_STANDARDIZED

# Check if successful
if [ $? -ne 0 ]; then
  echo "Error: Evaluation failed!"
  exit 1
fi

# Run prediction script
echo "Running prediction..."
python3 predict.py $RESULTS_FILE_STANDARDIZED $MODEL_FILE

# Check if successful
if [ $? -ne 0 ]; then
  echo "Error: Prediction failed!"
  exit 1
fi

echo "Analysis completed successfully!"