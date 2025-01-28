USERS_DIR="audio/tests"
OUTPUT_DIR="mfccs/testing"
RESULTS_FILE="results/testing.csv"

mkdir -p $OUTPUT_DIR
python3 automfcc.py $USERS_DIR $OUTPUT_DIR
python3 collate.py $USERS_DIR $OUTPUT_DIR $RESULTS_FILE
