import os

import librosa
import librosa.display
import matplotlib.pyplot as plt
import numpy as np

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
    wave_form, sample_rate = librosa.load(audioFile)


    window_size = 2048 # the number of samples in each frame
    hop_length = 512 # the number of samples between successive frames
    number_of_mels = 10 # the number of Mel bands to generate
    mel_spectrogram = librosa.feature.melspectrogram(y=wave_form, sr=sample_rate, n_fft=window_size, hop_length=hop_length, n_mels=number_of_mels)
    mel_spectrogram_db = librosa.power_to_db(mel_spectrogram, ref=np.max)
    figure = plt.figure(figsize=(25, 10))

    # Adds a title to the top of the chart
    figure.suptitle(chartName)

    librosa.display.specshow(mel_spectrogram_db,
                             x_axis="time",
                             y_axis="mel",
                             sr=sample_rate)
    plt.colorbar(format="%+2.0f dB")
    plt.title('Mel Spectrogram')
    plt.tight_layout()

    #  Save the chart as a png (this must be done before calling .show() or only a blank image will be saved)
    plt.savefig(chartDirectory + chartName + imageFileExtension)