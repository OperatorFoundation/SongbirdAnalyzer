#!/bin/bash

# Source common functions
source ./common-functions.sh

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