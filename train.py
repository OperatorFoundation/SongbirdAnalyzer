import os
import shutil
import sys
import time

import pandas as pd
import joblib

from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from spinner import Spinner


def split_data(data_frame, first_column='speaker'):
    """
    Split a Pandas DataFrame into two separate DataFrames:
        1. A DataFrame with only the first column. (defaults to 'speaker')
        2. A DataFrame with all the remaining columns.

    :param data_frame: pandas.DataFrame The dataframe to split.
    :param first_column: str, optional defaults to 'speaker'
    :return: A tuple with both DataFrames
    """

    # make sure the requested first column exists
    if first_column not in data_frame.columns:
        raise ValueError(f"Column {first_column} is not present in the dataframe.")

    # Create a DataFrame with the first column
    target_data_frame = data_frame[[first_column]].copy()

    # Create a DataFrame with the remaining columns
    features_data_frame = data_frame.drop(columns=[first_column]).copy()

    return features_data_frame, target_data_frame


def train_model(features_data_frame, target_data_frame, n_estimators=100, config=None):
    """
    Train a Random Forest Classifier model.

    Args:
        features_data_frame: DataFrame containing the feature data for training.
        target_data_frame: DataFrame containing the target values for training.
        n_estimators (int): Number of trees in the random forest (default: 100).
        config: Optional configuration dict with keys like 'enable_spinner'

    Returns:
        tuple: (trained_model, training_time_seconds)
    """
    # Handle configuration
    if config is None:
        config = {}

    enable_spinner = config.get('enable_spinner', True)

    print(f"Training RandomForestClassifier with {n_estimators} trees...")

    # Create the model
    model = RandomForestClassifier(n_estimators=n_estimators, verbose=0)

    # Record the start time for calculating training duration
    start_time = time.time()

    # Create spinner if enabled
    spinner = None
    if enable_spinner:
        spinner = Spinner(message="Training model...")
        spinner.start()

    try:
        # Train the model
        model.fit(features_data_frame, target_data_frame)
    finally:
        # Calculate the total training time
        training_time = time.time() - start_time

        if spinner:
            completion_message = f"Model training completed in {training_time:.2f} seconds!      \n"
            spinner.stop(completion_message)
        else:
            print(f"Model training completed in {training_time:.2f} seconds!")

    # Return the trained model and timing info
    return model, training_time


def train_with_progress(features_data_frame, target_data_frame, n_estimators=100):
    """
    Train a Random Forest Classifier model with a spinner animation to show progress.

    Maintained for backward compatibility.

    This function creates and trains a RandomForestClassifier model while displaying
    a spinner animation to provide visual feedback during the training process.

    Args:
        features_data_frame: DataFrame containing the feature data for training.
        target_data_frame: DataFrame containing the target values for training.
        n_estimators (int): Number of trees in the random forest (default: 100).

    Returns:
        RandomForestClassifier: The trained model.
    """
    model, _ = train_model(features_data_frame, target_data_frame, n_estimators, {'enable_spinner': True})
    return model


def prepare_data_for_training(df, config=None):
    """
    Prepare DataFrame for training by handling wav_file column and splitting data.

    Args:
        df: DataFrame with MFCC features and speaker labels
        config: Optional configuration dict

    Returns:
        tuple: (features, target, wav_files_or_none)
    """
    if config is None:
        config = {}

    # Check if wav_file column exists (from automfcc.py)
    wav_file_column = 'wav_file'
    if wav_file_column not in df.columns:
        raise ValueError("No 'wav_file' column found in the data. Cannot track test files. "
                         "Please update automfcc.py to include WAV file references in the output CSV.")

    # Handle wav_file column
    wav_files = None
    if 'wav_file' in df.columns:
        # Temporarily save the wav_file column
        wav_files = df['wav_file'].copy()
        # Drop the wav_file column before splitting
        df_without_wavfile = df.drop(columns=['wav_file'])
        # Now split
        mfccs, speaker = split_data(df_without_wavfile)
    else:
        mfccs, speaker = split_data(df)

    # convert speaker to the correct format if needed
    if isinstance(speaker, pd.DataFrame) and speaker.shape[1] == 1:
        speaker = speaker.iloc[:, 0]

    # Check for categorical features in mfccs
    categorical_cols = mfccs.select_dtypes(include=['object', 'category']).columns
    if not categorical_cols.empty:
        print(f"Warning: Found categorical columns: {list(categorical_cols)}")
        print("Consider encoding these columns before training")

    return mfccs, speaker, wav_files


def split_train_test_data(features, target, wav_files=None, config=None):
    """
    Split data into training and testing sets.

    Args:
        features: Feature DataFrame
        target: Target Series/DataFrame
        wav_files: Optional wav file names Series
        config: Optional configuration dict with 'test_size', 'random_state'

    Returns:
        tuple: (features_train, features_test, target_train, target_test, wav_files_train, wav_files_test)
    """
    if config is None:
        config = {}

    test_size = config.get('test_size', 0.1)
    random_state = config.get('random_state', 42)

    # Split the data for training and testing, tracking WAV files
    if wav_files is not None:
        # If we have wav_files, include them in the split
        features_train, features_test, target_train, target_test, wav_files_train, wav_files_test = train_test_split(
            features, target, wav_files, test_size=test_size, random_state=random_state)
    else:
        # Otherwise just do a normal split
        features_train, features_test, target_train, target_test = train_test_split(
            features, target, test_size=test_size, random_state=random_state)
        wav_files_train = None
        wav_files_test = None

    print(f"Train set: {features_train.shape[0]} samples, Test set: {features_test.shape[0]} samples")

    return features_train, features_test, target_train, target_test, wav_files_train, wav_files_test


def save_training_data(features_train, target_train, features_test, target_test,
                       input_prefix, output_prefix, wav_files_test=None, target_test_series=None):
    """
    Save training and testing data to CSV files.

    Args:
        features_train: Training features DataFrame
        target_train: Training targets
        features_test: Testing features DataFrame
        target_test: Testing targets
        input_prefix: Prefix for training files
        output_prefix: Prefix for testing files
        wav_files_test: Optional test wav file names
        target_test_series: Optional test targets as series for mapping

    Returns:
        list: List of files created
    """
    files_created = []

    # Save the split data to CSV files
    train_mfcc_file = input_prefix + "_mfccs.csv"
    train_speaker_file = input_prefix + "_speakers.csv"
    test_mfcc_file = output_prefix + "_mfccs.csv"
    test_speaker_file = output_prefix + "_speakers.csv"

    features_train.to_csv(train_mfcc_file, index=False)
    files_created.append(train_mfcc_file)

    target_train.to_csv(train_speaker_file, index=False)
    files_created.append(train_speaker_file)

    features_test.to_csv(test_mfcc_file, index=False)
    files_created.append(test_mfcc_file)

    target_test.to_csv(test_speaker_file, index=False)
    files_created.append(test_speaker_file)

    print("Saved train and test splits to CSV files")

    # Save test set mapping for reference if we have wav files
    if wav_files_test is not None:
        test_mapping_file = output_prefix + "_test_mapping.csv"
        test_mapping = pd.DataFrame({
            'speaker': target_test_series if target_test_series is not None else target_test,
            'wav_file': wav_files_test
        })
        test_mapping.to_csv(test_mapping_file, index=False)
        files_created.append(test_mapping_file)
        print(f"Saved test mapping to {test_mapping_file}")

    return files_created


def copy_test_wav_files(target_test, wav_files_test, wav_dir, test_wav_dir):
    """
    Copy WAV files for the test set to a separate directory.

    Args:
        target_test: Test target labels
        wav_files_test: Test wav file names
        wav_dir: Source directory containing WAV files by speaker
        test_wav_dir: Destination directory for test WAV files

    Returns:
        dict: Statistics about file copying (files_copied, files_not_found)
    """
    files_copied = 0
    files_not_found = 0

    for speaker_id, wav_filename in zip(target_test, wav_files_test):
        # Create speaker directory in test directory
        test_speaker_dir = os.path.join(test_wav_dir, str(speaker_id))
        os.makedirs(test_speaker_dir, exist_ok=True)

        # Construct source path
        source_path = os.path.join(wav_dir, str(speaker_id), wav_filename)

        # If the source doesn't exist, try adding .wav extension
        if not os.path.exists(source_path) and not wav_filename.endswith('.wav'):
            source_path = os.path.join(wav_dir, str(speaker_id), wav_filename + '.wav')

        # Copy the file if it exists
        if os.path.exists(source_path):
            dest_path = os.path.join(test_speaker_dir, wav_filename)
            shutil.copy2(source_path, dest_path)
            files_copied += 1
        else:
            print(f"Warning: WAV file not found: {source_path}")
            files_not_found += 1

    print(f"Copied {files_copied} WAV files to test directory: {test_wav_dir}")
    if files_not_found > 0:
        print(f"⚠️ WARNING: Could not find {files_not_found} WAV files for test samples")

    return {
        'files_copied': files_copied,
        'files_not_found': files_not_found
    }


def setup_test_directory(test_wav_dir):
    """
    Set up the test WAV directory, removing existing one if present.

    Args:
        test_wav_dir: Path to test WAV directory

    Returns:
        str: The created directory path
    """
    if os.path.exists(test_wav_dir):
        shutil.rmtree(test_wav_dir)
        print(f"Deleted existing directory for test WAV files: {test_wav_dir}")

    os.makedirs(test_wav_dir, exist_ok=True)
    print(f"Created directory for test WAV files: {test_wav_dir}")

    return test_wav_dir


def train_model_pipeline(input_file, output_prefix, model_file, wav_dir, config=None):
    """
    Complete model training pipeline.

    Args:
        input_file: CSV file with MFCC features
        output_prefix: Prefix for test output files
        model_file: Where to save the trained model
        wav_dir: Directory containing WAV files by speaker
        config: Optional configuration dict

    Returns:
        dict: Results with model, training_time, and file statistics
    """
    if config is None:
        config = {}

    input_prefix = os.path.splitext(input_file)[0]

    # Create a directory for test WAV files
    test_wav_dir = output_prefix + "_wav"
    setup_test_directory(test_wav_dir)

    # Read the CSV with MFCC features
    df = pd.read_csv(input_file, delimiter=',')
    print(f"Loaded data with {df.shape[0]} rows and {df.shape[1]} columns")

    # Prepare data for training
    mfccs, speaker, wav_files = prepare_data_for_training(df, config)

    # Split the data
    features_train, features_test, target_train, target_test, wav_files_train, wav_files_test = split_train_test_data(
        mfccs, speaker, wav_files, config)

    # Save training data
    files_created = save_training_data(
        features_train, target_train, features_test, target_test,
        input_prefix, output_prefix, wav_files_test, target_test)

    # Copy WAV files for test set
    copy_stats = copy_test_wav_files(target_test, wav_files_test, wav_dir, test_wav_dir)

    # Train the model
    n_estimators = config.get('n_estimators', 100)
    model, training_time = train_model(features_train, target_train, n_estimators, config)

    # Save the model
    print(f'Saving {model_file}...')
    joblib.dump(model, model_file)
    print('✨New model saved.✨')

    return {
        'model': model,
        'training_time': training_time,
        'train_samples': features_train.shape[0],
        'test_samples': features_test.shape[0],
        'files_created': files_created,
        'copy_stats': copy_stats,
        'model_file': model_file,
        'test_wav_dir': test_wav_dir
    }


def main():
    """CLI wrapper function that handles command-line arguments and calls the core pipeline."""
    # Main training process
    if len(sys.argv) < 5:
        print("Usage: python train.py <input_csv> <output_prefix> <model_file> <wav_directory>")
        print(f"Input: {list(sys.argv)} ")
        sys.exit(1)

    input_file = sys.argv[1]  # CSV file with MFCC features
    output_prefix = sys.argv[2]  # Prefix for test output files
    model_file = sys.argv[3]  # Where to save the trained model
    wav_dir = sys.argv[4]  # Directory containing WAV files by speaker

    try:
        # Call the main training pipeline with default configuration
        results = train_model_pipeline(input_file, output_prefix, model_file, wav_dir)

        # Print summary (only in CLI mode)
        print(f"\n🎉 Model training completed successfully!")
        print(f"Training time: {results['training_time']:.2f} seconds")
        print(f"Train samples: {results['train_samples']}, Test samples: {results['test_samples']}")
        print(f"Model saved: {results['model_file']}")
        print(f"Test WAV files: {results['copy_stats']['files_copied']} copied")

    except Exception as error:
        print(f"Error: {error}")
        sys.exit(1)


if __name__ == "__main__":
    main()