USERS_DIR=os.listdir("audio/Tests")

./splitall.sh

python3 automfcc.py
python3 classify.py
python3 merge.py

