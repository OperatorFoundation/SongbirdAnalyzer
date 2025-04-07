USERS_DIR="audio/training"
RESULTS_FILE="results/training.csv"
WORKING_DIR="working-training"
MODEL_FILE="songbird.pkl"
TEST_DATA="results/testing"

# Make sure we have directories for our users
for user in 21525 23723 19839; do
  mkdir -p $USERS_DIR/$user
  done

pushd $USERS_DIR/21525
wget -nc https://www.archive.org/download/man_who_knew_librivox/man_who_knew_librivox_64kb_mp3.zip
for zip in *.zip; do
  unzip -u "$zip"
done
popd

pushd $USERS_DIR/23723
wget -nc https://www.archive.org/download/man_thursday_zach_librivox/man_thursday_zach_librivox_64kb_mp3.zip
for zip in *.zip; do
  unzip -u "$zip"
done
popd

pushd $USERS_DIR/19839
wget -nc https://www.archive.org/download/emma_solo_librivox/emma_solo_librivox_64kb_mp3.zip
for zip in *.zip; do
  unzip -u "$zip"
done
rm emma_01_04_austen_64kb.mp3 # guest reader
rm emma_02_11_austen_64kb.mp3 # guest reader
popd

./splitall.sh $USERS_DIR $WORKING_DIR
python3 automfcc.py $WORKING_DIR $RESULTS_FILE
python3 train.py $RESULTS_FILE $TEST_DATA $MODEL_FILE


