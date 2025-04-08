import sys
from pyexpat import features

import pandas as pd
import joblib
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split

def split_data(data_frame, first_column='speaker'):
    """
    Split a Pandas DataFrame into two seperate DataFrames:
        1. A DataFrame with only the first column. (defaults to 'speaker')
        2. A DataFrame with all the remaining columns.

    :param data_frame: pandas.DataFrame The dataframe to split.
    :param first_column: str, optional defaults to 'speaker'
    :return: A tuple with both DataFrames
    """

    # make sure the requested first column exists
    if first_column not in data_frame.columns:
        raise ValueError(f"Column {first_column} is not present in the dataframe.")

    # Create a DataFrame with the first column
    target_data_frame = data_frame[[first_column]].copy()

    # Create a DataFrame with the remaining columns
    features_data_frame = data_frame.drop(columns=[first_column]).copy()

    return features_data_frame, target_data_frame

input_file = sys.argv[1]
output_prefix = sys.argv[2]
model_file = sys.argv[3]

# read the csv
df = pd.read_csv(input_file, delimiter=',')
print(f"Loaded data with {df.shape[0]} rows and {df.shape[1]} columns")

# split it into two tables
x, y = split_data(df)

# convert y to the correct format
if isinstance(y, pd.DataFrame) and y.shape[1] == 1:
    y = y.iloc[:, 0]

# Check for categorical features in x
categorical_cols = x.select_dtypes(include=['object', 'category']).columns
if not categorical_cols.empty:
    print(f"Warning: Found categorical columns: {list(categorical_cols)}")
    print("Consider encoding these columns before training")

x_train, x_test, y_train, y_test = train_test_split(x, y, test_size=0.1, random_state=42)
print(f"Train set: {x_train.shape[0]} samples, Test set: {x_test.shape[0]} samples")

x_train.to_csv(input_file +".x", index=False)
y_train.to_csv(input_file +".y", index=False)
x_test.to_csv(output_prefix +"_x.csv", index=False)
y_test.to_csv(output_prefix +"_y.csv", index=False)
print("Saved train and test splits to CSV files")

model = RandomForestClassifier()
model.fit(x_train, y_train)

print(f'Saving {model_file}...')
joblib.dump(model, model_file)
print('✨New model saved.✨')

