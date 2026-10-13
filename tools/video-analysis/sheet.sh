#!/bin/bash
# usage: sheet.sh START DURATION OUTPREFIX [TILE=6x5] [SIZE=270] [STEP=1]
S=$1; D=$2; O=$3; T=${4:-6x5}; Z=${5:-270}; STEP=${6:-1}
ffmpeg -v error -ss "$S" -t "$D" -copyts -i /root/tgdesign/research/source/IMG_6025.MP4 \
  -vf "select='not(mod(n\,$STEP))',scale=$Z:$Z:flags=area,drawtext=text='%{pts\:flt}':x=4:y=4:fontsize=18:fontcolor=yellow:box=1:boxcolor=black@0.7,tile=$T:padding=2" \
  -fps_mode passthrough -q:v 3 "${O}_%d.jpg"
