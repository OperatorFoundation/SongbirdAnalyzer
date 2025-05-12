#!/usr/bin/env python3

import pandas as pd
import re
import os
import sys

# Hardcoded list of CSV file paths - update these to your actual file paths
csv_files = [
    "results/evaluation_Noise_mfccs.csv",
    "results/evaluation_PitchShift_mfccs.csv",
    "results/evaluation_Wave_mfccs.csv",
    "results/evaluation_All_mfccs.csv",
    "results/testing_mfccs.csv",
    "results/training_mfccs.csv",
    "results/evaluation_mfccs.csv",
    "results/evaluation.csv"
]


def categorize_columns(columns):
    """
    Categorize columns into MFCC, Delta, and Delta2 with their counts
    """
    categories = {
        'MFCC': [],
        'Delta': [],
        'Delta2': []
    }

    for col in columns:
        if col.startswith('MFCC_'):
            categories['MFCC'].append(col)
        elif col.startswith('Delta_'):
            categories['Delta'].append(col)
        elif col.startswith('Delta2_'):
            categories['Delta2'].append(col)

    # Sort columns by their numeric suffix to ensure correct ordering
    for category in categories:
        categories[category].sort(key=lambda x: int(re.search(r'_(\d+)', x).group(1)))

    return categories


def find_min_columns_by_category(files):
    """
    Find the minimum number of columns for each category across all files
    """
    min_counts = {
        'MFCC': float('inf'),
        'Delta': float('inf'),
        'Delta2': float('inf')
    }

    file_categories = {}

    print("Analyzing files...")
    for file_path in files:
        if not os.path.exists(file_path):
            print(f"Warning: File {file_path} does not exist. Skipping.")
            continue

        try:
            # Read only the header to save memory
            df_header = pd.read_csv(file_path, nrows=0)
            columns = list(df_header.columns)

            categories = categorize_columns(columns)
            file_categories[file_path] = categories

            # Update minimum counts
            for category, cols in categories.items():
                count = len(cols)
                print(f"  {file_path}: {category} columns: {count}")
                min_counts[category] = min(min_counts[category], count)

        except Exception as e:
            print(f"Error processing {file_path}: {e}")

    return min_counts, file_categories


def trim_csv_files(files, min_counts, file_categories):
    """
    Trim CSV files to have the minimum number of columns in each category
    """
    for file_path in files:
        if file_path not in file_categories:
            continue

        categories = file_categories[file_path]

        # Check if any trimming is needed
        needs_trimming = False
        for category, cols in categories.items():
            if len(cols) > min_counts[category]:
                needs_trimming = True
                break

        if not needs_trimming:
            print(f"No trimming needed for {file_path}")
            continue

        # Determine columns to keep
        columns_to_keep = []
        for category, cols in categories.items():
            columns_to_keep.extend(cols[:min_counts[category]])

        try:
            # Read the file
            df = pd.read_csv(file_path)

            # Keep only the columns we want
            df_trimmed = df[columns_to_keep]

            # Create output filename
            output_path = file_path.replace('.csv', '_trimmed.csv')
            if output_path == file_path:
                output_path = file_path + '_trimmed.csv'

            # Save the trimmed dataframe
            df_trimmed.to_csv(output_path, index=False)
            print(f"Created trimmed file: {output_path}")

            # Print trimming details
            for category in categories:
                original = len(categories[category])
                new = min_counts[category]
                if original > new:
                    print(f"  - Trimmed {category} columns: {original} → {new}")

        except Exception as e:
            print(f"Error trimming {file_path}: {e}")


def main():
    # Validate file list
    valid_files = [f for f in csv_files if os.path.exists(f) and f.endswith('.csv')]

    if not valid_files:
        print("No valid CSV files found in the provided list.")
        return

    print(f"Found {len(valid_files)} valid CSV files.")

    # Find minimum column counts by category
    min_counts, file_categories = find_min_columns_by_category(valid_files)

    print("\nMinimum column counts across all files:")
    for category, count in min_counts.items():
        if count == float('inf'):
            print(f"{category}: None found")
        else:
            print(f"{category}: {count}")

    # Ask for confirmation
    response = input("\nDo you want to trim all CSV files to these minimum counts? (y/n): ")
    if response.lower() not in ['y', 'yes']:
        print("Operation cancelled.")
        return

    # Trim the files
    print("\nTrimming files...")
    trim_csv_files(valid_files, min_counts, file_categories)

    print("\nDone! All CSV files have been processed.")


if __name__ == "__main__":
    main()