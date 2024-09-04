import csv
import glob
import librosa
import librosa.display
import matplotlib.pyplot as plt
import numpy as np
import os
import os.path
from pathlib import Path
import sys

users=os.listdir("audio")
for user in users:
    print(f"Processing user {user}")
    wavs = glob.glob(f"audio/{user}/*.wav")

    for wav in wavs:
        print(f"{wav}...")
        audio_file = wav
        signal, sr = librosa.load(audio_file)

        mfccs = librosa.feature.mfcc(y=signal, n_mfcc=13, sr=sr)

        plt.figure(figsize=(25, 10))
        librosa.display.specshow(mfccs,
                                 x_axis="time",
                                 sr=sr)
        plt.colorbar(format="%+2.f")
        plt.savefig("images/"+Path(audio_file).stem+"1.png")
        plt.close()

        delta_mfccs = librosa.feature.delta(mfccs)
        delta2_mfccs = librosa.feature.delta(mfccs, order=2)
        plt.figure(figsize=(25, 10))
        librosa.display.specshow(delta_mfccs,
                                 x_axis="time",
                                 sr=sr)
        plt.colorbar(format="%+2.f")
        plt.savefig("images/"+Path(audio_file).stem+"2.png")
        plt.close()

        plt.figure(figsize=(25, 10))
        librosa.display.specshow(delta2_mfccs,
                                 x_axis="time",
                                 sr=sr)
        plt.colorbar(format="%+2.f")
        plt.savefig("images/"+Path(audio_file).stem+"3.png")
        plt.close()

        mfccs_features = np.concatenate((mfccs, delta_mfccs, delta2_mfccs))

        output_file_name = "mfccs/"+Path(audio_file).stem+".csv"
        output_file = open(output_file_name, "w")
        csvout = csv.writer(output_file, delimiter=',')
        csvout.writerows(mfccs_features)
        output_file.close()