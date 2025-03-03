import sys
import pandas as pd
import joblib
from sklearn.ensemble import RandomForestClassifier

df = pd.read_csv(sys.argv[1])
x = df.drop(columns=["speaker"])
y = df["speaker"]

model = RandomForestClassifier()
model.fit(x, y)

print('Saving {sys.argv[2]}...')
joblib.dump(model, sys.argv[2])
print('✨New model saved.✨')