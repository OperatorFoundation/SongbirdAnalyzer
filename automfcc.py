"""
Audio Feature Extraction Script

This script processes WAV audio files for multiple users, extracts MFCC features,
and saves both visualization images and feature data to a CSV file.
"""

import csv
import glob
import os
import sys
from pathlib import Path

import librosa.feature
import librosa.display
import matplotlib.pyplot as plt

# Define constants for feature names
MFCC = "mfcc"
DELTA = "delta"
DELTA2 = "delta2"

# Feature dictionary keys
MFCCS = f"{MFCC}s"
MFCCS_SEQ = f"{MFCC}s_seq"
DELTA_MFCCS = f"{DELTA}_{MFCC}s"
DELTA_MFCCS_SEQ = f"{DELTA}_{MFCC}s_seq"
DELTA2_MFCCS = f"{DELTA2}_{MFCC}s"
DELTA2_MFCCS_SEQ = f"{DELTA2}_{MFCC}s_seq"

# Visualization suffixes
VIZ_SUFFIX_MFCC = "1"
VIZ_SUFFIX_DELTA = "2"
VIZ_SUFFIX_DELTA2 = "3"

# CSV header labels
CSV_HEADER_MFCC = "MFCC"
CSV_HEADER_DELTA = "Delta"
CSV_HEADER_DELTA2 = "Delta2"

def extract_features(signal, sample_rate):
    """Extracts MFCC features and their deltas from a WAV audio file."""

    # Extract MFCCs
    mfccs_seq = librosa.feature.mfcc(y=signal, n_mfcc=13, sr=sample_rate)
    mfccs = list(mfccs_seq[0])

    # Extract First Order Delta features
    delta_mfccs_seq = librosa.feature.delta(mfccs_seq)
    delta_mfccs = list(delta_mfccs_seq[0])

    # Extract Second Order Delta Features
    delta2_mfccs_seq = librosa.feature.delta(mfccs_seq, order=2)
    delta2_mfccs = list(delta2_mfccs_seq[0])

    return {
        MFCCS: mfccs,
        MFCCS_SEQ: mfccs_seq,
        DELTA_MFCCS: delta_mfccs,
        DELTA_MFCCS_SEQ: delta_mfccs_seq,
        DELTA2_MFCCS: delta2_mfccs,
        DELTA2_MFCCS_SEQ: delta2_mfccs_seq
    }

def save_visualization(feature_seq, filename, sample_rate):
    """Save a visualization of the feature sequence."""
    plt.figure(figsize=(25, 10))
    librosa.display.specshow(feature_seq, x_axis="time", sr=sample_rate)
    plt.colorbar(format="%+2.f")
    plt.savefig(filename)
    plt.close()

def create_visualization(features, audio_file_path, sample_rate):
    """Create and save visualizations for all feature types."""
    # Make sure the image directory exists
    os.makedirs("images", exist_ok=True)
    base_file_name = Path(audio_file_path).stem

    # Generate and save visualizations for each feature type
    feature_types = [
        (MFCCS_SEQ, VIZ_SUFFIX_MFCC),
        (DELTA_MFCCS_SEQ, VIZ_SUFFIX_DELTA),
        (DELTA2_MFCCS_SEQ, VIZ_SUFFIX_DELTA2)
    ]

    for feature_name, suffix in feature_types:
        output_path = os.path.join("images", f"{base_file_name}{suffix}.png")
        save_visualization(features[feature_name], output_path, sample_rate)

def generate_csv_header(features):
    """Generate CSV header row based on feature dimensions"""
    header = ["speaker", "wav_file"]

    # Add column names for each feature type
    for name, feature_list in [
        (CSV_HEADER_MFCC, features[MFCCS]),
        (CSV_HEADER_DELTA, features[DELTA_MFCCS]),
        (CSV_HEADER_DELTA2, features[DELTA2_MFCCS])
    ]:
        header.extend([f"{name}_{i +  1}" for i in range(len(feature_list))])

    return header

def process_audio_file(audio_file_path, speaker_id, csv_writer, first_row_flag):
    """Process a single audio file and write features to CSV."""
    try:
        # Load the audio file
        signal, sample_rate = librosa.load(audio_file_path)

        # Extract features
        features = extract_features(signal, sample_rate)

        # Create visualizations
        create_visualization(features, audio_file_path, sample_rate)

        # Write header row if this is the first file
        if first_row_flag:
            header = generate_csv_header(features)
            csv_writer.writerow(header)
            first_row_flag = False

        # Get just the file name without the path
        wav_file_name = os.path.basename( audio_file_path )

        # Write feature values for this file
        row_data = [speaker_id, wav_file_name] + features[MFCCS] + features[DELTA_MFCCS] + features[DELTA2_MFCCS]
        csv_writer.writerow(row_data)
        return first_row_flag

    except Exception as error:
        print(f'Error processing {audio_file_path}: {error}')
        return first_row_flag

def main():
    # Validate command line arguments
    if len(sys.argv) < 3:
        print("Usage: python automfcc.py <input_directory> <output_csv_file>")
        sys.exit(1)

    input_directory = sys.argv[1]
    output_csv = sys.argv[2]

    # Get list of speakers (directories)
    speakers = os.listdir(input_directory)

    # Open output CSV file
    with open(output_csv, 'w', newline='') as csv_file:
        csv_writer = csv.writer(csv_file, delimiter=',')
        first_row = True

        # Process each speaker
        for speaker in speakers:
            print(f"Processing speaker {speaker}")

            # Get all wav files for this speaker
            wav_files = glob.glob(os.path.join(input_directory, speaker, "*.wav"))

            # Process each wav file
            for wav_file in wav_files:
                print(f"Processing {wav_file}...")
                first_row = process_audio_file(wav_file, speaker, csv_writer, first_row)



if __name__ == "__main__":
    main()
