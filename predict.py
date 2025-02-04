import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score

df = pd.read_csv("results/training.csv")
X = df.drop(columns=["speaker"])
y = df["speaker"]
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.5)

model = RandomForestClassifier()
model.fit(X_train, y_train)
predictions = model.predict(X_test)

print("Accuracy:", accuracy_score(y_test, predictions))
