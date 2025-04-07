maxtime=15

USERS_DIR="audio/training"
RESULTS_FILE="results/evaluation.csv"
FILES_DIR="working-training" # TODO: This should be working-testing
WORKING_DIR="working-evaluation"
MODEL_FILE="songbird.pkl"
DEVICE_NAME="Teensy MIDI_Audio"


device="/dev/cu.usbmodem159429201" # FIXME: Get the first device from /dev with cu.modem* name
stty -f $device 115200 cs8 -cstopb -parenb

# Make sure we have directories for our users
#for user in 21525 23723 19839; do
#  mkdir -p $WORKING_DIR/$user # Make sure we have an evaluation directory for each user
#
#  for file in $FILES_DIR/$user/*.wav; do
#
#    for mode in n p w a; do # Play and record each file in each mode
#      echo $mode > $device
#      basename=$(basename "$file" ".wav")
#      filename=$basename-$mode.wav
#      SwitchAudioSource -t "input" -s "$DEVICE_NAME"
#      SwitchAudioSource -t "output" -s "$DEVICE_NAME"
#      afplay $file &
#      echo "Recording for $maxtime seconds to $WORKING_DIR/$user/$filename..."
#      rec $WORKING_DIR/$user/$filename trim 0 $maxtime
#      echo "Recording complete"
#
#    done
#  done
#done

python3 automfcc.py $WORKING_DIR $RESULTS_FILE
python3 evaluate.py $RESULTS_FILE
python3 predict.py $RESULTS_FILE $MODEL_FILE