USERS_DIR="audio/tests"
RESULTS_FILE="results/evaluation.csv"
START_INDEX=10
MAX_FILES=1

python3 automfcc.py $USERS_DIR $RESULTS_FILE $START_INDEX $MAX_FILES
head -n 2 $RESULTS_FILE > "results/one_speaker.csv"