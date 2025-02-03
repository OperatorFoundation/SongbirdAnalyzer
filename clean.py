import glob
import os

# Removes any audio files that are not the standardized size
for user in os.listdir('audio'):
    for wav in glob.glob(f'audio/{user}/*.wav'):
        if os.path.getsize(wav) != 882044:
            os.remove(wav)