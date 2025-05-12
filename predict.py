"""
Speaker Classification Prediction Script

This script loads MFCC feature data for audio files organized by mode/speaker,
makes predictions using a trained model, and generates classification reports
for both combined data and per-mode analysis.

Usage: python predict.py <data_prefix> <model_file>
"""
import os
import sys
import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix


def process_data(data_prefix, model_file, mode=None):
    """
    Process data and generate classification report.

    Args:
        data_prefix: Base path/prefix for data files.
        model_file: Path to the trained model file.
        mode: Optional mode to filter data by. If provided, process mode-specific data; otherwise process combined data.

    Returns:
        Dictionary with results or None if processing failed.
    """

    # Determine file paths based on mode
    if mode:
        mfccs_file = f"{data_prefix}_{mode}_mfccs_trimmed.csv"
        speakers_file = f"{data_prefix}_{mode}_speakers.csv"
        output_prefix = f"{data_prefix}_{mode}"
        print(f"\n\n{'='*50}")
        print(f"PROCESSING MODE: {mode}")
    else:
        mfccs_file = f"{data_prefix}_mfccs_trimmed.csv"
        speakers_file = f"{data_prefix}_speakers.csv"
        output_prefix = data_prefix
        print(f"\n\n{'='*50}")
        print(f"PROCESSING COMBINED DATA")

    print(f"{'='*50}")
    print(f"Loading data from {mfccs_file} and {speakers_file}")
    print(f"Loading model from {model_file}")

    # Check if required files exist
    if not os.path.exists(mfccs_file):
        print(f"Error: {mfccs_file} does not exist")
        return None

    if not os.path.exists(speakers_file):
        print(f"Error: {speakers_file} does not exist")
        return None

    # Load data files
    try:
        features = pd.read_csv(mfccs_file)
        target = pd.read_csv(speakers_file)

        # Convert target to series if it's a dataframe
        if isinstance(target, pd.DataFrame):
            target = target.iloc[:, 0]

        print(f"Loaded {len(features)} samples for evaluation")

    except Exception as error:
        print(f"Error loading data: {error}")
        return None

    # Load the model
    try:
        model = joblib.load(model_file)
        print(f"Loaded model: {model_file}")
    except Exception as error:
        print(f"Error loading model: {error}")
        return None

    # Make predictions
    try:
        exclude_columns = []
        if "wav_file" in features.columns:
            exclude_columns.append("wav_file")
        if "speaker" in features.columns:
            exclude_columns.append("speaker")
        if "mode" in features.columns:
            exclude_columns.append("mode")

        features = features.drop(columns=exclude_columns)
        predictions = model.predict(features)

        # Calculate accuracy
        accuracy = accuracy_score(target, predictions)
        print(f"\n🎯 Accuracy: {accuracy:.4f}")

        # Generate classification report
        report = classification_report(target, predictions)
        print("\nClassification report:")
        print("=======================")
        print(report)

        # Generate confusion matrix
        print("\nConfusion matrix:")
        confusion = confusion_matrix(target, predictions)

        # Get unique classes
        classes = np.unique(target)

        # Print matrix with labels
        print(f"{'':8}", end="")

        for i, cls in enumerate(classes):
            print(f"{cls:8}", end="")
        print()

        for index, clss in enumerate(classes):
            print(f"{clss:8}", end="")
            for j in range(len(classes)):
                print(f"{confusion[index, j]:8}", end="")
            print()

        # Save the results to CSV
        results_df = pd.DataFrame({'true_speaker': target, 'predicted_speaker': predictions, 'correct': predictions == target})

        # Add mode information if it exists
        if mode:
            results_df['mode'] = mode

        results_file = f"{output_prefix}_predictions.csv"
        results_df.to_csv(results_file, index=False)
        print(f"Saved predictions to {results_file}")

        return {
            'mode': mode if mode else 'combined',
            'accuracy': accuracy,
            'report': report,
            'confusion': confusion,
            'classes': classes
        }
    except Exception as error:
        print(f"Error predicting data: {error}")
        return None



def main():
    """Main function to parse arguments and run predictions."""

    # Validate command line args
    if len(sys.argv) < 3:
        print("Usage: python predict.py <data_prefix> <model_file>")
        sys.exit(1)

    evaluation_file = sys.argv[1]
    model_file = sys.argv[2]
    data_prefix = evaluation_file.replace('.csv', '')
    testing_file_prefix = "results/testing"
    mode_names = ["Noise", "PitchShift", "Wave", "All"]

    # First, process the combined data
    combined_result = process_data(data_prefix, model_file)
    unmodified_result = process_data(testing_file_prefix, model_file)

    # Get list of mode directories from the working directory
    # mode_dirs = []
    # if os.path.isdir(data_prefix):
    #     try:
    #         mode_dirs = [d for d in os.listdir(data_prefix)
    #                      if os.path.isdir(os.path.join(data_prefix, d))]
    #     except Exception as error:
    #         print(f"Warning: Could not access directory {data_prefix}: {error}")

    # Process each mode
    mode_results = []
    for mode in mode_names:
        # Check if mode-specific files exist
        mfcc_file = f"{data_prefix}_{mode}_mfccs_trimmed.csv"
        if os.path.exists(mfcc_file):
            result = process_data(data_prefix, model_file, mode)
            if result:
                mode_results.append(result)

    # Generate comparative summary if we have multiple results
    if len(mode_results) > 0:
        print(f"\n\n{'=' * 50}")
        print("COMPARATIVE SUMMARY")
        print(f"{'=' * 50}")
        print("Mode           | Accuracy")
        print("-" * 25)

        # Add combined result if it exists
        all_results = []
        if combined_result:
            all_results.append(combined_result)
        if unmodified_result:
            all_results.append(unmodified_result)

        all_results.extend(mode_results)

        # Display and save comparison
        for result in all_results:
            print(f"{result['mode']:<14} | {result['accuracy']:.4f}")

        summary_df = pd.DataFrame([
            {'mode': r['mode'], 'accuracy': r['accuracy']}
            for r in all_results
        ])

        summary_file = f"{data_prefix}_mode_comparison.csv"
        summary_df.to_csv(summary_file, index=False)
        print(f"\nSaved mode comparison to {summary_file}")


if __name__ == "__main__":
    main()

