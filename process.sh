USERS_DIR=os.listdir("audio/Tests")

./splitall.sh $USERS_DIR

python3 automfcc.py $USERS_DIR
python3 collate.py $USERS_DIR
