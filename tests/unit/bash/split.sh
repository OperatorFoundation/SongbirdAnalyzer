#!/bin/bash
mp3_file="$1"
if [[ "$mp3_file" == *"chapter02"* ]]; then
    echo "Simulated processing failure for chapter02" >&2
    exit 1
fi
# Process other files normally
output_dir="$3"
basename_file=$(basename "$mp3_file" .mp3)
mkdir -p "$output_dir"
touch "$output_dir/${basename_file}_001.wav"
