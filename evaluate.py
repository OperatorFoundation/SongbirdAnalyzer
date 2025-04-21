import sys
import os
import pandas as pd

def main():
    if len(sys.argv) < 2:
        print("Usage: python evaluate.py <results_file.csv> [output_prefix]")
        sys.exit(1)

    # Parse arguments
    results_file = sys.argv[1]
    output_prefix = sys.argv[1] if len(sys.argv) < 3 else sys.argv[2]

    print(f"Evaluating {results_file}")

    # Load the results data
    try:
        results_data = pd.read_csv(results_file)
        print(f"Loaded data with {results_data.shape[0]} rows and {results_data.shape[1]} columns")
    except Exception as e:
        print(f"Failed to load data from {results_file}: {e}")
        sys.exit(1)

    # Extract features and correct answers
    if "speaker" not in results_data.columns:
        print(f"No speaker column in {results_file}")
        sys.exit(1)

    # Get features
    exclude_columns = ["speaker"]
    if "wav_file" in results_data.columns:
        exclude_columns.append("wav_file")

    mfccs = results_data.drop(columns=exclude_columns)
    correct_answers = results_data["speaker"]

    # Save the extracted data
    mfccs.to_csv(f"{output_prefix}_mfccs.csv", index=False)
    correct_answers.to_csv(f"{output_prefix}_speakers.csv", index=False)
    print(f"Saved features to {output_prefix}_mfccs.csv")
    print(f"Saved labels to {output_prefix}_speakers.csv")

    # Calculate basic statistics about the data
    print("\nData  Statistics:")
    print(f"Total samples: {len(results_data)}")

    # Count samples per speaker
    speaker_counts = results_data["speaker"].value_counts()
    print("\nSamples per speaker:")
    for speaker, count in speaker_counts.items():
        print(f"  Speaker {speaker}: {count} samples")

    if "wav_file" in results_data.columns:
        # Extract mode from wav file names (format *-n.wav, *-p.wav, etc.)
        results_data["mode"] = results_data["wav_file"].apply(
            lambda x: x.split("-")[-1].split(".")[0] if "-" in x else "unknown"
        )

        mode_counts = results_data["mode"].value_counts()
        print("\nSamples per mode:")
        for mode, count in mode_counts.items():
            print(f"  Mode {mode}: {count} samples")

    print("\nEvaluation data ready!")

if __name__ == "__main__":
    main()

