import sys
import joblib
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score

df = pd.read_csv(sys.argv[1])
X = df.drop(columns=["speaker"])
y = df["speaker"]
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.5)

model = joblib.load(sys.argv[2])
predictions = model.predict(X_test)

print("Note: this accuracy will be overly high because we are not splitting the test data out properly at this stage")
print("This is just a test that the model is loading. Look at the train.py accuracy rating for a more realistic number.")
print("In the future, we can test with additional data not used during training.")
print("Accuracy:", accuracy_score(y_test, predictions))

