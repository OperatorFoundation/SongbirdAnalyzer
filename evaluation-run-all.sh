#!/bin/bash

# Source common functions
source ./common-functions.sh

print_header "Full Evaluation Process"

# Run each step in sequence
echo "Step 1: Setup environment"
./setup-evaluation-env.sh
if [ $? -ne 0 ]; then
  echo "Environment setup failed. Aborting."
  exit 1
fi

echo "Step 2: Record audio"
./record-modified-audio.sh
if [ $? -ne 0 ]; then
  echo "Audio recording failed. Aborting."
  exit 1
fi

echo "Step 3: Process MFCC features"
./process-mfcc.sh
if [ $? -ne 0 ]; then
  echo "MFCC processing failed. Aborting."
  exit 1
fi

echo "Step 4: Analyze results"
./analyze-results.sh
if [ $? -ne 0 ]; then
  echo "Results analysis failed. Aborting."
  exit 1
fi

echo "Full evaluation process completed successfully!"