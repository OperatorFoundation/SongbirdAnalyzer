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
for leftfilename in mfccs:
    (leftuser, leftindex) = parse(leftfilename)
    left = load(leftfilename)
    result = [leftuser] + list(left)
    writer.writerow(result)
