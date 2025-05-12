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

# Import the Spinner class from spinner.py
from utils.spinner import Spinner

# Define constants for feature names and messages
MFCC = "mfcc"
DELTA = "delta"
DELTA2 = "delta2"
WAV_EXTENSION = ".wav"
CSV_EXTENSION = ".csv"
PNG_EXTENSION = ".png"

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

# CSV column names
SPEAKER_COLUMN = "speaker"
WAV_FILE_COLUMN = "wav_file"
MODE_COLUMN = "mode"

# Directory and file names
IMAGES_DIR = "images"

# Status messages
MSG_STARTING = "Starting audio feature extraction..."
MSG_DETECTING = "Detecting directory structure..."
MSG_STRUCTURE_DETECTED = "Detected {} structure with {} {}"
MSG_MODE_BASED = "mode-based"
MSG_SPEAKER_BASED = "speaker-based"
MSG_MODES = "modes"
MSG_SPEAKERS = "speakers"
MSG_PROCESSING_MODE = "Processing mode: {}..."
MSG_PROCESSING_SPEAKER = "Processing speaker: {}..."
MSG_PROCESSING_FILES = "Processing {} files for speaker {}..."
MSG_PROCESSING_FILE = "Processing {}..."
MSG_PROCESSED_FILES = "Processed all audio files in {:.2f} seconds"
MSG_CREATING_LABELS = "Creating speaker label files..."
MSG_COMPLETE = "Feature extraction complete!"
MSG_ERROR = "Error: {}"
MSG_SAVED_LABELS = "Saved {} speaker labels to {}"
MSG_ERROR_LABELS = "Error extracting speaker labels from {}: {}"
MSG_NO_SUBDIRS = "No subdirectories found in {}."

def extract_features(signal, sample_rate):
    """Extracts MFCC features and their deltas from a WAV audio signal."""
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
    os.makedirs(IMAGES_DIR, exist_ok=True)
    base_file_name = Path(audio_file_path).stem

    # Generate and save visualizations for each feature type
    feature_types = [
        (MFCCS_SEQ, VIZ_SUFFIX_MFCC),
        (DELTA_MFCCS_SEQ, VIZ_SUFFIX_DELTA),
        (DELTA2_MFCCS_SEQ, VIZ_SUFFIX_DELTA2)
    ]

    for feature_name, suffix in feature_types:
        output_path = os.path.join(IMAGES_DIR, f"{base_file_name}{suffix}{PNG_EXTENSION}")
        save_visualization(features[feature_name], output_path, sample_rate)

def generate_csv_header(features, include_mode=True):
    """Generate CSV header row based on feature dimensions."""
    if include_mode:
        header = [SPEAKER_COLUMN, WAV_FILE_COLUMN, MODE_COLUMN]
    else:
        header = [SPEAKER_COLUMN, WAV_FILE_COLUMN]

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
        spinner: Optional spinner to update during processing

    Returns:
        Updated first_row_flag
    """
    try:
        # Update spinner with current file if provided
        file_name = os.path.basename(audio_file_path)

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

        # Write feature values for this file
        if include_mode:
            row_data = [speaker_id, file_name, mode_name] + features[MFCCS] + features[DELTA_MFCCS] + features[DELTA2_MFCCS]
        else:
            row_data = [speaker_id, file_name] + features[MFCCS] + features[DELTA_MFCCS] + features[DELTA2_MFCCS]

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
            csv_writer.writerow([SPEAKER_COLUMN])
            for speaker in speakers:
                csv_writer.writerow([speaker])

        print(MSG_SAVED_LABELS.format(len(speakers), output_path))

    except Exception as error:
        print(MSG_ERROR_LABELS.format(csv_file_path, error))

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
        print(MSG_NO_SUBDIRS.format(working_directory))
        sys.exit(1)

    # Check the first directory to see if it contains speaker directories
    first_dir_path = os.path.join(working_directory, first_level_dirs[0])
    subdir_contents = os.listdir(first_dir_path)

    # Check if there are subdirectories (likely speaker directories)
    has_subdirs = any(os.path.isdir(os.path.join(first_dir_path, item)) for item in subdir_contents)

    # Check if there are wav files in the first subdirectory
    has_wav_files = any(item.lower().endswith(WAV_EXTENSION) for item in subdir_contents)

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
        spinner: Optional spinner to update during processing

    Returns:
        Dictionary of updated first_row_flags
    """
    # Get all the wav files for this speaker
    wav_files = glob.glob(os.path.join(speaker_path, f"*{WAV_EXTENSION}"))

    # Process each wav file
    for i, wav_file in enumerate(wav_files):
        # Process file and add to each CSV writer
        for writer_name, writer in csv_writers.items():
            first_row_flags[writer_name] = process_audio_file(
                wav_file,
                speaker_id,
                mode_name,
                writer,
                first_row_flags[writer_name],
                include_mode
            )

    return first_row_flags


def main():
    # Validate command line arguments
    if len(sys.argv) < 3:
        print("Usage: python automfcc.py <working_directory> <output_csv_file>")
        sys.exit(1)

    working_directory = sys.argv[1]
    input_csv = sys.argv[2]
    input_base = input_csv.replace(CSV_EXTENSION, '')

    # Check if the input directory exists
    if not os.path.isdir(working_directory):
        print(f"Input directory '{working_directory}' not found.")
        sys.exit(1)

    # Create the main progress spinner
    spinner = Spinner(message=MSG_STARTING)
    spinner.start()

    try:
        # Detect directory structure
        spinner.stop(MSG_DETECTING)
        spinner.start()

        has_modes, first_level_dirs = detect_directory_structure(working_directory)
        structure_type = MSG_MODE_BASED if has_modes else MSG_SPEAKER_BASED
        entity_type = MSG_MODES if has_modes else MSG_SPEAKERS
        spinner.stop(MSG_STRUCTURE_DETECTED.format(structure_type, len(first_level_dirs), entity_type))

        # Create main output CSV file
        main_file_key = "main"
        output_csv_path = f"{input_base}_{MFCCS}{CSV_EXTENSION}"
        csv_files = {main_file_key: open(output_csv_path, 'w', newline='')}
        csv_writers = {main_file_key: csv.writer(csv_files[main_file_key], delimiter=',')}
        first_row_flags = {main_file_key: True}

        # Record start time for overall processing
        start_time = time.time()
        spinner.start()

        # Process files based on directory structure
        if has_modes:
            # For each mode, create a mode-specific CSV file
            for mode_index, mode_name in enumerate(first_level_dirs):
                mode_progress = f"[{mode_index+1}/{len(first_level_dirs)}]"
                spinner.stop(f"{mode_progress} {MSG_PROCESSING_MODE.format(mode_name)}")
                spinner.start()

                mode_path = os.path.join(working_directory, mode_name)
                mode_csv_path = f"{input_base}_{mode_name}_{MFCCS}{CSV_EXTENSION}"

                csv_files[mode_name] = open(mode_csv_path, 'w', newline='')
                csv_writers[mode_name] = csv.writer(csv_files[mode_name], delimiter=',')
                first_row_flags[mode_name] = True

                # Get speakers in this mode
                speakers = [s for s in os.listdir(mode_path) if os.path.isdir(os.path.join(mode_path, s))]

                # Process speakers within this mode
                for speaker_index, speaker in enumerate(speakers):
                    speaker_progress = f"{mode_progress} [{speaker_index+1}/{len(speakers)}]"
                    spinner.stop(f"{speaker_progress} {MSG_PROCESSING_SPEAKER.format(speaker)}")
                    spinner.start()

                    speaker_path = os.path.join(mode_path, speaker)

                    # Process all WAV files for this speaker
                    first_row_flags = process_wav_files(
                        speaker_path,
                        speaker,
                        mode_name,
                        csv_writers,
                        first_row_flags,
                        include_mode=True,
                        spinner=spinner
                    )
        else:
            # Process speakers separately
            for speaker_index, speaker in enumerate(first_level_dirs):
                speaker_progress = f"[{speaker_index+1}/{len(first_level_dirs)}]"
                spinner.stop(f"{speaker_progress} {MSG_PROCESSING_SPEAKER.format(speaker)}")
                spinner.start()

                speaker_path = os.path.join(working_directory, speaker)

                # Process all WAV files for this speaker
                first_row_flags = process_wav_files(
                    speaker_path,
                    speaker,
                    None,
                    csv_writers,
                    first_row_flags,
                    include_mode=False
                )

        # Calculate total processing time
        total_time = time.time() - start_time
        spinner.stop(MSG_PROCESSED_FILES.format(total_time))

        # Finalize results and create speaker label files
        spinner.stop(MSG_CREATING_LABELS)
        spinner.start()

        # Close all csv files and create speaker label files
        for name, file_handle in csv_files.items():
            file_handle.close()

            # Create corresponding speaker label file
            if name == main_file_key:
                speaker_csv = f"{input_base}_speakers{CSV_EXTENSION}"
                csv_path = output_csv_path
            else:
                speaker_csv = f"{input_base}_{name}_speakers{CSV_EXTENSION}"
                csv_path = f"{input_base}_{name}_{MFCCS}{CSV_EXTENSION}"

            if os.path.exists(csv_path):
                extract_speaker_labels(csv_path, speaker_csv)

        spinner.stop(MSG_COMPLETE)

    except Exception as error:
        # Log the error details
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        # Ensure the spinner is always stopped, even if an exception occurs
        if 'spinner' in locals():
            spinner.stop(MSG_COMPLETE if 'error' not in locals() else MSG_ERROR.format(error))


if __name__ == "__main__":
    main()