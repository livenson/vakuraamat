#!/bin/sh
# Start everything the game needs and the game itself: the tile service (world generation from
# national data, port 8765) and the world service (shared worlds, port 8766) if they are not
# running, then Godot. Extra arguments go to the game after "--" (e.g. --site=kvissentali,
# --windowed). Service logs: <user dir>/logs/tile_service.log and world_service.log.
# The game also starts the services itself when run from the source tree; this script is the
# one-command way and keeps their logs in files.
set -e
cd "$(dirname "$0")/.."
case "$(uname)" in
  Darwin) U="$HOME/Library/Application Support/Godot/app_userdata/Vakuraamat" ;;
  *) U="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Vakuraamat" ;;
esac
mkdir -p "$U/logs"
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"

start_service() {  # name port script
  if curl -fs "http://127.0.0.1:$2/health" >/dev/null 2>&1; then
    echo "$1 already running on $2"
    return
  fi
  nohup python3 "$3" --port "$2" >>"$U/logs/$1.log" 2>&1 &
  echo "$1 started (pid $!, log $U/logs/$1.log)"
  i=0
  while ! curl -fs "http://127.0.0.1:$2/health" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -gt 30 ]; then echo "$1 did not answer on port $2; see the log" >&2; break; fi
    sleep 0.5
  done
}

start_service tile_service 8765 tools/tile_service.py
start_service world_service 8766 tools/world_service.py
exec "$GODOT" --path . -- "$@"
