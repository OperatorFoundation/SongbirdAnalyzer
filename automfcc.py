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
import time
from pathlib import Path

import librosa.feature
import librosa.display
import matplotlib.pyplot as plt

from spinner import Spinner

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
    """
    Extracts MFCC features and their deltas from a WAV audio signal.

    Args:
        signal: Audio signal data
        sample_rate: Sample rate of the audio signal

    Returns:
        Dictionary containing extracted features
    """

    # Create a spinner for the feature extraction process
    spinner = Spinner(message="Extracting features...")
    spinner.start()

    try:
        # Extract MFCCs
        mfccs_seq = librosa.feature.mfcc(y=signal, n_mfcc=13, sr=sample_rate)
        mfccs = list(mfccs_seq[0])

        # Extract First Order Delta features
        delta_mfccs_seq = librosa.feature.delta(mfccs_seq)
        delta_mfccs = list(delta_mfccs_seq[0])

        # Extract Second Order Delta Features
        delta2_mfccs_seq = librosa.feature.delta(mfccs_seq, order=2)
        delta2_mfccs = list(delta2_mfccs_seq[0])

        result = {
            MFCCS: mfccs,
            MFCCS_SEQ: mfccs_seq,
            DELTA_MFCCS: delta_mfccs,
            DELTA_MFCCS_SEQ: delta_mfccs_seq,
            DELTA2_MFCCS: delta2_mfccs,
            DELTA2_MFCCS_SEQ: delta2_mfccs_seq
        }

        spinner.stop("Features extracted successfully")
        return result

    except Exception as error:
        spinner.stop(f"Error extracting features: {str(error)}")
        raise

def save_visualization(feature_seq, filename, sample_rate):
    """Save a visualization of the feature sequence."""
    plt.figure(figsize=(25, 10))
    librosa.display.specshow(feature_seq, x_axis="time", sr=sample_rate)
    plt.colorbar(format="%+2.f")
    plt.savefig(filename)
    plt.close()

def create_visualization(features, audio_file_path, sample_rate):
    """
    Create and save visualizations for all feature types.

    Args:
        features: Dictionary of extracted features
        audio_file_path: Path to the audio file
        sample_rate: Sample rate of the audio
    """

    # Create a spinner for the visualization creation
    spinner = Spinner(message=f"Creating visualizations for {os.path.basename(audio_file_path)}...")
    spinner.start()

    try:
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

        spinner.stop("Visualizations created successfully")

    except Exception as error:
        spinner.stop(f"Error creating visualizations: {str(error)}")
        raise


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
    """
    Process a single audio file and write features to CSV.

    Args:
        audio_file_path: Path to the audio file
        speaker_id: ID of the speaker
        mode_name: Name of the mode (or None)
        csv_writer: CSV writer object
        first_row_flag: Flag indicating if this is the first row
        include_mode: Whether to include mode column

    Returns:
        Updated first_row_flag
    """

    try:
        file_name = os.path.basename(audio_file_path)
        spinner = Spinner(message=f"Loading audio file {file_name}...")
        spinner.start()

        # Load the audio file
        signal, sample_rate = librosa.load(audio_file_path)
        spinner.stop(f"Loaded {file_name} successfully")

        # Extract features
        features = extract_features(signal, sample_rate)

        # Create visualizations
        create_visualization(features, audio_file_path, sample_rate)

        # Create a spinner for writing to CSV
        spinner = Spinner(message=f"Writing features to CSV for {file_name}...")
        spinner.start()

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
        spinner.stop(f"Features for {file_name} written to CSV")

        return first_row_flag

    except Exception as error:
        # Make sure spinner is stopped if there's an error
        if 'spinner' in locals():  # <--- NEW CODE
            spinner.stop(f'Error processing {audio_file_path}: {error}')
        else:
            print(f'Error processing {audio_file_path}: {error}')

        return first_row_flag

def extract_speaker_labels(csv_file_path, output_path):
    """
    Extract speaker labels from the MFCC CSV file and save to a new CSV file.

    Args:
        csv_file_path: Path to the MFCC CSV file
        output_path: Path to save the speaker labels
    """
    spinner = Spinner(message=f"Extracting speaker labels from {os.path.basename(csv_file_path)}...")
    spinner.start()

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

        spinner.stop(f"Saved {len(speakers)} speaker labels to {os.path.basename(output_path)}")

    except Exception as error:
        spinner.stop(f"Error extracting speaker labels from {csv_file_path}: {error}")

def detect_directory_structure(working_directory):
    """
    Detects whether the directory structure has modes or is a simple speaker-based structure.

    Args:
        working_directory: Path to the working directory

    Returns:
        tuple: (has_modes, first_level_dirs)
            - has_modes: True if the structure includes mode directories, False otherwise
            - first_level_dirs: List of directories at the first level (either modes or speakers)
    """

    spinner = Spinner(message=f"Detecting directory structure in {working_directory}...")
    spinner.start()

    try:

        first_level_dirs = [directory for directory in os.listdir(working_directory)
                            if os.path.isdir(os.path.join(working_directory, directory))]
        if not first_level_dirs:
            spinner.stop(f"No subdirectories found in {working_directory}.")
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

        structure_type = "mode-based" if has_modes else "speaker-based"  # <--- NEW CODE
        spinner.stop(f"Detected {structure_type} directory structure with {len(first_level_dirs)} {('modes' if has_modes else 'speakers')}")

        return has_modes, first_level_dirs

    except Exception as error:
        spinner.stop(f"Error detecting directory structure: {error}")
        raise

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

    spinner = Spinner(message=f"Discovering WAV files for speaker {speaker_id}...")
    spinner.start()

    # Get all the wav files for this speaker
    wav_files = glob.glob(os.path.join(speaker_path, "*.wav"))

    spinner.stop(f"Found {len(wav_files)} WAV files for speaker {speaker_id}")

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

        overall_spinner = Spinner(message="Processing audio files...")
        overall_spinner.start()

        # Record start time for overall processing
        start_time = time.time()

        if has_modes:
            # For each mode, create a mode-specific CSV file
            for mode_index, mode_name in enumerate(first_level_dirs):
                mode_spinner = Spinner(
                    message=f"Processing mode: {mode_name} ({mode_index + 1}/{len(first_level_dirs)})...")
                mode_spinner.start()

                mode_path = os.path.join(working_directory, mode_name)
                mode_csv_path = f"{input_base}_{mode_name}_{MFCCS}.csv"

                csv_files[mode_name] = open(mode_csv_path, 'w', newline='')
                csv_writers[mode_name] = csv.writer(csv_files[mode_name], delimiter=',')
                first_row_flags[mode_name] = True

                # Get speakers in this mode with count information
                speakers = [s for s in os.listdir(mode_path) if os.path.isdir(os.path.join(mode_path, s))]
                mode_spinner.stop(f"Mode {mode_name}: found {len(speakers)} speakers")

                # Process speakers within this mode
                for speaker_index, speaker in enumerate(speakers):
                    speaker_spinner = Spinner(
                        message=f"  Processing speaker {speaker} ({speaker_index + 1}/{len(speakers)}) in mode {mode_name}...")
                    speaker_spinner.start()

                    speaker_path = os.path.join(mode_path, speaker)

                    # Get WAV files for this speaker with count information
                    wav_files = glob.glob(os.path.join(speaker_path, "*.wav"))
                    speaker_spinner.stop(f"  Speaker {speaker}: found {len(wav_files)} WAV files")

                    # Process all WAV files for this speaker/mode
                    for file_index, wav_file in enumerate(wav_files):
                        file_spinner = Spinner(message=f"    Processing file {os.path.basename(wav_file)} ({file_index+1}/{len(wav_files)})...")
                        file_spinner.start()

                        # Update both main and mode specific CSVs
                        first_row_flags[main_file_key] = process_audio_file(wav_file, speaker, mode_name, csv_writers[main_file_key], first_row_flags[main_file_key], include_mode=True)
                        first_row_flags[mode_name] = process_audio_file(wav_file, speaker, mode_name, csv_writers[mode_name], first_row_flags[mode_name], include_mode=True)

                        file_spinner.stop(f"    Processed file {os.path.basename(wav_file)}")
        else:
            # Process speakers seperately
            for speaker_index, speaker in enumerate(first_level_dirs):
                speaker_spinner = Spinner(message=f"Processing speaker: {speaker} ({speaker_index+1}/{len(first_level_dirs)})...")
                speaker_spinner.start()

                speaker_path = os.path.join(working_directory, speaker)

                # Get WAV files for this speaker with count information
                wav_files = glob.glob(os.path.join(speaker_path, "*.wav"))
                speaker_spinner.stop(f"Speaker {speaker}: found {len(wav_files)} WAV files")

                # Process all WAV files for this speaker
                for file_index, wav_file in enumerate(wav_files):
                    file_spinner = Spinner(message=f"  Processing file {os.path.basename(wav_file)} ({file_index+1}/{len(wav_files)})...")
                    file_spinner.start()

                    # Update the main csv
                    first_row_flags[main_file_key] = process_audio_file(wav_file, speaker, None, csv_writers[main_file_key], first_row_flags[main_file_key], include_mode=False)

                    file_spinner.stop(f"  Processed file {os.path.basename(wav_file)}")

        # Calculate total processing time
        total_time = time.time() - start_time
        overall_spinner.stop(f"Processed all audio files in {total_time:.2f} seconds")

        finalize_spinner = Spinner(message="Finalizing results and creating speaker label files...")
        finalize_spinner.start()

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

        finalize_spinner.stop("All files processed and speaker labels extracted")
        print("\nFeature extraction complete!")

    except Exception as error:
        # Make sure all spinners are stopped if there's an error
        if 'overall_spinner' in locals():
            overall_spinner.stop(f"Error during processing: {error}")
        if 'finalize_spinner' in locals():
            finalize_spinner.stop(f"Error during finalization: {error}")

        print(f"Error processing directory structure: {error}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
