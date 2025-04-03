import os
import sys
import glob

path = sys.argv[1]

# Removes any audio files that are not the standardized size
#for user in os.listdir(path):
#    for wav in glob.glob(f'{path}/{user}/*.wav'):
#        if os.path.getsize(wav) < 1323044:
#            os.remove(wav)
