filename="$1"
basename="${filename%.*}"

sox "${filename}" -c 1 "${basename}_%03n.wav" trim 0 10 : newfile : restart
