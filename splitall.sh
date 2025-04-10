# Maximum time in seconds for each audio segment
MAX_TIME=15
SPEAKER_DIR="$1"
WORKING_DIR="$2"


for SPEAKER_ID in 21525 23723 19839; do
  # Create an output directory for each SPEAKER_ID
  mkdir -p "${WORKING_DIR}/$SPEAKER_ID"

  # Check if input directory exists
  if [! -d "${SPEAKER_DIR}/$SPEAKER_ID" ]; then
    echo "Warning: Directory ${SPEAKER_DIR}/$SPEAKER_ID does not exist. Skipping..."
    continue
  fi

  # Process all mp3 files for the current SPEAKER_ID
  MP3_COUNT=0

  for FILE in "${SPEAKER_DIR}/$SPEAKER_ID"/*.mp3; do
    if [ -f "$FILE" ]; then
      ./split.sh "$FILE" ${MAX_TIME} "${WORKING_DIR}/$SPEAKER_ID"
      MP3_COUNT=$((MP3_COUNT + 1))
    fi
  done

  if [ $MP3_COUNT -eq 0 ]; then
    echo "No MP3 files found for speaker ID ${SPEAKER_ID}"
  else
    echo "Processed ${MP3_COUNT} files for speaker ID ${SPEAKER_ID}"
  fi

  # python3 clean.py ${WORKING_DIR}/$SPEAKER_ID
done
