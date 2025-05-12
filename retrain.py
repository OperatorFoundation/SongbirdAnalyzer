import joblib
import pandas as pd
import numpy as np

from train import train_with_progress

MODEL_FILE="songbird.pkl"
TRAIN_MFCCS_FILE="results/training_mfccs_trimmed.csv"
TRAIN_SPEAKERS_FILE="results/training_speakers.csv"

# Load the csv files
mffccs_data = pd.read_csv(TRAIN_MFCCS_FILE)
# Create a DataFrame with the first column

speakers_data = pd.read_csv(TRAIN_SPEAKERS_FILE)
speakers_data_raveled = np.ravel(speakers_data)

# Train the model
model = train_with_progress(mffccs_data, speakers_data_raveled)

print(f'Saving {MODEL_FILE}...')
joblib.dump(model, MODEL_FILE)
print('✨New model saved.✨')