"""
Audio Feature Extraction Script

This script processes WAV audio files organized in either:
1. Mode-based structure (for evaluation):
    working_dir/
        mode1/
            speaker1/
                audio1.wav
                audio2.wav
            speaker2/
                ...
        mode2/
            ...

2. Simple structure (for training):
    working_dir/
        speaker1/
            audio1.wav
            audio2.wav
        speaker2/
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

def generate_csv_header(features, include_mode=True):
    """Generate CSV header row based on feature dimensions."""
    if include_mode:
        header = ["speaker", "wav_file", "mode"]
    else:
        header = ["speaker", "wav_file"]

    # Add column names for each feature type
    for name, feature_list in [
        (CSV_HEADER_MFCC, features[MFCCS]),
        (CSV_HEADER_DELTA, features[DELTA_MFCCS]),
        (CSV_HEADER_DELTA2, features[DELTA2_MFCCS])
    ]:
        header.extend([f"{name}_{i + 1}" for i in range(len(feature_list))])

    return header

def process_audio_file(audio_file_path, speaker_id, mode_name, csv_writer, first_row_flag, include_mode=True):
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
            header = generate_csv_header(features, include_mode)
            csv_writer.writerow(header)
            first_row_flag = False

        # Get just the file name without the path
        wav_file_name = os.path.basename(audio_file_path)

        # Write feature values for this file
        if include_mode:
            row_data = [speaker_id, wav_file_name, mode_name] + features[MFCCS] + features[DELTA_MFCCS] + features[DELTA2_MFCCS]
        else:
            row_data = [speaker_id, wav_file_name] + features[MFCCS] + features[DELTA_MFCCS] + features[DELTA2_MFCCS]

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

def detect_directory_structure(working_directory):
    """
   Detects whether the directory structure has modes or is a simple speaker-based structure.

   Returns:
       tuple: (has_modes, first_level_dirs)
           - has_modes: True if the structure includes mode directories, False otherwise
           - first_level_dirs: List of directories at the first level (either modes or speakers)
   """
    first_level_dirs = [directory for directory in os.listdir(working_directory)
                        if os.path.isdir(os.path.join(working_directory, directory))]
    if not first_level_dirs:
        print(f"No subdirectories found in {working_directory}.")
        sys.exit(1)

    # Check the first directory to see if it contains speaker directories
    first_dir_path = os.path.join(working_directory, first_level_dirs[0])
    subdir_contents = os.listdir(first_dir_path)

    # Check if there are subdirectories (likely speaker directories)
    has_subdirs = any(os.path.isdir(os.path.join(first_dir_path, item)) for item in subdir_contents)

    # Check if there are wav files in the first subdirectory
    has_wav_files = any(item.lower().endswith('.wav') for item in subdir_contents)

    # If there are subdirectories and no WAV files, it's likely a mode-based structure
    has_modes = has_subdirs and not has_wav_files

    return has_modes, first_level_dirs

def process_wav_files(speaker_path, speaker_id, mode_name, csv_writers, first_row_flags, include_mode=True):
    """
    Process all WAV files for a speaker and add them to the provided CSV writers.

    Args:
        speaker_path: Path to the speaker directory
        speaker_id: ID of the speaker
        mode_name: Name of the mode (or None if no modes)
        csv_writers: Dictionary of CSV writers to write to
        first_row_flags: Dictionary of flags indicating if this is the first row for each writer
        include_mode: Whether to include the mode column

    Returns:
        Dictionary of updated first_row_flags
    """

    # Get all the wav files for this speaker
    wav_files = glob.glob(os.path.join(speaker_path, "*.wav"))

    # Process each wav file
    for wav_file in wav_files:
        wav_name = os.path.basename(wav_file)
        print(f"{'  ' if mode_name else ''}Processing file {wav_name}...")

        # Process file and add to each CSV writer
        for writer_name, writer in csv_writers.items():
            first_row_flags[writer_name] = process_audio_file(wav_file,
                                                              speaker_id,
                                                              mode_name,
                                                              writer,
                                                              first_row_flags[writer_name],
                                                              include_mode)
    return first_row_flags


def main():
    # Validate command line arguments
    if len(sys.argv) < 3:
        print("Usage: python automfcc.py <working_directory> <output_csv_file>")
        sys.exit(1)

    working_directory = sys.argv[1]
    input_csv = sys.argv[2]
    input_base = input_csv.replace('.csv', '')

    # Check if input directory exists
    if not os.path.isdir(working_directory):
        print(f"Input directory '{working_directory}' not found.")
        sys.exit(1)

    try:
        # Detect directory structure
        has_modes, first_level_dirs = detect_directory_structure(working_directory)
        structure_type = "mode-based" if has_modes else "speaker-based"
        print(f"Detected {structure_type} directory structure")

        # Create main output CSV file
        main_file_key = "main"
        output_csv_path = f"{input_base}_{MFCCS}.csv"
        csv_files = {main_file_key: open(output_csv_path, 'w', newline='')}
        csv_writers = {main_file_key: csv.writer(csv_files[main_file_key], delimiter=',')}
        first_row_flags = {main_file_key: True}

        if has_modes:
            # For each mode, create a mode-specific CSV file
            for mode_name in first_level_dirs:
                print(f"\nProcessing mode: {mode_name}...")
                mode_path = os.path.join(working_directory, mode_name)
                mode_csv_path = f"{input_base}_{mode_name}_{MFCCS}.csv"

                csv_files[mode_name] = open(mode_csv_path, 'w', newline='')
                csv_writers[mode_name] = csv.writer(csv_files[mode_name], delimiter=',')
                first_row_flags[mode_name] = True

                # Process speakers within this mode
                for speaker in [s for s in os.listdir(mode_path) if os.path.isdir(os.path.join(mode_path, s))]:
                    print(f"  Processing speaker {speaker} in mode {mode_name}...")
                    speaker_path = os.path.join(mode_path, speaker)

                    # Process all WAV files for this speaker/mode
                    wav_files = glob.glob(os.path.join(speaker_path, "*.wav"))
                    for wav_file in wav_files:
                        print(f"  Processing {os.path.basename(wav_file)}...")

                        # Update both main and mode specific CSVs
                        first_row_flags[main_file_key] = process_audio_file(wav_file, speaker, mode_name, csv_writers[main_file_key], first_row_flags[main_file_key], include_mode=True)
                        first_row_flags[mode_name] = process_audio_file(wav_file, speaker, mode_name, csv_writers[mode_name], first_row_flags[mode_name], include_mode=True)
        else:
            # Process speakers seperately
            for speaker in first_level_dirs:
                print(f"\nProcessing speaker: {speaker}...")
                speaker_path = os.path.join(working_directory, speaker)

                # Process all WAV files for this speaker
                wav_files = glob.glob(os.path.join(speaker_path, "*.wav"))
                for wav_file in wav_files:
                    print(f"  Processing {os.path.basename(wav_file)}...")

                    # Update the main csv
                    first_row_flags[main_file_key] = process_audio_file(wav_file, speaker, None, csv_writers[main_file_key], first_row_flags[main_file_key], include_mode=False)

        # Close all csv files
        for file_handle in csv_files.values():
            file_handle.close()

        # Create speaker label files
        for name in csv_files.keys():
            if name == main_file_key:
                speaker_csv = f"{input_base}_speakers.csv"
                csv_path = output_csv_path
            else:
                speaker_csv = f"{input_base}_{name}_speakers.csv"
                csv_path = f"{input_base}_{name}_{MFCCS}.csv"

            if os.path.exists(csv_path):
                extract_speaker_labels(csv_path, speaker_csv)

        print("\nFeature extraction complete!")

    except Exception as error:
        print(f"Error processing directory structure: {error}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
