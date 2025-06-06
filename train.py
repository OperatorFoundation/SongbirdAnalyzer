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

def train_with_progress(features_data_frame, target_data_frame, n_estimators=100):
    """
    Train a Random Forest Classifier model with a spinner animation to show progress.

    This function creates and trains a RandomForestClassifier model while displaying
    a spinner animation to provide visual feedback during the training process.

    Args:
        features_data_frame: DataFrame containing the feature data for training.
        target_data_frame: DataFrame containing the target values for training.
        n_estimators (int): Number of trees in the random forest (default: 100).

    Returns:
        RandomForestClassifier: The trained model.
    """

    print(f"Training RandomForestClassifier with {n_estimators} trees...")

    # Create the model
    model = RandomForestClassifier(n_estimators=n_estimators, verbose=0)

    # Record the start time for calculating training duration
    start_time = time.time()

    # Create a spinner with a custom message and start it
    spinner = Spinner(message="Training model...")
    spinner.start()


    try:
        # Train the model
        model.fit(features_data_frame, target_data_frame)
    finally: # No matter what, stop the spinner
        # Calculate the total training time
        training_time = time.time() - start_time

        completion_message = f"Model training completed in {training_time:.2f} seconds!      \n"
        spinner.stop(completion_message)

    # Return the trained model
    return model

if __name__ == "__main__":
    # Main training process
    if len(sys.argv) < 5:
        print("Usage: python train.py <input_csv> <output_prefix> <model_file> <wav_directory>")
        print(f"Input: {list(sys.argv)} ")
        sys.exit(1)

    input_file = sys.argv[1]  # CSV file with MFCC features
    input_prefix = os.path.splitext(input_file)[0]
    output_prefix = sys.argv[2]  # Prefix for test output files
    model_file = sys.argv[3]  # Where to save the trained model
    wav_dir = sys.argv[4]  # Directory containing WAV files by speaker

    # Create a directory for test WAV files
    test_wav_dir = output_prefix + "_wav"

    if os.path.exists(test_wav_dir):
        shutil.rmtree(test_wav_dir)
        print(f"Deleted existing directory for test WAV files: {test_wav_dir}")

    os.makedirs(test_wav_dir, exist_ok=True)
    print(f"Created directory for test WAV files: {test_wav_dir}")

    # read the csv with MFCC features
    df = pd.read_csv(input_file, delimiter=',')
    print(f"Loaded data with {df.shape[0]} rows and {df.shape[1]} columns")

    # Check if wav_file column exists (from automfcc.py)
    wav_file_column = 'wav_file'
    if wav_file_column not in df.columns:
        print("🛑 ERROR: No 'wav_file' column found in the data. Cannot track test files.")
        print("Please update automfcc.py to include WAV file references in the output CSV.")
        sys.exit(1)

    # split it into features and target
    if 'wav_file' in df.columns:
        # Temporarily save the wav_file column
        wav_files = df['wav_file'].copy()
        # Drop the wav_file column before splitting
        df_without_wavfile = df.drop(columns=['wav_file'])
        # Now split
        mfccs, speaker = split_data(df_without_wavfile)
        # Restore wav_files as a separate variable
    else:
        mfccs, speaker = split_data(df)
        wav_files = None

    # convert speaker to the correct format if needed
    if isinstance(speaker, pd.DataFrame) and speaker.shape[1] == 1:
        speaker = speaker.iloc[:, 0]

    # Check for categorical features in mfccs
    categorical_cols = mfccs.select_dtypes(include=['object', 'category']).columns
    if not categorical_cols.empty:
        print(f"Warning: Found categorical columns: {list(categorical_cols)}")
        print("Consider encoding these columns before training")

    # Split the data for training and testing, tracking WAV files
    if wav_files is not None:
        # If we have wav_files, include them in the split
        features_train, features_test, target_train, target_test, wav_files_train, wav_files_test = train_test_split(
            mfccs, speaker, wav_files, test_size=0.1, random_state=42)
    else:
        # Otherwise just do a normal split
        features_train, features_test, target_train, target_test = train_test_split(
            mfccs, speaker, test_size=0.1, random_state=42)
        wav_files_train = None
        wav_files_test = None

    print(f"Train set: {features_train.shape[0]} samples, Test set: {features_test.shape[0]} samples")

    # Save the split data to CSV files
    features_train.to_csv(input_prefix + "_mfccs.csv", index=False)
    target_train.to_csv(input_prefix + "_speakers.csv", index=False)
    features_test.to_csv(output_prefix + "_mfccs.csv", index=False)
    target_test.to_csv(output_prefix + "_speakers.csv", index=False)
    print("Saved train and test splits to CSV files")

    # Save test set mapping for reference
    test_mapping = pd.DataFrame({
        'speaker': target_test,
        'wav_file': wav_files_test
    })
    test_mapping.to_csv(output_prefix + "_test_mapping.csv", index=False)
    print(f"Saved test mapping to {output_prefix}_test_mapping.csv")

    # Copy the WAV files for the test set
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

    # Train the model
    model = train_with_progress(features_train, target_train)

    print(f'Saving {model_file}...')
    joblib.dump(model, model_file)
    print('✨New model saved.✨')