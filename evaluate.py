import sys
import pandas as pd


def load_evaluation_data(results_file):
    """
    Load evaluation data from CSV file with validation.

    Args:
        results_file: Path to the CSV file containing evaluation results

    Returns:
        pandas.DataFrame: Loaded evaluation data

    Raises:
        FileNotFoundError: If file doesn't exist
        ValueError: If file is missing required columns
    """
    try:
        results_data = pd.read_csv(results_file)
        print(f"Loaded data with {results_data.shape[0]} rows and {results_data.shape[1]} columns")
    except Exception as e:
        raise FileNotFoundError(f"Failed to load data from {results_file}: {e}")

    # Validate required columns
    if "speaker" not in results_data.columns:
        raise ValueError(f"No speaker column in {results_file}")

    return results_data


def extract_features_and_labels(results_data):
    """
    Extract features and labels from evaluation data.

    Args:
        results_data: DataFrame containing evaluation data

    Returns:
        tuple: (features_df, labels_series, metadata_dict)
    """
    # Determine columns to exclude from features
    exclude_columns = ["speaker"]
    if "wav_file" in results_data.columns:
        exclude_columns.append("wav_file")

    # Extract labels and features
    correct_answers = results_data["speaker"]
    mfccs = results_data.drop(columns=exclude_columns)

    # Create metadata dictionary
    metadata = {
        'total_samples': len(results_data),
        'feature_columns': list(mfccs.columns),
        'excluded_columns': exclude_columns,
        'has_wav_file': "wav_file" in results_data.columns
    }

    return mfccs, correct_answers, metadata


def calculate_data_statistics(results_data):
    """
    Calculate and return statistics about the evaluation data.

    Args:
        results_data: DataFrame containing evaluation data

    Returns:
        dict: Statistics including speaker counts, mode counts, etc.
    """
    stats = {}

    # Basic statistics
    stats['total_samples'] = len(results_data)

    # Count samples per speaker
    speaker_counts = results_data["speaker"].value_counts()
    stats['speaker_counts'] = speaker_counts.to_dict()
    stats['unique_speakers'] = len(speaker_counts)

    # Extract mode information if wav_file column exists
    if "wav_file" in results_data.columns:
        # Extract mode from wav file names (format *-n.wav, *-p.wav, etc.)
        modes = results_data["wav_file"].apply(
            lambda x: x.split("-")[-1].split(".")[0] if "-" in x else "unknown"
        )

        mode_counts = modes.value_counts()
        stats['mode_counts'] = mode_counts.to_dict()
        stats['unique_modes'] = len(mode_counts)
        stats['has_modes'] = True
    else:
        stats['mode_counts'] = {}
        stats['unique_modes'] = 0
        stats['has_modes'] = False

    return stats


def save_evaluation_data(mfccs, correct_answers, output_prefix):
    """
    Save extracted features and labels to CSV files.

    Args:
        mfccs: DataFrame containing feature data
        correct_answers: Series containing speaker labels
        output_prefix: Prefix for output files

    Returns:
        list: List of files created
    """
    files_created = []

    # Save the extracted data
    mfcc_file = f"{output_prefix}_mfccs.csv"
    speaker_file = f"{output_prefix}_speakers.csv"

    mfccs.to_csv(mfcc_file, index=False)
    files_created.append(mfcc_file)

    correct_answers.to_csv(speaker_file, index=False)
    files_created.append(speaker_file)

    print(f"Saved features to {mfcc_file}")
    print(f"Saved labels to {speaker_file}")

    return files_created


def print_data_statistics(stats):
    """
    Print data statistics to console.

    Args:
        stats: Dictionary containing statistics from calculate_data_statistics()
    """
    print("\nData Statistics:")
    print(f"Total samples: {stats['total_samples']}")

    # Print samples per speaker
    print("\nSamples per speaker:")
    for speaker, count in stats['speaker_counts'].items():
        print(f"  Speaker {speaker}: {count} samples")

    # Print mode statistics if available
    if stats['has_modes'] and stats['mode_counts']:
        print("\nSamples per mode:")
        for mode, count in stats['mode_counts'].items():
            print(f"  Mode {mode}: {count} samples")


def evaluate_data_pipeline(results_file, output_prefix=None):
    """
    Complete evaluation data processing pipeline.

    Args:
        results_file: Path to CSV file containing evaluation results
        output_prefix: Prefix for output files (defaults to results_file without .csv)

    Returns:
        dict: Processing results including statistics and file information
    """
    # Set default output prefix
    if output_prefix is None:
        output_prefix = results_file.replace('.csv', '')
    else:
        output_prefix = output_prefix.replace('.csv', '')

    print(f"Evaluating {results_file}")

    # Load and validate data
    results_data = load_evaluation_data(results_file)

    # Extract features and labels
    mfccs, correct_answers, metadata = extract_features_and_labels(results_data)

    # Calculate statistics
    stats = calculate_data_statistics(results_data)

    # Save processed data
    files_created = save_evaluation_data(mfccs, correct_answers, output_prefix)

    # Print statistics
    print_data_statistics(stats)

    print("\nEvaluation data ready!")

    # Return comprehensive results
    return {
        'stats': stats,
        'metadata': metadata,
        'files_created': files_created,
        'output_prefix': output_prefix,
        'mfccs_shape': mfccs.shape,
        'labels_count': len(correct_answers)
    }


def main():
    """CLI wrapper function that handles command-line arguments and calls the core pipeline."""
    if len(sys.argv) < 2:
        print("Usage: python evaluate.py <results_file.csv> [output_prefix]")
        sys.exit(1)

    # Parse arguments
    results_file = sys.argv[1]
    output_prefix = None if len(sys.argv) < 3 else sys.argv[2]

    try:
        # Call the main evaluation pipeline
        results = evaluate_data_pipeline(results_file, output_prefix)

        # Print summary (only in CLI mode)
        print(f"\n🎉 Evaluation completed successfully!")
        print(f"Processed {results['stats']['total_samples']} samples")
        print(f"Features shape: {results['mfccs_shape']}")
        print(f"Files created: {len(results['files_created'])}")

    except Exception as error:
        print(f"Error: {error}")
        sys.exit(1)


if __name__ == "__main__":
    main()