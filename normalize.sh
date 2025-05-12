#!/bin/bash

MODEL_FILE="songbird.pkl"
ALL_FILES=("results/evaluation_Noise_mfccs.csv" "results/evaluation_PitchShift_mfccs.csv" "results/evaluation_Wave_mfccs.csv" "results/evaluation_All_mfccs.csv" "results/testing_mfccs.csv" "results/training_mfccs.csv", "results/evaluation_mfccs.csv", "results/evaluation.csv")

# Function to count columns in a CSV file
count_columns() {
    local file="$1"
    local header=$(head -n 1 "$file")
    local count=$(echo "$header" | awk -F, '{print NF}')
    echo "$count"
}

# Function to trim a CSV file to a specified number of columns
trim_csv() {
    local input_file="$1"
    local num_columns="$2"
    local output_file="${input_file%.csv}_trimmed.csv"

    # Create a cut command with the right number of fields
    local cut_list=""
    for ((i=1; i<=num_columns; i++)); do
        if [ -z "$cut_list" ]; then
            cut_list="$i"
        else
            cut_list="$cut_list,$i"
        fi
    done

    # Cut the file and save to the new file
    cut -d, -f"$cut_list" "$input_file" > "$output_file"
    echo "Created trimmed file: $output_file"
}

# Find the file with the fewest columns
min_columns=999999  # Start with a high number
min_columns_file=""

for file in ${ALL_FILES[@]}; do
    # Check if the file exists and is a regular file
    if [ ! -f "$file" ]; then
        echo "Warning: '$file' is not a file or doesn't exist. Skipping."
        continue
    fi

    # Check if the file has a .csv extension
    if [[ "$file" != *.csv ]]; then
        echo "Warning: '$file' does not have a .csv extension. Skipping."
        continue
    fi

    # Count columns in this file
    columns=$(count_columns "$file")
    echo "File '$file' has $columns columns."

    # Update minimum if this file has fewer columns
    if [ "$columns" -lt "$min_columns" ]; then
        min_columns="$columns"
        min_columns_file="$file"
    fi
done

if [ -z "$min_columns_file" ]; then
    echo "No valid CSV files found."
    exit 1
fi

echo "============================================="
echo "The file with the fewest columns is: $min_columns_file with $min_columns columns."
echo "============================================="

# Ask for confirmation before proceeding
read -p "Do you want to trim all other CSV files to $min_columns columns? (y/n): " confirm
if [[ "$confirm" != [yY]* ]]; then
    echo "Operation cancelled."
    exit 0
fi

# Process all files
for file in ${ALL_FILES[@]}; do
    # Skip files that don't exist or aren't CSV
    if [ ! -f "$file" ] || [[ "$file" != *.csv ]]; then
        continue
    fi

    # Skip the file with minimum columns
    if [ "$file" = "$min_columns_file" ]; then
        output_file="${file%.csv}_trimmed.csv"
        echo "Copying $file unmodified to new name $output_file (it already has the minimum columns)."
        cp $file $output_file
        continue
    fi

    # Get column count for this file
    columns=$(count_columns "$file")

    # If this file has more columns than the minimum, trim it
    if [ "$columns" -gt "$min_columns" ]; then
        echo "Trimming $file from $columns to $min_columns columns..."
        trim_csv "$file" "$min_columns"
    else
        echo "$file already has $min_columns columns. No trimming needed."
        output_file="${file%.csv}_trimmed.csv"
        echo "Copying $file unmodified to new name $output_file (it already has the minimum columns)."
        cp $file $output_file
    fi
done

echo "Done! All CSV files have been processed."