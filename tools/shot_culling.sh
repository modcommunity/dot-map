#!/usr/bin/env bash
# Draw calls and a frame each for no occluders, the baked occluders, and the occluders with every door shut (examples/culling_demo.gd).
#
#   ../gpu.sh shot --pull <out dir> dot-map tools/shot_culling.sh --shot=<out dir>
set -euo pipefail
cd "$(dirname "$0")/.."
exec xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --path . --resolution 960x540 \
    res://examples/culling_demo.tscn -- "$@"
