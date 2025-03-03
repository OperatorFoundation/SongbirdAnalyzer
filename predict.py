import sys
import joblib
import pandas as pd
from sklearn.metrics import accuracy_score

df = pd.read_csv(sys.argv[1])
x = df.drop(columns=["speaker"])
y = df["speaker"]

model = joblib.load(sys.argv[2])
predictions = model.predict(x)

print("🎯Accuracy:", accuracy_score(y, predictions))
