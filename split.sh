filename="$1"
basename=`basename ${filename%.*}`
maxtime="$2"
output_dir="$3"

sox "${filename}" -c 1 "${output_dir}/${basename}_%03n.wav" trim 0 ${maxtime} : newfile : restart
