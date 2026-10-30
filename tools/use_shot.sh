#!/usr/bin/env bash
# Render the press-E prompt frames of a converted map under Xvfb: the eye on a button, then after the press.
#
#   heavy -- tools/use_shot.sh <out prefix> [--world=<prefix>] [--button=<index>]
#
# Not --headless: that driver draws nothing and saves a black PNG. Mesa's llvmpipe stands in for a GPU.
# A world outside this repo cannot be routed to the GPU boxes: prefix GPU_OFFLOAD=0 to render here.
set -uo pipefail
cd "$(dirname "$0")/.."
command -v Xvfb >/dev/null || { echo "Xvfb not installed" >&2; exit 3; }
[ $# -ge 1 ] || { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
OUT="$1"; shift
mkdir -p "$(dirname "$OUT")"
godot --headless --path . --import >/dev/null 2>&1
disp=$((90 + RANDOM % 8)); export DISPLAY=":$disp" LIBGL_ALWAYS_SOFTWARE=1
Xvfb ":$disp" -screen 0 1280x720x24 >/dev/null 2>&1 &
xpid=$!
sleep 2
timeout 150 godot --path . --resolution 1280x720 --rendering-method gl_compatibility --rendering-driver opengl3 res://examples/use_shot.tscn -- --out="$OUT" "$@"
rc=$?
kill $xpid 2>/dev/null
exit $rc
