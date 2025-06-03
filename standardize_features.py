#!/usr/bin/env python3
# standardize_features.py

# =============================================================================
# FEATURE STANDARDIZATION UTILITY
# =============================================================================
#
# Ensures consistent MFCC feature dimensions between training and evaluation
# data to prevent model prediction errors.
#
# USAGE:
# ------
# python3 standardize_features.py training    # Set reference dimensions
# python3 standardize_features.py evaluation  # Match evaluation to training
#
# PURPOSE:
# --------
# Training Mode:  Analyzes training.csv and saves dimension reference
# Evaluation Mode: Trims evaluation.csv to match training dimensions
#
# SAFETY:
# -------
# 🟢 SAFE - Creates new *_standardized.csv files, preserves originals
#
# FILES CREATED:
# --------------
# results/training_standardized.csv     # Standardized training data
# results/evaluation_standardized.csv   # Standardized evaluation data
# results/feature_dimensions.json       # Reference dimensions
#
# AUTOMATIC INTEGRATION:
# ----------------------
# Called automatically by songbird-pipeline.sh - rarely used directly
#
# =============================================================================


import pandas as pd
import numpy as np
import sys
import os
import re
import json


def categorize_columns(columns):
    """Categorize columns into MFCC, Delta, and Delta2"""
    categories = {'MFCC': [], 'Delta': [], 'Delta2': []}

    for col in columns:
        if col.startswith('MFCC_'):
            categories['MFCC'].append(col)
        elif col.startswith('Delta_'):
            categories['Delta'].append(col)
        elif col.startswith('Delta2_'):
            categories['Delta2'].append(col)

    # Sort by numeric suffix
    for category in categories:
        if categories[category]:  # Only sort if list is not empty
            categories[category].sort(key=lambda x: int(re.search(r'_(\d+)', x).group(1)))

    return categories


def standardize_to_training_dimensions(file_path, reference_dims):
    """Standardize a file to match training dimensions"""
    print(f"  📄 Processing: {file_path}")
    df = pd.read_csv(file_path)
    categories = categorize_columns(df.columns)

    # Keep only the columns that exist in training, up to training limits
    columns_to_keep = []

    # Add non-feature columns first (speaker, wav_file, etc.)
    for col in df.columns:
        if not (col.startswith('MFCC_') or col.startswith('Delta_') or col.startswith('Delta2_')):
            columns_to_keep.append(col)

    # Add feature columns up to reference dimensions
    for category, limit in reference_dims.items():
        available_cols = categories[category][:limit]
        columns_to_keep.extend(available_cols)

        if len(categories[category]) > limit:
            print(f"    ✂️  Trimmed {category}: {len(categories[category])} → {limit}")
        elif len(categories[category]) < limit:
            print(
                f"    ⚠️  Warning: {category} has fewer columns ({len(categories[category])}) than reference ({limit})")

    # Ensure all columns exist in the dataframe
    existing_columns = [col for col in columns_to_keep if col in df.columns]
    if len(existing_columns) != len(columns_to_keep):
        missing = set(columns_to_keep) - set(existing_columns)
        print(f"    ⚠️  Warning: Missing columns: {missing}")

    df_standardized = df[existing_columns]

    # Save standardized version
    output_path = file_path.replace('.csv', '_standardized.csv')
    df_standardized.to_csv(output_path, index=False)

    return output_path, df_standardized.shape


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 standardize_features.py [training|evaluation]")
        print("  training   - Analyze training data and set feature dimension standards")
        print("  evaluation - Standardize evaluation data to match training dimensions")
        sys.exit(1)

    mode = sys.argv[1]

    if mode == "training":
        print("🔧 TRAINING MODE: Setting feature dimension standards")

        # For training mode, find the minimum dimensions and set as reference
        training_file = "results/training.csv"

        if not os.path.exists(training_file):
            print(f"❌ Training file {training_file} not found!")
            sys.exit(1)

        print(f"📖 Reading training data from: {training_file}")
        df = pd.read_csv(training_file)
        categories = categorize_columns(df.columns)

        # Save reference dimensions
        reference_dims = {cat: len(cols) for cat, cols in categories.items()}

        print("📏 Feature dimensions found:")
        for category, count in reference_dims.items():
            print(f"  {category}: {count} columns")

        # Create standardized training file (remove non-feature columns for training)
        columns_to_keep = []

        # Add metadata columns (speaker, wav_file)
        for col in df.columns:
            if not (col.startswith('MFCC_') or col.startswith('Delta_') or col.startswith('Delta2_')):
                columns_to_keep.append(col)

        # Add all feature columns
        for category, cols in categories.items():
            columns_to_keep.extend(cols)

        df_standardized = df[columns_to_keep]
        output_file = "results/training_standardized.csv"
        df_standardized.to_csv(output_file, index=False)

        # Save reference for evaluation
        reference_file = "results/feature_dimensions.json"
        with open(reference_file, "w") as f:
            json.dump(reference_dims, f, indent=2)

        print(f"✅ Training data standardized: {df_standardized.shape}")
        print(f"💾 Saved to: {output_file}")
        print(f"📐 Reference dimensions saved to: {reference_file}")

    elif mode == "evaluation":
        print("🎯 EVALUATION MODE: Standardizing to match training dimensions")

        # Load reference dimensions from training
        reference_file = "results/feature_dimensions.json"
        try:
            with open(reference_file, "r") as f:
                reference_dims = json.load(f)
            print(f"📐 Loaded reference dimensions from: {reference_file}")
            for category, count in reference_dims.items():
                print(f"  {category}: {count} columns")
        except FileNotFoundError:
            print(f"❌ No reference dimensions found at {reference_file}")
            print("Run training first: python3 standardize_features.py training")
            sys.exit(1)

        # Standardize evaluation file
        eval_file = "results/evaluation.csv"
        if os.path.exists(eval_file):
            output_path, shape = standardize_to_training_dimensions(eval_file, reference_dims)
            print(f"✅ Evaluation data standardized: {shape}")
            print(f"💾 Output: {output_path}")
        else:
            print(f"❌ Evaluation file {eval_file} not found!")
            print("Run evaluation MFCC processing first.")
            sys.exit(1)

    else:
        print(f"❌ Unknown mode: {mode}")
        print("Use 'training' or 'evaluation'")
        sys.exit(1)


if __name__ == "__main__":
    main()