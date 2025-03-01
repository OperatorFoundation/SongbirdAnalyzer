maxtime=15

for user in 21525 23723 19839; do
  mkdir -p working/$user

  for file in $1/$user/*.mp3; do
    ./split.sh $file ${maxtime} $2/$user
  done

  python3 clean.py $2/$user
done
