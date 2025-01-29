import csv
import glob
import os
from pathlib import Path
import numpy as np
import sys

def load(mfccfilename):
    """
    Loads the MFCC data from a given CSV file and returns it as a NumPy array. The CSV file
    is expected to contain numeric data that represents the Mel-frequency cepstral coefficients
    (MFCCs). Each value in the file is read, converted to a float, and returned in a flattened
    array format, suitable for further processing or analysis.

    :param mfccfilename: The path to the CSV file containing MFCC data
    :type mfccfilename: str
    :return: A NumPy array containing the flattened MFCC data loaded from the file
    :rtype: numpy.ndarray
    """
    print(f"{mfccfilename}...")
    mfccfile = open(mfccfilename, "r")
    reader = csv.reader(mfccfile, delimiter=",")
    return np.array([float(x) for x in np.array(list(reader)).flatten()])

def parse(filename):
    """
    Parse the given filename to extract the user segment which is the portion
    before the first hyphen in the base name of the file.

    This function processes the input `filename`, retrieves its base name
    (excluding the extension), and extracts the user identifier segment by
    splitting the base name on the '-' character. It only returns the first
    portion of the split base name as the user identifier.

    :param filename:
        The full file name (including path and extension) to process.
    :type filename: str
    :return:
        The extracted user identifier segment from the base name.
    :rtype: str
    """
    base = Path(filename).stem
    user = base.split('-')[0]
    return user

def writeRow(filename, writer):
    """
    Write a row containing user data and corresponding MFCC data into a writer.

    This function takes a filename to parse user data and load extracted
    MFCC features. It then combines the user data and MFCC features into
    a single list and writes it as a row using the provided writer object.

    :param filename: Path to the file containing user and MFCC data.
    :type filename: str
    :param writer: A writer object, such as a CSV writer, used for writing
        rows.
    :type writer: csv.writer or similar
    :return: None
    """
    user = parse(filename)
    mfccData = load(filename)
    result = [user] + list(mfccData)
    writer.writerow(result)

users = os.listdir(sys.argv[1])
mfccs = glob.glob(f"{sys.argv[2]}/*.csv")
resultsFile = open(sys.argv[3], "w")

writer = csv.writer(resultsFile)

# Write the header row
# The first column is the speaker and the rest are MFCC features

# Check an example file to see how many rows there will be
mfcc_example = np.loadtxt(mfccs[0], delimiter=',').flatten()

header = ["speaker"] + [f"MFCC_{i + 1}" for i in range(len(mfcc_example))]
writer.writerow(header)

for filename in mfccs:
    writeRow(filename, writer)

resultsFile.close()
