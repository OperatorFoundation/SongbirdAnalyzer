import csv
import glob
from sklearn.metrics import mean_squared_error as rmse
import os
from pathlib import Path
import numpy as np

def load(mfccfilename):
    print(f"{mfccfilename}...")
    mfccfile = open(mfccfilename, "r")
    reader = csv.reader(mfccfile, delimiter=",")
    return np.array([float(x) for x in np.array(list(reader)).flatten()])

def parse(filename):
    base = Path(filename).stem
    user = base.split('-')[0]
    index = base.split('n')[1]
    return (user, index)

def process(leftfilename, rightfilename):
    (leftuser, leftindex) = parse(leftfilename)
    (rightuser, rightindex) = parse(rightfilename)
    left = load(leftfilename)
    right = load(rightfilename)
    error = rmse(left, right)

    return [leftuser, leftindex, rightuser, rightindex, error]

users=os.listdir("audio")
mfccs = glob.glob(f"mfccs/*.csv")

writer = csv.writer(open("results/results.csv", "w"))
writers = {}
for leftfilename in mfccs:
    for rightfilename in mfccs:
        result = process(leftfilename, rightfilename)
#        writer.writerow(result)

        leftuser = result[0]
        rightuser = result[2]
        users = [leftuser, rightuser]
        users.sort()

        writer_name = f"{users[0]}-{users[1]}"
        if writer_name in writers:
            writer2 = writers[writer_name]
        else:
            writer2 = csv.writer(open(f"results/{writer_name}.csv", "w"))
            writers[writer_name] = writer2
        writer2.writerow(result)