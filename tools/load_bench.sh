#!/usr/bin/env bash
# Load time of a converted world with 0, 1, 2 and 4 workers, three runs each: tools/load_bench.sh <world dir>/<name>
for w in 0 1 2 4; do
	for r in 1 2 3; do
		echo "== workers $w run $r"
		heavy -- timeout 200 godot --headless --path "$(dirname "$0")/.." --script tools/load_bench.gd -- "$1" $w 2>&1 | grep -E "ms |DIGEST|ERROR"
	done
done
