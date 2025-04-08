import sys
import joblib
import pandas as pd
from sklearn.metrics import accuracy_score

features = pd.read_csv(sys.argv[1] + "_mfccs.csv")
target = pd.read_csv(sys.argv[1] + "_speakers.csv")

model = joblib.load(sys.argv[2])
predictions = model.predict(features)

print("🎯Accuracy:", accuracy_score(target, predictions))
