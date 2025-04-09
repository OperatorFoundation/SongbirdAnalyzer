
: <<'END_COMMENT'
###############################################################
#                                                             #
#  ██████  IMPORTANT: DEVICE DEPENDANT OPERATION              #
#  █       This script should only be run while               #
#  █       a songbird device is plugged in to your computer   #
#  ██████  and in development mode.                           #
#                                                             #
###############################################################
END_COMMENT

maxtime=10

USERS_DIR="audio/training"
RESULTS_FILE="results/evaluation.csv"
FILES_DIR="working-training"
WORKING_DIR="working-evaluation"
MODEL_FILE="songbird.pkl"
DEVICE_NAME="Teensy MIDI_Audio" # The device name as it appears on macOS

find_teensy_device() {
  # List all usb devices and grep for Teensy
  local device_list=$(ioreg -p IOUSB -l -w 0 | grep -i teensy -A10 | grep "IODialinDevice" | sed -e 's/.*= "//' -e 's/".*//')

  # if no device is found using ioreg, fall back to looking in /dev
  if [ -z "$device_list" ]; then
    # Try to find a likely Teensy usb modem device
    device_list=$(ls /dev/cu.usbmodem* 2>/dev/null)
  fi

  # Return the first device found or empty
  echo "$device_list" | head -n1
}

#device="/dev/cu.usbmodem159429201" # FIXME: Do not hard code devices
device=$(find_teensy_device)

# check if the device was found
if [ -z "$device" ]; then
  echo "⚠️ ERROR: Could not find a Teensy device. Is it connected?"
  exit 1
else
  echo "Found Teensy device at: $device"
fi

# Configure serial communication settings
# 115200 - Set baud rate to 115200 bps
# cs8    - 8 data bits
# -cstopb - 1 stop bit (disable 2 stop bits)
# -parenb - No parity bit
stty -f $device 115200 cs8 -cstopb -parenb

# Check if SwitchAudioSource is installed
if ! command -v SwitchAudioSource &>/dev/null; then
  echo "ERROR: SwitchAudioSource not found. Install it with: brew install switchaudio-osx"
  exit 1
fi

check_audio_device()
{
  # Returns true (0) if device exists, false (1) otherwise
  SwitchAudioSource -a | grep -q "$DEVICE_NAME"
  return $?
}

# Check If Audio Device Exists
if ! check_audio_device; then
  echo "ERROR: Audio device '$DEVICE_DEVICE_NAME' not found."
  echo "Available audio devices: "
  SwitchAudioSource -a
  exit 1
fi

# Set Teensy as the audio input device
echo "Setting $DEVICE_NAME as audio input device"
SwitchAudioSource -t "input" -s "$DEVICE_NAME"

echo "Setting $DEVICE_NAME as audio output device..."
SwitchAudioSource -t "output" -s "$DEVICE_NAME"

# Verify that the settings were applied
echo "Current audio input device: $(SwitchAudioSource -c -t input)"
echo "Current audio output device: $(SwitchAudioSource -c -t output)"
echo "Teensy audio configuration complete!"

# Make sure we have directories for our users
for user in 21525 23723 19839; do
  mkdir -p $WORKING_DIR/$user # Make sure we have an evaluation directory for each user

  for file in $FILES_DIR/$user/*.wav; do

    for mode in n p w a; do # Play and record each file in each mode
      echo $mode > $device
      basename=$(basename "$file" ".wav")
      filename=$basename-$mode.wav
      afplay $file &
      echo "Recording for $maxtime seconds to $WORKING_DIR/$user/$filename..."
      rec $WORKING_DIR/$user/$filename trim 0 $maxtime
      echo "Recording complete"

    done
  done
done

python3 automfcc.py $WORKING_DIR $RESULTS_FILE
python3 evaluate.py $RESULTS_FILE
python3 predict.py $RESULTS_FILE $MODEL_FILE