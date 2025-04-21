import sys
import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix


# features = pd.read_csv(sys.argv[1] + "_mfccs.csv")
# target = pd.read_csv(sys.argv[1] + "_speakers.csv")
#
# model = joblib.load(sys.argv[2])
# predictions = model.predict(features)
#
# print("🎯Accuracy:", accuracy_score(target, predictions))

def main():
    if len(sys.argv) < 3:
        print("Usage: python predict.py <data_prefix> <model_file>")
        sys.exit(1)

    data_prefix = sys.argv[1]
    model_file = sys.argv[2]

    print(f"Loading data from {data_prefix}_mfccs.csv  and {data_prefix}_speakers.csv")
    print(f"Loading model from {model_file}")


    # Load the model file
    try:
        features = pd.read_csv(f"{data_prefix}_mfccs.csv")
        target = pd.read_csv(f"{data_prefix}_speakers.csv")

        # Convert target to series if it's a dataframe
        if isinstance(target, pd.DataFrame):
            target = target.iloc[:, 0]

            print(f"Loaded {len(features)} samples for evaluation")
    except Exception as e:
        print(f"Error loading {data_prefix}_mfccs.csv: {e}")
        sys.exit(1)

    # Load model
    try:
        model = joblib.load(model_file)
        print(f"Loaded {model_file}")
    except Exception as e:
        print(f"Error loading {model_file}: {e}")
        sys.exit(1)

    # Make predictions
    try:
        predictions = model.predict(features)

        # Calculate accuracy
        accuracy = accuracy_score(target, predictions)
        print(f"\n🎯 Accuracy: {accuracy:.4f}")

        # Generate classification report
        print("\nClassification report:")
        print("=======================")
        print(f"Target: {target}")
        print(f"Predictions: {predictions}")
        print(classification_report(target, predictions))

        # Generate confusion matrix
        print("\nConfusion matrix:")
        confusion = confusion_matrix(target, predictions)

        # Get unique classes
        classes = np.unique(target)

        # Print matrix with labels
        print(f"{'':8}", end="")
        for cls in enumerate(classes):
            print(f"{cls:8}", end="")
        print()

        for index, cls in enumerate(classes):
            print(f"{cls:8}", end="")
            for j in range(len(classes)):
                print(f"{confusion[index, j]:8}", end="")
            print()

        # Save results to csv
        results_df = pd.DataFrame({'true_speaker': target, 'predicted_speaker': predictions, 'correct': predictions == target})

        results_file = f"{data_prefix}_predictions.csv"
        results_df.to_csv(results_file, index=False)
        print(f"Saved predictions to {results_file}")

    except Exception as e:
        print(f"Error predicting {data_prefix}_mfccs.csv: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()

