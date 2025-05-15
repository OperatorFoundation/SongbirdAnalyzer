#!/bin/bash

# Source common functions
source ./common-functions.sh

print_header "Results Analysis"

# Check if required files exist
if [ ! -f "$RESULTS_FILE" ]; then
  echo "Error: Results file '$RESULTS_FILE' not found!"
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
python3 evaluate.py $RESULTS_FILE

# Check if successful
if [ $? -ne 0 ]; then
  echo "Error: Evaluation failed!"
  exit 1
fi

# Run prediction script
echo "Running prediction..."
python3 predict.py $RESULTS_FILE $MODEL_FILE

# Check if successful
if [ $? -ne 0 ]; then
  echo "Error: Prediction failed!"
  exit 1
fi

echo "Analysis completed successfully!"