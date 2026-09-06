#!/bin/sh
# Build the tile-service sidecar: one executable (PyInstaller) with the pipeline, rasterio, pyogrio,
# shapely and pyproj, the template pack and the rules. Output: dist/tile_service[.exe].
#   tools/service/build.sh            # uses .venv-service (created with uv or venv + requirements.txt)
set -e
cd "$(dirname "$0")/../.."
PY="${PYTHON:-.venv-service/bin/python}"
if [ ! -x "$PY" ]; then
  if command -v uv >/dev/null 2>&1; then
    uv venv .venv-service --python 3.12 -q && uv pip install -p .venv-service/bin/python -q -r tools/service/requirements.txt
  else
    python3 -m venv .venv-service && .venv-service/bin/pip install -q -r tools/service/requirements.txt
  fi
fi
"$PY" -m PyInstaller --clean --noconfirm --distpath dist --workpath build/pyinstaller tools/service/tile_service.spec
ls -la dist/tile_service*
