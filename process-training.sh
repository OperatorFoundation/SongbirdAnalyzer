USERS_DIR="audio/training"
RESULTS_FILE="results/training.csv"
WORKING_DIR="working-training"
MODEL_FILE="songbird.pkl"

for user in 21525 23723 19839; do
  mkdir -p USERS_DIR/$user
  done

pushd $USERS_DIR/21525
wget -nc https://www.archive.org/download/man_who_knew_librivox/man_who_knew_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/anthem_doomed_youth_owen_librivox/anthem_doomed_youth_owen_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/art_and_heart_librivox/art_and_heart_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/psalms_selections_librivox/psalms_selections_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/crome_yellow_librivox/crome_yellow_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/death_be_not_proud_librivox/death_be_not_proud_librivox_64kb_mp3.zip
unzip -u *.zip
popd

pushd $USERS_DIR/23723
wget -nc https://www.archive.org/download/man_thursday_zach_librivox/man_thursday_zach_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/adventures_holmes/adventures_holmes_64kb_mp3.zip
wget -nc https://www.archive.org/download/astounding_stories_06_1403_librivox/astounding_stories_06_1403_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/astounding_stories_08_1403_librivox/astounding_stories_08_1403_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/atlanticnarratives2_1502_librivox/atlanticnarratives2_1502_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/beautiful_soup_librivox/beautiful_soup_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/aboriginal_canada/aboriginal_canada_64kb_mp3.zip
wget -nc https://www.archive.org/download/dannys_own_story_1408_librivox/dannys_own_story_1408_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/don_quixote_vol1_librivox/don_quixote_vol1_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/dream_play_1403_librivox/dream_play_1403_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/drinking_alone_librivox/drinking_alone_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/faith_of_men_0707_librivox/faith_of_men_0707_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/favourite_chapters_collection_002_librivox/favourite_chapters_collection_002_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/federalist_papers_librivox/federalist_papers_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/fire_and_ice_librivox/fire_and_ice_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/greenmantle_0709_librivox/greenmantle_0709_librivox_64kb_mp3.zip
unzip -u *.zip
popd

pushd $USERS_DIR/19839
wget -nc https://www.archive.org/download/emma_solo_librivox/emma_solo_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/adventures_pinocchio_librivox/adventures_pinocchio_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/anne_of_green_gables_librivox/anne_of_green_gables_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/potter_treasury_librivox/potter_treasury_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/grimms_english_librivox/grimms_english_librivox_64kb_mp3.zip
wget -nc https://www.archive.org/download/pride_and_prejudice_librivox/pride_and_prejudice_librivox_64kb_mp3.zip
unzip -u *.zip
rm emma_01_04_austen_64kb.mp3 # guest reader
rm emma_02_11_austen_64kb.mp3 # guest reader
popd

./splitall.sh $USERS_DIR $WORKING_DIR
python3 automfcc.py $WORKING_DIR $RESULTS_FILE
python3 train.py $RESULTS_FILE $MODEL_FILE