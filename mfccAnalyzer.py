import os
from random import sample

import librosa.display
import matplotlib.pyplot as plt
import numpy as np

from constants import chartDirectory, imageFileExtension

# create and save MFCC charts for all the audio files in a given directory
def create_mfcc_charts_from(directory: str):
    for filename in os.listdir(directory):
        # Create file path
        filePath = os.path.join(directory, filename)

        # Make sure it's a wav file
        if os.path.isfile(filePath) and filename.lower().endswith('.wav'):
            # Remove the extension from the filename
            chartName = os.path.splitext(filename)[0]
            create_mfcc_chart_from(filePath, chartName)

def extract_mfcc_from(audioFile: str):
    audio, sample_rate = librosa.load(audioFile)
    mfcc = librosa.feature.mfcc(y=audio, sr=sample_rate, n_mfcc=13)
    return mfcc, sample_rate


def create_mfcc_chart_from(audioFile: str, chartName: str):
    chartType = "MFCC" # This is only used for filenames
    chartName = chartName + chartType

    ## Extracting MFCCs
    mfcc, sample_rate = extract_mfcc_from(audioFile)

    ## Visualising MFCCs
    plt.figure(figsize=(25, 10))
    librosa.display.specshow(mfcc,
                             x_axis="time",
                             sr=sample_rate)
    plt.colorbar(format="%+2.f")

    ## Computing first / second MFCCs derivatives

    # TODO: Try calculating without the deltas for a smaller dataset
    delta_mfcc = librosa.feature.delta(mfcc)
    delta2_mfcc = librosa.feature.delta(mfcc, order=2)
    plt.figure(figsize=(25, 10))
    librosa.display.specshow(delta_mfcc,
                             x_axis="time",
                             sr=sample_rate)
    plt.colorbar(format="%+2.f")

    figure = plt.figure(figsize=(25, 10))

    # Adds a title to the top of the chart
    figure.suptitle(chartName)

    librosa.display.specshow(delta2_mfcc,
                             x_axis="time",
                             sr=sample_rate)
    plt.colorbar(format="%+2.f")

    mfcc_features = np.concatenate((mfcc, delta_mfcc, delta2_mfcc))

    # # Save the DataFrame to an Excel file
    # tableFilePath = tablesDirectory + filename + ".xlsx"
    # dataframe.to_excel(tableFilePath, index=False)

    # tableFilePath = tablesDirectory + filename + ".csv"
    # dataframe.to_csv(tableFilePath, index=False, header=True)

    #  Save the chart as a png (this must be done before calling .show() or only a blank image will be saved)
    plt.savefig(chartDirectory + chartName + imageFileExtension)
