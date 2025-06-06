#!/bin/bash
# Script to split an audio file into segments of a specified maximum length

source songbird-common.sh

INPUT_FILE="$1"
MAX_TIME="${2:-$MAX_TIME}"  # Use parameter if provided, otherwise use default from songbird-common.sh
OUTPUT_DIR="$3"

BASE_NAME=$(basename "${INPUT_FILE%.*}")

# Use sox to split the audio file
# - Convert to mono (-c 1)
# - Create sequentially numbered output files
# - Each file is trimmed to MAX_TIME length
sox "${INPUT_FILE}" -V1 -c 1 "${OUTPUT_DIR}/${BASE_NAME}_%03n.wav" trim 0 ${MAX_TIME} : newfile : restart