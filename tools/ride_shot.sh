#!/usr/bin/env bash
# Render a body riding (or shoved by) a converted map mover under Xvfb, then tile the frames into one strip.
#
#   heavy -- tools/ride_shot.sh <world prefix, without .json> <out prefix> --entity=<index> --scenario=ride|push
#
# Not --headless: that driver draws nothing and saves a black PNG. Mesa's llvmpipe stands in for a GPU.
# A world outside this repo cannot be routed to the GPU boxes: prefix GPU_OFFLOAD=0 to render here.
set -uo pipefail
cd "$(dirname "$0")/.."
command -v Xvfb >/dev/null || { echo "Xvfb not installed" >&2; exit 3; }
[ $# -ge 2 ] || { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
WORLD="$(realpath -m "$1")"; OUT="$(realpath -m "$2")"; shift 2
mkdir -p "$(dirname "$OUT")"
godot --headless --path . --import >/dev/null 2>&1
disp=$((90 + RANDOM % 8)); export DISPLAY=":$disp" LIBGL_ALWAYS_SOFTWARE=1
Xvfb ":$disp" -screen 0 1280x720x24 >/dev/null 2>&1 &
xpid=$!
sleep 2
timeout 150 godot --path . --resolution 1280x720 --rendering-method gl_compatibility --rendering-driver opengl3 res://examples/ride_shot.tscn -- --world="$WORLD" --out="$OUT" "$@"
rc=$?
for sc in ride push; do
  rm -f "${OUT}_${sc}_strip.png"
  ls "${OUT}"_${sc}_*.png >/dev/null 2>&1 && ffmpeg -y -loglevel error -pattern_type glob -framerate 1 -i "${OUT}_${sc}_*.png" -vf "scale=640:-1,tile=4x2" -frames:v 1 "${OUT}_${sc}_strip.png"
done
kill $xpid 2>/dev/null
exit $rc
