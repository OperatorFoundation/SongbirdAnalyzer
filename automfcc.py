"""
Audio Feature Extraction Script

This script processes WAV audio files organized in a directory structure of:
    working_dir/
        mode1/
            speaker1/
                audio1.wav
                audio2.wav
            speaker2/
                ...
        mode2/
            ...

It extracts MFCC features and saves both combined and mode-specific results.
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
    """Generate CSV header row based on feature dimensions."""
    header = ["speaker", "wav_file", "mode"]

    # Add column names for each feature type
    for name, feature_list in [
        (CSV_HEADER_MFCC, features[MFCCS]),
        (CSV_HEADER_DELTA, features[DELTA_MFCCS]),
        (CSV_HEADER_DELTA2, features[DELTA2_MFCCS])
    ]:
        header.extend([f"{name}_{i + 1}" for i in range(len(feature_list))])

    return header

def process_audio_file(audio_file_path, speaker_id, mode_name, csv_writer, first_row_flag):
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
        wav_file_name = os.path.basename(audio_file_path)

        # Write feature values for this file
        row_data = [speaker_id, wav_file_name, mode_name] + features[MFCCS] + features[DELTA_MFCCS] + features[DELTA2_MFCCS]
        csv_writer.writerow(row_data)
        return first_row_flag

    except Exception as error:
        print(f'Error processing {audio_file_path}: {error}')
        return first_row_flag

def extract_speaker_labels(csv_file_path, output_path):
    """Extract speaker labels from the MFCC CSV file and save to a new CSV file."""
    try:
        # Read the CSV file
        with open(csv_file_path, 'r', newline='') as csv_file:
            csv_reader = csv.reader(csv_file)
            header = next(csv_reader) # Skip the header
            speakers = [row[0] for row in csv_reader]

        # Write the speaker labels to a new file
        with open(output_path, 'w', newline='') as output_file:
            csv_writer = csv.writer(output_file)
            csv_writer.writerow(['speaker'])
            for speaker in speakers:
                csv_writer.writerow([speaker])

        print(f"Saved {len(speakers)} speaker labels to {output_path}")

    except Exception as error:
        print(f"Error extracting speaker labels from {csv_file_path}: {error}")

def main():
    # Validate command line arguments
    if len(sys.argv) < 3:
        print("Usage: python automfcc.py <input_directory> <output_csv_file>")
        sys.exit(1)

    input_directory = sys.argv[1]
    output_csv = sys.argv[2]
    output_base = output_csv.replace('.csv', '')

    # Check if input directory exists
    if not os.path.isdir(input_directory):
        print(f"Input directory '{input_directory}' not found.")
        sys.exit(1)

    # Get list of mode directories
    try:
        mode_directories = [directory_name  for directory_name  in os.listdir(input_directory)
                            if os.path.isdir(os.path.join(input_directory, directory_name))]

        if not mode_directories:
            print(f"No mode directories found in {input_directory}.")
            sys.exit(1)
    except Exception as error:
        print(f"Error accessing input directory '{input_directory}': {error}")
        sys.exit(1)

    # Open the combined CSV file for all modes
    combined_csv_path = f"{output_base}_mfccs.csv"
    with open(combined_csv_path, 'w', newline='') as combined_csv_file:
        combined_csv_writer = csv.writer(combined_csv_file, delimiter=',')
        combined_first_row = True

        # Process each mode directory
        for mode in mode_directories:
            mode_path = os.path.join(input_directory, mode)
            print(f"\nProcessing mode directory: {mode}")

            # Create mode-specific output file
            mode_csv_path = f"{output_base}_{mode}_mfccs.csv"
            with open(mode_csv_path, 'w', newline='') as mode_csv_file:
                mode_csv_writer = csv.writer(mode_csv_file, delimiter=',')
                mode_first_row = True

                # Get all speakers within this mode
                try:
                    speakers = [speaker for speaker in os.listdir(mode_path)
                                if os.path.isdir(os.path.join(mode_path, speaker))]
                except Exception as error:
                    print(f"Error accessing mode directory '{mode_path}': {error}")
                    continue

                # Process each speaker within this mode
                for speaker in speakers:
                    speaker_path = os.path.join(mode_path, speaker)
                    print(f"    Processing speaker {speaker} in {mode} mode...")

                    # Get all the WAV files for this speaker in this mode
                    wav_files = glob.glob(os.path.join(speaker_path, "*.wav"))

                    # Process each WAV file
                    for wav_file in wav_files:
                        print(f"        Processing file {os.path.basename(wav_file)}...")

                        # Add to combined CSV
                        combined_first_row = process_audio_file(wav_file, speaker, mode, combined_csv_writer, combined_first_row)

                        # Add to mode specific CSV
                        mode_first_row = process_audio_file(wav_file, speaker, mode, mode_csv_writer, mode_first_row)

            # Extract speaker labels for this mode
            if os.path.exists(mode_csv_path):
                mode_speaker_csv = f"{output_base}_{mode}_speakers.csv"
                extract_speaker_labels(mode_csv_path, mode_speaker_csv)

    # Extract speaker labels for combined data
    if os.path.exists(combined_csv_path):
        combined_speaker_csv = f"{output_base}_speakers.csv"
        extract_speaker_labels(combined_csv_path, combined_speaker_csv)

    print("\nFeature extraction complete!")

if __name__ == "__main__":
    main()
