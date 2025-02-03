USERS_DIR="audio/tests"
RESULTS_FILE="results/training.csv"
START_INDEX=0
MAX_FILES=10

#./splitall.sh $USERS_DIR
python3 automfcc.py $USERS_DIR $RESULTS_FILE $START_INDEX $MAX_FILES
