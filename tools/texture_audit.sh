#!/usr/bin/env bash
# Where a converted map's texture memory goes, by category (builds the world under Xvfb, prints AUDIT rows).
#
#   heavy -- tools/texture_audit.sh <world prefix> [--cap=<px>] [--nomodels] [--half=0|1] [--fullnormals] [--fullmodelmasks] [--fullmodelnormals]
#
# Not --headless: that driver has no renderer to count. Mesa llvmpipe stands in for a GPU.
set -uo pipefail
cd "$(dirname "$0")/.."
command -v Xvfb >/dev/null || { echo "Xvfb not installed" >&2; exit 3; }
[ $# -ge 1 ] || { sed -n 2,4p "$0"; exit 2; }
WORLD="$(realpath -m "$1")"; shift 1
godot --headless --path . --import >/dev/null 2>&1
LIMIT=400
disp=$((90 + RANDOM % 8)); export DISPLAY=":$disp" LIBGL_ALWAYS_SOFTWARE=1
Xvfb ":$disp" -screen 0 1280x720x24 >/dev/null 2>&1 &
xpid=$!
sleep 2
timeout "$LIMIT" godot --path . --resolution 1280x720 --rendering-method gl_compatibility --rendering-driver opengl3 res://tools/texture_audit.tscn -- --world="$WORLD" "$@"
rc=$?
kill $xpid 2>/dev/null
exit $rc
