import os
import shutil
import sys

import pandas as pd
import joblib

from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split

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


# Main training process

if len(sys.argv) < 5:
    print("Usage: python script.py <input_csv> <output_prefix> <model_file> <wav_directory>")
    sys.exit(1)

input_file = sys.argv[1]
input_prefix = os.path.splitext(input_file)[0]
output_prefix = sys.argv[2]
model_file = sys.argv[3]
wav_dir = sys.argv[4]

# Create a directory for test WAV files
test_wav_dir = output_prefix + "_wav"
os.makedirs(test_wav_dir, exist_ok=True)
print(f"Created directory for test WAV files: {test_wav_dir}")

# read the csv
df = pd.read_csv(input_file, delimiter=',')
print(f"Loaded data with {df.shape[0]} rows and {df.shape[1]} columns")

# split it into two tables
mfccs, speaker = split_data(df)

# convert y to the correct format
if isinstance(speaker, pd.DataFrame) and speaker.shape[1] == 1:
    speaker = speaker.iloc[:, 0]

# Check for categorical features in x
categorical_cols = mfccs.select_dtypes(include=['object', 'category']).columns
if not categorical_cols.empty:
    print(f"Warning: Found categorical columns: {list(categorical_cols)}")
    print("Consider encoding these columns before training")

# Preserve the indices from the original dataframe for tracking the test set
df_with_index = df.reset_index()  # Add an index column to track original positions
original_indices = df_with_index['index']  # Store original indices

# Split data while keeping track of indices
features_train, features_test, target_train, target_test, idx_train, idx_test = train_test_split(
    mfccs, speaker, original_indices, test_size=0.1, random_state=42)

print(f"Train set: {features_train.shape[0]} samples, Test set: {features_test.shape[0]} samples")

features_train.to_csv(input_prefix + "_mfccs.csv", index=False)
target_train.to_csv(input_prefix + "_speakers.csv", index=False)
features_test.to_csv(output_prefix + "_mfccs.csv", index=False)
target_test.to_csv(output_prefix + "_speakers.csv", index=False)
print("Saved train and test splits to CSV files")

# Save the mapping between test samples and their file identifiers
# This assumes the DataFrame has a column that identifies the WAV files called file_id
if 'file_id' in df.columns:
    # Get the file IDs for test samples
    file_ids = df.iloc[idx_test]['file_id'].tolist()
else:
    # If no file_id column exists, use speaker IDs and create a mapping file
    file_ids = target_test.tolist()

    # Save the mapping
    pd.DataFrame({'speaker': target_test, 'index': idx_test}).to_csv(output_prefix + "_test_mapping.csv", index=False)

# Copy the WAV files for test samples to the test directory
files_copied = 0
wav_files_not_found = []

# 📌 TODO: Adjust the pattern below based on how the WAV files are actually named
for file_id in file_ids:
    # Search for matching WAV files in the source directory
    for wav_file in os.listdir(wav_dir):
        if wav_file.endswith(".wav") and str(file_id) in wav_file:
            source_path = os.path.join(wav_dir, wav_file)
            destination_path = os.path.join(test_wav_dir, wav_file)
            shutil.copy2(source_path, destination_path)
            files_copied += 1
            break
        else:
            wav_files_not_found.append(file_id)

print(f"Copied {files_copied} WAV files to test directory: {test_wav_dir}")
if wav_files_not_found:
    print(f"⚠️ WARNING: Could not find WAV files for {len(wav_files_not_found)} test samples")
    pd.DataFrame({'missing_file_id': wav_files_not_found}).to_csv(
        output_prefix + "_missing_wavs.csv", index=False)

# Train the model
model = RandomForestClassifier()
model.fit(features_train, target_train)

print(f'Saving {model_file}...')
joblib.dump(model, model_file)
print('✨New model saved.✨')

