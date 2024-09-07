import os

import librosa.display
import matplotlib.pyplot as plt
import numpy as np

from constants import chartDirectory, imageFileExtension

# create and save MFCC charts for all the audio files in a given directory
def createMfccsFrom(directory: str):
    for filename in os.listdir(directory):
        # Create file path
        filePath = os.path.join(directory, filename)

        # Make sure it's a wav file
        if os.path.isfile(filePath) and filename.lower().endswith('.wav'):
            # Remove the extension from the filename
            chartName = os.path.splitext(filename)[0]
            createMfccFrom(filePath, chartName)

def createMfccFrom(audioFile: str, chartName: str):
    chartType = "MFCC"
    chartName = chartName + chartType

    # load audio files with librosa
    signal, sr = librosa.load(audioFile)

    ## Extracting MFCCs
    mfccs = librosa.feature.mfcc(y=signal, n_mfcc=13, sr=sr)

    ## Visualising MFCCs
    plt.figure(figsize=(25, 10))
    librosa.display.specshow(mfccs,
                             x_axis="time",
                             sr=sr)
    plt.colorbar(format="%+2.f")

    ## Computing first / second MFCCs derivatives
    delta_mfccs = librosa.feature.delta(mfccs)
    delta2_mfccs = librosa.feature.delta(mfccs, order=2)
    plt.figure(figsize=(25, 10))
    librosa.display.specshow(delta_mfccs,
                             x_axis="time",
                             sr=sr)
    plt.colorbar(format="%+2.f")

    figure = plt.figure(figsize=(25, 10))

    # Adds a title to the top of the chart
    figure.suptitle(chartName)

    librosa.display.specshow(delta2_mfccs,
                             x_axis="time",
                             sr=sr)
    plt.colorbar(format="%+2.f")

    mfccs_features = np.concatenate((mfccs, delta_mfccs, delta2_mfccs))

    #  Save the chart as a png (this must be done before calling .show() or only a blank image will be saved)
    plt.savefig(chartDirectory + chartName + imageFileExtension)