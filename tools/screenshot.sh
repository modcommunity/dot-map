#!/usr/bin/env bash
# Render one frame of a converted map (free textures, environment, stand-in props) under Xvfb.
#
#   heavy -- tools/screenshot.sh <world prefix, without .json> <out.png> [--cam=x,y,z --look=x,y,z]
#
# Not --headless: that driver draws nothing and saves a black PNG. Mesa's llvmpipe stands in for a GPU.
set -uo pipefail
cd "$(dirname "$0")/.."
command -v Xvfb >/dev/null || { echo "Xvfb not installed" >&2; exit 3; }
[ $# -ge 2 ] || { sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
WORLD="$(realpath "$1")"; OUT="$(realpath -m "$2")"; shift 2
mkdir -p "$(dirname "$OUT")"
godot --headless --path . --import >/dev/null 2>&1
disp=$((90 + RANDOM % 8)); export DISPLAY=":$disp" LIBGL_ALWAYS_SOFTWARE=1
Xvfb ":$disp" -screen 0 1280x720x24 >/dev/null 2>&1 &
xpid=$!
sleep 2
timeout 150 godot --path . --resolution 1280x720 --rendering-method gl_compatibility --rendering-driver opengl3 res://examples/bsp_world_shot.tscn -- --world="$WORLD" --out="$OUT" "$@"
rc=$?
kill $xpid 2>/dev/null
exit $rc
