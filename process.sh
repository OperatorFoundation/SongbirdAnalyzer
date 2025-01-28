USERS_DIR=os.listdir("audio/Tests")

./splitall.sh

python3 automfcc.py $USERS_DIR
python3 classify.py $USERS_DIR
python3 merge.py $USERS_DIR

