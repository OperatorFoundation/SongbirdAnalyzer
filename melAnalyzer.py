import os

import librosa.display
import matplotlib.pyplot as plt

from constants import chartDirectory, imageFileExtension

# create and save Mel charts for all of the audio files in a given directory
def createMelsFrom(directory: str):
    for filename in os.listdir(directory):
        # Create file path
        filePath = os.path.join(directory, filename)

        # Make sure it's a wav file
        if os.path.isfile(filePath) and filename.lower().endswith('.wav'):
            print(f"Creating Mel from file: {filePath}")

            # Remove the extension from the filename
            chartName = os.path.splitext(filename)[0]
            createMelFrom(filePath, chartName)

def createMelFrom(audioFile: str, chartName: str):
    chartType = "Mel"
    chartName = chartName + chartType
    # load audio files with librosa
    scale, sr = librosa.load(audioFile)

    mel_spectrogram = librosa.feature.melspectrogram(y=scale, sr=sr, n_fft=2048, hop_length=512, n_mels=10)
    log_mel_spectrogram = librosa.power_to_db(mel_spectrogram)
    figure = plt.figure(figsize=(25, 10))

    # Adds a title to the top of the chart
    figure.suptitle(chartName)

    librosa.display.specshow(log_mel_spectrogram,
                             x_axis="time",
                             y_axis="mel",
                             sr=sr)
    plt.colorbar(format="%+2.f")

    #  Save the chart as a png (this must be done before calling .show() or only a blank image will be saved)
    plt.savefig(chartDirectory + chartName + imageFileExtension)