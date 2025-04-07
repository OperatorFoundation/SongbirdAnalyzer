import sys

import pandas as pd

results_data = pd.read_csv(sys.argv[1])
mfccs = results_data.drop(columns=["speaker"])
correct_answers = results_data["speaker"]

mfccs.to_csv(sys.argv[2]+"_x.csv", index=True)
correct_answers.to_csv(sys.argv[2]+"_y.csv", index=True)