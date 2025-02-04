USERS_DIR="audio/tests"
RESULTS_FILE="results/testing.csv"
START_INDEX=18
MAX_FILES=1

python3 automfcc.py $USERS_DIR $RESULTS_FILE $START_INDEX $MAX_FILES
