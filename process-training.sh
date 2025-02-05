USERS_DIR="audio/tests"
RESULTS_FILE="results/training.csv"

./splitall.sh $USERS_DIR
python3 automfcc.py $USERS_DIR $RESULTS_FILE
python3 predict.py
