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


def load_prediction_data(mfccs_file, speakers_file):
    """
    Load feature and target data for prediction.

    Args:
        mfccs_file: Path to CSV file containing MFCC features
        speakers_file: Path to CSV file containing speaker labels

    Returns:
        tuple: (features_df, target_series) or raises exception if loading fails
    """
    # Check if required files exist
    if not os.path.exists(mfccs_file):
        raise FileNotFoundError(f"MFCC file does not exist: {mfccs_file}")

    if not os.path.exists(speakers_file):
        raise FileNotFoundError(f"Speakers file does not exist: {speakers_file}")

    # Load data files
    try:
        features = pd.read_csv(mfccs_file)
        target = pd.read_csv(speakers_file)

        # Convert target to series if it's a dataframe
        if isinstance(target, pd.DataFrame):
            target = target.iloc[:, 0]

        print(f"Loaded {len(features)} samples for evaluation")
        return features, target

    except Exception as error:
        raise ValueError(f"Error loading data: {error}")


def load_model(model_file):
    """
    Load trained model from file.

    Args:
        model_file: Path to the model file

    Returns:
        Loaded model object
    """
    try:
        model = joblib.load(model_file)
        print(f"Loaded model: {model_file}")
        return model
    except FileNotFoundError:
        raise FileNotFoundError(f"Model file not found: {model_file}")
    except Exception as error:
        raise ValueError(f"Error loading model: {error}")


def prepare_features_for_prediction(features):
    """
    Clean and prepare features for prediction by removing non-feature columns.

    Args:
        features: DataFrame containing features and possibly metadata columns

    Returns:
        DataFrame with only feature columns
    """
    exclude_columns = []
    if "wav_file" in features.columns:
        exclude_columns.append("wav_file")
    if "speaker" in features.columns:
        exclude_columns.append("speaker")
    if "mode" in features.columns:
        exclude_columns.append("mode")

    cleaned_features = features.drop(columns=exclude_columns)
    return cleaned_features


def make_predictions_and_evaluate(model, features, target):
    """
    Make predictions and calculate evaluation metrics.

    Args:
        model: Trained model object
        features: DataFrame containing feature data
        target: Series containing true labels

    Returns:
        dict: Evaluation results including accuracy, predictions, etc.
    """
    # Make predictions
    predictions = model.predict(features)

    # Calculate accuracy
    accuracy = accuracy_score(target, predictions)

    # Generate classification report
    report = classification_report(target, predictions)

    # Generate confusion matrix
    confusion = confusion_matrix(target, predictions)
    classes = np.unique(target)

    return {
        'predictions': predictions,
        'accuracy': accuracy,
        'report': report,
        'confusion': confusion,
        'classes': classes,
        'target': target
    }


def print_evaluation_results(results, mode=None):
    """
    Print evaluation results in formatted output.

    Args:
        results: Dictionary containing evaluation results
        mode: Optional mode name for labeling output
    """
    mode_label = mode if mode else 'combined'

    print(f"\n\n{'=' * 50}")
    if mode:
        print(f"PROCESSING MODE: {mode}")
    else:
        print(f"PROCESSING COMBINED DATA")
    print(f"{'=' * 50}")

    print(f"\n🎯 Accuracy: {results['accuracy']:.4f}")

    # Print classification report
    print("\nClassification report:")
    print("=======================")
    print(results['report'])

    # Print confusion matrix
    print("\nConfusion matrix:")
    classes = results['classes']
    confusion = results['confusion']

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


def save_prediction_results(results, output_prefix, mode=None):
    """
    Save prediction results to CSV file.

    Args:
        results: Dictionary containing prediction results
        output_prefix: Prefix for output files
        mode: Optional mode name

    Returns:
        str: Path to saved results file
    """
    target = results['target']
    predictions = results['predictions']

    # Create results DataFrame
    results_df = pd.DataFrame({
        'true_speaker': target,
        'predicted_speaker': predictions,
        'correct': predictions == target
    })

    # Add mode information if it exists
    if mode:
        results_df['mode'] = mode

    # Save results
    results_file = f"{output_prefix}_predictions.csv"
    results_df.to_csv(results_file, index=False)
    print(f"Saved predictions to {results_file}")

    return results_file


def process_single_mode_data(data_prefix, model_file, mode=None, config=None):
    """
    Process data for a single mode or combined data and generate predictions.

    Args:
        data_prefix: Base path/prefix for data files
        model_file: Path to the trained model file
        mode: Optional mode to filter data by. If None, process combined data
        config: Optional configuration dict

    Returns:
        Dictionary with results or None if processing failed
    """
    if config is None:
        config = {}

    enable_printing = config.get('enable_printing', True)

    # Determine file paths based on mode
    if mode:
        mfccs_file = f"{data_prefix}_{mode}_mfccs_trimmed.csv"
        speakers_file = f"{data_prefix}_{mode}_speakers.csv"
        output_prefix = f"{data_prefix}_{mode}"
    else:
        mfccs_file = f"{data_prefix}_mfccs_trimmed.csv"
        speakers_file = f"{data_prefix}_speakers.csv"
        output_prefix = data_prefix

    if enable_printing:
        print(f"Loading data from {mfccs_file} and {speakers_file}")
        print(f"Loading model from {model_file}")

    try:
        # Load data and model
        features, target = load_prediction_data(mfccs_file, speakers_file)
        model = load_model(model_file)

        # Prepare features for prediction
        cleaned_features = prepare_features_for_prediction(features)

        # Make predictions and evaluate
        results = make_predictions_and_evaluate(model, cleaned_features, target)

        # Print results if enabled
        if enable_printing:
            print_evaluation_results(results, mode)

        # Save results
        results_file = save_prediction_results(results, output_prefix, mode)

        # Add metadata to results
        results.update({
            'mode': mode if mode else 'combined',
            'results_file': results_file,
            'sample_count': len(target),
            'mfccs_file': mfccs_file,
            'speakers_file': speakers_file
        })

        return results

    except Exception as error:
        if enable_printing:
            print(f"Error processing data: {error}")
        # Re-raise the exception in test mode so we can see what's wrong
        if not enable_printing:  # Test mode
            raise
        return None


def generate_mode_comparison(all_results, data_prefix):
    """
    Generate and save mode comparison summary.

    Args:
        all_results: List of result dictionaries from different modes
        data_prefix: Prefix for output files

    Returns:
        str: Path to saved comparison file
    """
    if len(all_results) == 0:
        return None

    print(f"\n\n{'=' * 50}")
    print("COMPARATIVE SUMMARY")
    print(f"{'=' * 50}")
    print("Mode           | Accuracy")
    print("-" * 25)

    # Display results
    for result in all_results:
        print(f"{result['mode']:<14} | {result['accuracy']:.4f}")

    # Create and save summary DataFrame
    summary_df = pd.DataFrame([
        {'mode': r['mode'], 'accuracy': r['accuracy']}
        for r in all_results
    ])

    summary_file = f"{data_prefix}_mode_comparison.csv"
    summary_df.to_csv(summary_file, index=False)
    print(f"\nSaved mode comparison to {summary_file}")

    return summary_file


def predict_all_modes(data_prefix, model_file, testing_file_prefix="results/testing",
                      mode_names=None, config=None):
    """
    Run predictions on combined data and all available modes.

    Args:
        data_prefix: Base path/prefix for data files
        model_file: Path to the trained model file
        testing_file_prefix: Prefix for testing data files
        mode_names: List of mode names to process
        config: Optional configuration dict

    Returns:
        dict: Results including all_results list and comparison_file path
    """
    if mode_names is None:
        mode_names = ["Noise", "PitchShift", "Wave", "All"]

    if config is None:
        config = {}

    all_results = []

    # Process combined data
    combined_result = process_single_mode_data(data_prefix, model_file, None, config)
    if combined_result:
        all_results.append(combined_result)

    # Process unmodified testing data (only if files exist)
    unmodified_result = None
    testing_mfcc_file = f"{testing_file_prefix}_mfccs_trimmed.csv"
    if os.path.exists(testing_mfcc_file):
        unmodified_result = process_single_mode_data(testing_file_prefix, model_file, None, config)
        if unmodified_result:
            # Rename for clarity
            unmodified_result['mode'] = 'unmodified'
            all_results.append(unmodified_result)

    # Process each mode
    mode_results = []
    for mode in mode_names:
        # Check if mode-specific files exist
        mfcc_file = f"{data_prefix}_{mode}_mfccs_trimmed.csv"
        if os.path.exists(mfcc_file):
            result = process_single_mode_data(data_prefix, model_file, mode, config)
            if result:
                mode_results.append(result)
                all_results.append(result)

    # Generate comparative summary if we have multiple results
    comparison_file = None
    if len(all_results) > 1:
        comparison_file = generate_mode_comparison(all_results, data_prefix)

    return {
        'all_results': all_results,
        'combined_result': combined_result,
        'unmodified_result': unmodified_result,
        'mode_results': mode_results,
        'comparison_file': comparison_file,
        'modes_processed': len(mode_results)
    }


def main():
    """CLI wrapper function that handles command-line arguments and calls the core pipeline."""
    # Validate command line args
    if len(sys.argv) < 3:
        print("Usage: python predict.py <data_prefix> <model_file>")
        sys.exit(1)

    evaluation_file = sys.argv[1]
    model_file = sys.argv[2]
    data_prefix = evaluation_file.replace('.csv', '')
    testing_file_prefix = "results/testing"
    mode_names = ["Noise", "PitchShift", "Wave", "All"]

    try:
        # Call the main prediction pipeline
        results = predict_all_modes(data_prefix, model_file, testing_file_prefix, mode_names)

        # Print summary (only in CLI mode)
        print(f"\n🎉 Prediction analysis completed successfully!")
        print(f"Total modes processed: {results['modes_processed']}")
        print(f"Total results: {len(results['all_results'])}")
        if results['comparison_file']:
            print(f"Comparison saved: {results['comparison_file']}")

    except Exception as error:
        print(f"Error: {error}")
        sys.exit(1)


if __name__ == "__main__":
    main()