#!/usr/bin/env bash
# Draw calls, primitives, frame time and pixel diffs of DotMapVisibility modes on a real converted map (examples/vis_proof.gd).
#
#   ../gpu.sh shot --stage <world dir> --pull <out dir> dot-map tools/shot_vis_proof.sh --world=<prefix> --out=<out dir> [--spots=6 --diffs=24]
#
# Prints PROOF lines. Not a headless run (that driver draws nothing); the GPU boxes' xvfb-run shim picks Forward+ on the NVIDIA card.
set -euo pipefail
cd "$(dirname "$0")/.."
exec xvfb-run -a -s "-screen 0 1280x720x24" "${GODOT:-godot}" --path . --resolution 640x360 \
    res://examples/vis_proof.tscn -- "$@"
