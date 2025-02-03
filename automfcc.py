import csv
import glob
from operator import truediv

import librosa.feature
import librosa.display
import matplotlib.pyplot as plt
import os.path
from pathlib import Path
import sys

users = os.listdir(sys.argv[1])
resultsFile = open(sys.argv[2], "w")
start_index = int(sys.argv[3])
max_files = int(sys.argv[4])
csvout = csv.writer(resultsFile, delimiter=',')
first_row = True

for user in users:
    print(f"Processing user {user}")
    wavs = glob.glob(f"audio/Tests/{user}/*.wav")

    # Limit to the first x wav files
    for index in range(start_index, start_index + max_files):
        wav = wavs[index]
        print(f"{wav}...")
        audio_file = wav
        signal, sr = librosa.load(audio_file)

        mfccs_seq = librosa.feature.mfcc(y=signal, n_mfcc=12, sr=sr)
        mfccs = list(mfccs_seq[0])

        delta_mfccs_seq = librosa.feature.delta(mfccs_seq)
        delta_mfccs = list(delta_mfccs_seq[0])

        delta2_mfccs_seq = librosa.feature.delta(mfccs_seq, order=2)
        delta2_mfccs = list(delta2_mfccs_seq[0])

        plt.figure(figsize=(25, 10))
        librosa.display.specshow(mfccs_seq,
                                 x_axis="time",
                                 sr=sr)
        plt.colorbar(format="%+2.f")
        plt.savefig("images/"+Path(audio_file).stem+"1.png")
        plt.close()

        plt.figure(figsize=(25, 10))
        librosa.display.specshow(delta_mfccs_seq,
                                 x_axis="time",
                                 sr=sr)
        plt.colorbar(format="%+2.f")
        plt.savefig("images/"+Path(audio_file).stem+"2.png")
        plt.close()

        plt.figure(figsize=(25, 10))
        librosa.display.specshow(delta2_mfccs_seq,
                                 x_axis="time",
                                 sr=sr)
        plt.colorbar(format="%+2.f")
        plt.savefig("images/"+Path(audio_file).stem+"3.png")
        plt.close()

        if first_row:
            header = ["speaker"] + [f"MFCC_{i + 1}" for i in range(len(mfccs))] + [f"Delta_{i + 1}" for i in range(len(delta_mfccs))] + [f"Delta2_{i + 1}" for i in range(len(delta2_mfccs))]
            csvout.writerow(header)
            first_row = False

        csvout.writerow([user] + mfccs + delta_mfccs + delta2_mfccs)


resultsFile.close()
