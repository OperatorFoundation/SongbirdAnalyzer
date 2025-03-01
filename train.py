import sys
import pandas as pd
import joblib
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score

df = pd.read_csv(sys.argv[1])
X = df.drop(columns=["speaker"])
y = df["speaker"]
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.1)

model = RandomForestClassifier()
model.fit(X_train, y_train)

print('Saving {sys.argv[2]}...')
joblib.dump(model, sys.argv[2])
print('Saved.')

predictions = model.predict(X_test)
print("Accuracy:", accuracy_score(y_test, predictions))
