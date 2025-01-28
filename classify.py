import csv
import glob
from sklearn.metrics import mean_squared_error as rmse
import os
from pathlib import Path
import numpy as np
import sys

def load(mfccfilename):
    """
    Load an MFCC (Mel-frequency cepstral coefficients) file and convert it into a
    flattened NumPy array of float values. The file is expected to be in CSV format
    and use a comma as the delimiter.

    :param mfccfilename: Path to the MFCC file to be loaded
    :type mfccfilename: str
    :return: NumPy array containing the flattened MFCC values read from the file
    :rtype: numpy.ndarray
    """
    print(f"{mfccfilename}...")
    mfccfile = open(mfccfilename, "r")
    reader = csv.reader(mfccfile, delimiter=",")
    return np.array([float(x) for x in np.array(list(reader)).flatten()])

def parse(filename):
    """
    Parses a given filename to extract the user identifier and index.

    This function accepts a filename, processes it to derive the base name
    (by removing its extension), and splits the base name into components
    to extract the user identifier (the substring before the first '-'
    character) and index (the substring after the last 'n' character). The
    results are returned as a tuple.

    :param filename: The full path of the file to be parsed, given as a string.
    :return: A tuple containing two elements:
        - The user identifier as a string.
        - The index as a string.
    """
    base = Path(filename).stem
    user = base.split('-')[0]
    index = base.split('n')[1]
    return (user, index)

def process(leftfilename, rightfilename):
    """
    Processes two files containing data, computes the root mean square error (RMSE)
    between the corresponding loaded data, and returns various metadata and error metrics.

    This function takes in two filenames, parses their content to extract metadata,
    loads their data, computes the RMSE between the loaded data, and returns a list
    containing metadata and the computed error. It is used in applications that require
    comparison or validation of data between two sources.

    :param str leftfilename: The filename containing the left-hand side data to be processed.
    :param str rightfilename: The filename containing the right-hand side data to be processed.
    :return: A list containing the parsed left user data, left index, right user data,
             right index, and the computed RMSE between the loaded left and right data.
    :rtype: list
    """
    (leftuser, leftindex) = parse(leftfilename)
    (rightuser, rightindex) = parse(rightfilename)
    left = load(leftfilename)
    right = load(rightfilename)
    error = rmse(left, right)

    return [leftuser, leftindex, rightuser, rightindex, error]


users=os.listdir(sys.argv[1])
mfccs = glob.glob(f"mfccs/*.csv")

writer = csv.writer(open("results/results.csv", "w"))
writers = {}
for leftfilename in mfccs:
    for rightfilename in mfccs:
        result = process(leftfilename, rightfilename)
        writer.writerow(result)

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
