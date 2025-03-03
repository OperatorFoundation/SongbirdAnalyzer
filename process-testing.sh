USERS_DIR="audio/tests"
RESULTS_FILE="results/tests.csv"
WORKING_DIR="working-tests"
MODEL_FILE="songbird.pkl"

# Make sure we have directories for our users
for user in 21525 23723 19839; do
  mkdir -p $USERS_DIR/$user
  done

pushd $USERS_DIR/21525
wget -nc https://www.archive.org/download/diary_of_nobody_librivox/diary_of_nobody_librivox_64kb_mp3.zip
unzip -u *.zip
popd

pushd $USERS_DIR/23723
wget -nc https://www.archive.org/download/andersenfairytalesvolume4_1402_librivox/andersenfairytalesvolume4_1402_librivox_64kb_mp3.zip
unzip -u *.zip
popd

pushd $USERS_DIR/19839
wget -nc https://www.archive.org/download/princess_of_mars_librivox/princess_of_mars_librivox_64kb_mp3.zip
unzip -u *.zip
popd

./splitall.sh $USERS_DIR $WORKING_DIR
python3 automfcc.py $WORKING_DIR $RESULTS_FILE
python3 predict.py $RESULTS_FILE $MODEL_FILE
