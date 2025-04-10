#!/bin/bash
# Script to split an audio file into segments of a specified maximum length

INPUT_FILE="$1"
MAX_TIME="$2"
OUTPUT_DIR="$3"

BASE_NAME=$(basename "${INPUT_FILE%.*}")
#`BASE_NAME ${INPUT_FILE%.*}`

# Use sox to split the audio file
# - Convert to mono (-c 1)
# - Create sequentially numbered output files
# - Each file is trimmed to MAX_TIME length
sox "${INPUT_FILE}" -c 1 "${OUTPUT_DIR}/${BASE_NAME}_%03n.wav" trim 0 ${MAX_TIME} : newfile : restart

