filename="$1"
basename="${filename%.*}"
maxtime=$2

sox "${filename}" -c 1 "${basename}_%03n.wav" trim 0 ${maxtime} : newfile : restart
