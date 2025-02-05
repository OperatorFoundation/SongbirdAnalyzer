== Install

brew install sox
mkdir images
mkdir results
mkdir mfccs

# Providing audio data

Audio data goes in folders in audio/Tests/ where each folder is the userid of the speaker

== Running

./process-training.sh

This will print a model accuracy evaluation. After each run, provide more audio
data or tweak the MFCC generation algorithm to try to increase the accuracy of
the model.
