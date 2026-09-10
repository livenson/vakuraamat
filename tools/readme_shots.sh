#!/usr/bin/env bash
# Retake the README screenshots (docs/screenshots/{menu,plots,street,shop,map,home}.jpg): 1280x720,
# Kvissentali at midday, the town filled in. Needs a window (not headless) and, for home.jpg, the
# network: the plot page fetches its historical orthophotos from Maa-amet on first use.
#   tools/readme_shots.sh            all six
#   tools/readme_shots.sh map shop   only these
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
OUT=docs/screenshots
TMP=$(mktemp -d)
SHOTS=${*:-menu plots street shop map home}

world() {   # name, then extra world flags
	local name=$1
	shift
	"$GODOT" --resolution 1280x720 --path . res://scenes/world/world.tscn -- --windowed --no-perf-log \
		--site=kvissentali --hour=12 --frames=900 --screenshot="$TMP/$name.png" "$@" >"$TMP/$name.log" 2>&1
}

for s in $SHOTS; do
	case $s in
		menu) "$GODOT" --resolution 1280x720 --path . res://tools/godot/menu_shot.tscn -- --windowed --no-perf-log \
			--site=kvissentali --out="$TMP/menu.png" >"$TMP/menu.log" 2>&1 ;;
		plots) world plots --open=book ;;
		street) world street --spawn=499,528,270 ;;                  # east along Kvissentali tee from the spawn
		shop) world shop "--enter=Pootsmani tn 24" --frames=1800 ;;  # Ankriset OÜ's building, from inside (after the fill)
		map) world map --open=map --layer=sector ;;
		home) world home "--open=plot:79501:002:0169#3" ;;           # Aeru tn 3 over the years
		*) echo "unknown shot: $s" >&2; exit 1 ;;
	esac
	if [ -s "$TMP/$s.png" ]; then
		sips -s format jpeg -s formatOptions 82 "$TMP/$s.png" --out "$OUT/$s.jpg" >/dev/null
		echo "$OUT/$s.jpg"
	else
		echo "no image for $s (log: $TMP/$s.log)" >&2
	fi
done
