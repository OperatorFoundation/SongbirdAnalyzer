import glob
import os

for user in os.listdir('audio'):
    for wav in glob.glob(f'audio/{user}/*.wav'):
        if os.path.getsize(wav) != 1323044:
            os.remove(wav)