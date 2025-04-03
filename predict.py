import sys
import joblib
import pandas as pd
from sklearn.metrics import accuracy_score

x = pd.read_csv(sys.argv[1]+"_x.csv")
y = pd.read_csv(sys.argv[1]+"_y.csv")

model = joblib.load(sys.argv[2])
predictions = model.predict(x)

print("🎯Accuracy:", accuracy_score(y, predictions))
