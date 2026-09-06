"""Where the pipeline finds the repository's data files and keeps its download cache.

Run from the source tree, ROOT is the repository and the cache is `data_raw/`. Frozen into the
tile-service sidecar (PyInstaller, tools/service/build.sh) the bundled template pack, parcel rules
and core strings sit under `sys._MEIPASS`, which is read-only, so the cache moves to the directory
named by the VAKURAAMAT_RAW_DIR environment variable (the game passes its user directory).
"""
import os, sys

FROZEN = getattr(sys, "frozen", False)
ROOT = getattr(sys, "_MEIPASS", None) if FROZEN else os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def raw_root():
    """The download cache directory (created)."""
    d = os.environ.get("VAKURAAMAT_RAW_DIR") or os.path.join(ROOT, "data_raw")
    os.makedirs(d, exist_ok=True)
    return d


def raw(*sub):
    """A subdirectory of the download cache (created)."""
    d = os.path.join(raw_root(), *sub)
    os.makedirs(d, exist_ok=True)
    return d
