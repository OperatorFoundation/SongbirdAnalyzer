maxtime=15

./split.sh $1/21525/21525-01.mp3 ${maxtime}
./split.sh $1/23723/23723-01.mp3 ${maxtime}
./split.sh $1/19839/19839-01.mp3 ${maxtime}

python3 clean.py $1
