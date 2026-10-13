#!/usr/bin/env bash
# Joins rendered segments into the submission cut with crossfades (like the single-take edit of the
# designer demo, which hides its one cut behind a dissolve), fading in from and out to black.
# usage: tools/compose.sh OUT.mp4 SEG1.mp4 SEG2.mp4 [SEG3.mp4 …]
set -euo pipefail
out=$1; shift
xf=0.6
inputs=()
durs=()
for f in "$@"; do
  inputs+=(-i "$f")
  durs+=("$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")")
done
n=$#
if [ "$n" -eq 1 ]; then
  total=${durs[0]}
  chain="[0:v]fade=t=in:st=0:d=0.4,fade=t=out:st=$(echo "$total - 0.6" | bc -l):d=0.6,format=yuv420p,setparams=range=tv:colorspace=bt709:color_primaries=bt709:color_trc=bt709[v]"
else
  chain=""
  prev="[0:v]"
  acc=${durs[0]}
  for ((i = 1; i < n; i++)); do
    offset=$(echo "$acc - $xf" | bc -l)
    chain+="${prev}[$i:v]xfade=transition=fade:duration=$xf:offset=$offset[x$i];"
    prev="[x$i]"
    acc=$(echo "$acc + ${durs[$i]} - $xf" | bc -l)
  done
  total=$acc
  chain+="${prev}fade=t=in:st=0:d=0.4,fade=t=out:st=$(echo "$total - 0.6" | bc -l):d=0.6,format=yuv420p,setparams=range=tv:colorspace=bt709:color_primaries=bt709:color_trc=bt709[v]"
fi
ffmpeg -y -loglevel error "${inputs[@]}" -filter_complex "$chain" -map "[v]" \
  -c:v libx264 -preset slow -crf 16 -profile:v high -r 60 -movflags +faststart -threads 1 "$out"
echo "saved $out ($(printf '%.1f' "$total") s)"
