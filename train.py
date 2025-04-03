import sys
import pandas as pd
import joblib
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split

df = pd.read_csv(sys.argv[1])
x = df.drop(columns=["speaker"])
y = df["speaker"]

x_train, x_test, y_train, y_test = train_test_split(x, y, test_size=0.1, random_state=42)
x_train.to_csv(sys.argv[1]+".x", index=True)  
y_train.to_csv(sys.argv[1]+".y", index=True)  
x_test.to_csv(sys.argv[2]+"_x.csv", index=True)  
y_test.to_csv(sys.argv[2]+"_y.csv", index=True)  

model = RandomForestClassifier()
model.fit(x_train, y_train)

print(f'Saving {sys.argv[3]}...')
joblib.dump(model, sys.argv[3])
print('✨New model saved.✨')
