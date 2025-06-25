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
    """
    Categorize columns into MFCC, Delta, and Delta2 types.

    Args:
        columns: List of column names to categorize

    Returns:
        dict: Dictionary with 'MFCC', 'Delta', 'Delta2' keys containing sorted column lists
    """
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


def extract_reference_dimensions(df):
    """
    Extract reference dimensions from training data.

    Args:
        df: DataFrame containing training data

    Returns:
        dict: Dictionary with feature category dimensions
    """
    categories = categorize_columns(df.columns)
    reference_dims = {cat: len(cols) for cat, cols in categories.items()}
    return reference_dims


def get_standardized_columns(df, reference_dims):
    """
    Determine which columns to keep based on reference dimensions.

    Args:
        df: DataFrame to standardize
        reference_dims: Dictionary with reference dimensions for each category

    Returns:
        tuple: (columns_to_keep, standardization_info)
    """
    categories = categorize_columns(df.columns)
    columns_to_keep = []
    standardization_info = {
        'trimmed': {},
        'warnings': [],
        'missing_columns': []
    }

    # Add non-feature columns first (speaker, wav_file, etc.)
    for col in df.columns:
        if not (col.startswith('MFCC_') or col.startswith('Delta_') or col.startswith('Delta2_')):
            columns_to_keep.append(col)

    # Add feature columns up to reference dimensions
    for category, limit in reference_dims.items():
        available_cols = categories[category][:limit]
        columns_to_keep.extend(available_cols)

        if len(categories[category]) > limit:
            standardization_info['trimmed'][category] = {
                'from': len(categories[category]),
                'to': limit
            }
        elif len(categories[category]) < limit:
            standardization_info['warnings'].append({
                'category': category,
                'available': len(categories[category]),
                'expected': limit
            })

    # Check for missing columns
    existing_columns = [col for col in columns_to_keep if col in df.columns]
    missing = set(columns_to_keep) - set(existing_columns)
    if missing:
        standardization_info['missing_columns'] = list(missing)

    return existing_columns, standardization_info


def standardize_dataframe_to_dimensions(df, reference_dims):
    """
    Standardize a DataFrame to match reference dimensions.

    Args:
        df: DataFrame to standardize
        reference_dims: Dictionary with reference dimensions

    Returns:
        tuple: (standardized_df, standardization_info)
    """
    columns_to_keep, standardization_info = get_standardized_columns(df, reference_dims)
    df_standardized = df[columns_to_keep]

    return df_standardized, standardization_info


def save_reference_dimensions(reference_dims, reference_file):
    """
    Save reference dimensions to JSON file.

    Args:
        reference_dims: Dictionary with reference dimensions
        reference_file: Path to save the reference file

    Returns:
        str: Path to saved file
    """
    with open(reference_file, "w") as f:
        json.dump(reference_dims, f, indent=2)
    return reference_file


def load_reference_dimensions(reference_file):
    """
    Load reference dimensions from JSON file.

    Args:
        reference_file: Path to the reference file

    Returns:
        dict: Reference dimensions

    Raises:
        FileNotFoundError: If reference file doesn't exist
    """
    try:
        with open(reference_file, "r") as f:
            reference_dims = json.load(f)
        return reference_dims
    except FileNotFoundError:
        raise FileNotFoundError(f"No reference dimensions found at {reference_file}")


def print_standardization_info(standardization_info, file_path=None):
    """
    Print standardization information in a formatted way.

    Args:
        standardization_info: Dictionary containing standardization details
        file_path: Optional file path for context
    """
    if file_path:
        print(f"  📄 Processing: {file_path}")

    # Print trimming information
    for category, info in standardization_info.get('trimmed', {}).items():
        print(f"    ✂️  Trimmed {category}: {info['from']} → {info['to']}")

    # Print warnings
    for warning in standardization_info.get('warnings', []):
        print(
            f"    ⚠️  Warning: {warning['category']} has fewer columns ({warning['available']}) than reference ({warning['expected']})")

    # Print missing columns
    if standardization_info.get('missing_columns'):
        print(f"    ⚠️  Warning: Missing columns: {set(standardization_info['missing_columns'])}")


def standardize_file_to_training_dimensions(file_path, reference_dims, config=None):
    """
    Standardize a CSV file to match training dimensions.

    Args:
        file_path: Path to the CSV file to standardize
        reference_dims: Dictionary with reference dimensions
        config: Optional configuration dict

    Returns:
        tuple: (output_path, standardized_shape, standardization_info)
    """
    if config is None:
        config = {}

    enable_printing = config.get('enable_printing', True)
    output_suffix = config.get('output_suffix', '_standardized')

    if enable_printing:
        print(f"  📄 Processing: {file_path}")

    # Load and standardize data
    df = pd.read_csv(file_path)
    df_standardized, standardization_info = standardize_dataframe_to_dimensions(df, reference_dims)

    # Print standardization info if enabled
    if enable_printing:
        print_standardization_info(standardization_info)

    # Save standardized version
    output_path = file_path.replace('.csv', f'{output_suffix}.csv')
    df_standardized.to_csv(output_path, index=False)

    return output_path, df_standardized.shape, standardization_info


def process_training_mode(training_file="results/training.csv", config=None):
    """
    Process training mode: analyze training data and set feature dimension standards.

    Args:
        training_file: Path to training data file
        config: Optional configuration dict

    Returns:
        dict: Processing results including dimensions and file paths
    """
    if config is None:
        config = {}

    enable_printing = config.get('enable_printing', True)
    output_dir = config.get('output_dir', 'results')

    if enable_printing:
        print("🔧 TRAINING MODE: Setting feature dimension standards")

    # Check if training file exists
    if not os.path.exists(training_file):
        raise FileNotFoundError(f"Training file {training_file} not found!")

    if enable_printing:
        print(f"📖 Reading training data from: {training_file}")

    # Load and analyze training data
    df = pd.read_csv(training_file)
    reference_dims = extract_reference_dimensions(df)

    if enable_printing:
        print("📏 Feature dimensions found:")
        for category, count in reference_dims.items():
            print(f"  {category}: {count} columns")

    # Create standardized training file
    df_standardized, _ = standardize_dataframe_to_dimensions(df, reference_dims)

    # Save standardized training data
    output_file = os.path.join(output_dir, "training_standardized.csv")
    df_standardized.to_csv(output_file, index=False)

    # Save reference dimensions
    reference_file = os.path.join(output_dir, "feature_dimensions.json")
    save_reference_dimensions(reference_dims, reference_file)

    if enable_printing:
        print(f"✅ Training data standardized: {df_standardized.shape}")
        print(f"💾 Saved to: {output_file}")
        print(f"📐 Reference dimensions saved to: {reference_file}")

    return {
        'reference_dims': reference_dims,
        'output_file': output_file,
        'reference_file': reference_file,
        'standardized_shape': df_standardized.shape,
        'original_shape': df.shape
    }


def process_evaluation_mode(evaluation_file="results/evaluation.csv",
                            reference_file="results/feature_dimensions.json",
                            config=None):
    """
    Process evaluation mode: standardize evaluation data to match training dimensions.

    Args:
        evaluation_file: Path to evaluation data file
        reference_file: Path to reference dimensions file
        config: Optional configuration dict

    Returns:
        dict: Processing results including output path and standardization info
    """
    if config is None:
        config = {}

    enable_printing = config.get('enable_printing', True)

    if enable_printing:
        print("🎯 EVALUATION MODE: Standardizing to match training dimensions")

    # Load reference dimensions
    reference_dims = load_reference_dimensions(reference_file)

    if enable_printing:
        print(f"📐 Loaded reference dimensions from: {reference_file}")
        for category, count in reference_dims.items():
            print(f"  {category}: {count} columns")

    # Check if evaluation file exists
    if not os.path.exists(evaluation_file):
        raise FileNotFoundError(f"Evaluation file {evaluation_file} not found!")

    # Standardize evaluation file
    output_path, shape, standardization_info = standardize_file_to_training_dimensions(
        evaluation_file, reference_dims, config)

    if enable_printing:
        print(f"✅ Evaluation data standardized: {shape}")
        print(f"💾 Output: {output_path}")
        print("📂 Creating separated files for prediction pipeline...")

    # Create separated files for predict.py
    # Load the standardized data
    df_standardized = pd.read_csv(output_path)

    # Determine columns
    feature_columns = [col for col in df_standardized.columns
                      if col not in ['speaker', 'wav_file', 'mode']]

    # 1. Create combined separated files (all modes together)
    features_only = df_standardized[feature_columns]
    labels_only = df_standardized[['speaker']] if 'speaker' in df_standardized.columns else None

    # Create file paths
    base_name = output_path.replace('.csv', '')
    features_file = f"{base_name}_mfccs.csv"
    labels_file = f"{base_name}_speakers.csv"

    # Save seperated files
    features_only.to_csv(features_file, index=False)
    files_created = [features_file]

    if labels_only is not None:
        labels_only.to_csv(labels_file, index=False)
        files_created.append(labels_file)

    # 2. Create mode-specific separated files
    if 'mode' in df_standardized.columns:
        unique_modes = df_standardized['mode'].unique()
        if enable_printing:
            print(f"📊 Found modes: {list(unique_modes)}")

        for mode in unique_modes:
            # Filter data by mode
            mode_data = df_standardized[df_standardized['mode'] == mode]

            # Create mode specific files
            mode_features = mode_data[feature_columns]
            mode_labels = mode_data[['speaker']] if 'speaker' in mode_data.columns else None

            # File paths for this mode
            mode_base_name = output_path.replace('_standardized.csv', '')
            mode_features_file = f"{mode_base_name}_standardized_{mode}_mfccs.csv"
            mode_labels_file = f"{mode_base_name}_standardized_{mode}_speakers.csv"

            # Save mode specific files
            mode_features.to_csv(mode_features_file, index=False)
            files_created.append(mode_features_file)

            if mode_labels is not None:
                mode_labels.to_csv(mode_labels_file, index=False)
                files_created.append(mode_labels_file)

            if enable_printing:
                print(f"   📄 Mode '{mode}': {len(mode_data)} samples")

    else:
        if enable_printing:
            print("⚠️  No 'mode' column found - skipping mode-specific file creation")

    if enable_printing:
        print(f"✅ Created separated files:")
        for file in files_created:
            print(f"   📄 {file}")

    return {
        'output_path': output_path,
        'standardized_shape': shape,
        'standardization_info': standardization_info,
        'reference_dims': reference_dims,
        'separated_files': files_created
    }


def standardize_features_pipeline(mode, config=None):
    """
    Main standardization pipeline that handles both training and evaluation modes.

    Args:
        mode: Either 'training' or 'evaluation'
        config: Optional configuration dict

    Returns:
        dict: Processing results
    """
    if config is None:
        config = {}

    if mode == "training":
        training_file = config.get('training_file', "results/training.csv")
        return process_training_mode(training_file, config)

    elif mode == "evaluation":
        evaluation_file = config.get('evaluation_file', "results/evaluation.csv")
        reference_file = config.get('reference_file', "results/feature_dimensions.json")
        return process_evaluation_mode(evaluation_file, reference_file, config)

    else:
        raise ValueError(f"Unknown mode: {mode}. Use 'training' or 'evaluation'")


def main():
    """CLI wrapper function that handles command-line arguments and calls the core pipeline."""
    if len(sys.argv) < 2:
        print("Usage: python3 standardize_features.py [training|evaluation]")
        print("  training   - Analyze training data and set feature dimension standards")
        print("  evaluation - Standardize evaluation data to match training dimensions")
        sys.exit(1)

    mode = sys.argv[1]

    try:
        # Call the main standardization pipeline
        results = standardize_features_pipeline(mode)

        # Print final summary (only in CLI mode)
        if mode == "training":
            print(f"\n🎉 Training standardization completed!")
            print(f"Original shape: {results['original_shape']}")
            print(f"Standardized shape: {results['standardized_shape']}")
            print(f"Reference dimensions: {results['reference_dims']}")
        else:
            print(f"\n🎉 Evaluation standardization completed!")
            print(f"Final shape: {results['standardized_shape']}")
            print(f"Output file: {results['output_path']}")

    except Exception as error:
        print(f"❌ Error: {error}")
        if "training" in str(error).lower():
            print("Run training first: python3 standardize_features.py training")
        elif "evaluation" in str(error).lower():
            print("Run evaluation MFCC processing first.")
        sys.exit(1)


if __name__ == "__main__":
    main()