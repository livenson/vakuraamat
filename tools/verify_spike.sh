#!/usr/bin/env bash
# Phase 0 acceptance check: rebuilds nothing, just launches the spike scene with a
# real window, lets it warm up for ~120 frames, saves a screenshot, prints the
# average FPS and the ground height under the player, then quits.
#
#   tools/verify_spike.sh [output.png] [frames]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${1:-$PWD/data_raw/spike_screenshot.png}"
FRAMES="${2:-120}"
mkdir -p "$(dirname "$OUT")"
"$GODOT" --path . --resolution 1600x900 -- --screenshot="$OUT" --frames="$FRAMES" 2>&1 \
  | grep -E "^\[spike\]|ERROR|SCRIPT ERROR" || true
echo "screenshot: $OUT"
