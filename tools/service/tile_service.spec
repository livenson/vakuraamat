# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for the tile-service sidecar: tools/tile_service.py with the pipeline modules,
# the template pack (sites/palupera), the parcel rules and the core strings it reads.
#   pyinstaller --clean --noconfirm tools/service/tile_service.spec        (tools/service/build.sh)
import os
from PyInstaller.utils.hooks import collect_all

ROOT = os.path.abspath(os.path.join(SPECPATH, "..", ".."))
datas = [
    (os.path.join(ROOT, "sites", "palupera", "site.json"), "sites/palupera"),
    (os.path.join(ROOT, "sites", "palupera", "strings.csv"), "sites/palupera"),
    (os.path.join(ROOT, "sites", "palupera", "data", "structures"), "sites/palupera/data/structures"),
    (os.path.join(ROOT, "assets", "data", "parcel_rules.json"), "assets/data"),
    (os.path.join(ROOT, "assets", "i18n", "strings.csv"), "assets/i18n"),
]
binaries, hiddenimports = [], []
for pkg in ("rasterio", "pyogrio", "shapely", "pyproj"):
    d, b, h = collect_all(pkg)
    datas += d; binaries += b; hiddenimports += h

a = Analysis(
    [os.path.join(ROOT, "tools", "tile_service.py")],
    pathex=[os.path.join(ROOT, "tools"), os.path.join(ROOT, "tools", "pipeline")],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports + ["new_site", "gen_era_scenes", "extract_features", "fetch_buildings", "fetch_trees", "fetch_parcels",
                                   "fetch_roads", "fetch_stops", "fetch_tenants", "fetch_fields", "market", "fetch_tile", "news_feeder",
                                   "validate_site", "register_extra", "emtak", "geo", "paths", "sources"],
    hookspath=[],
    runtime_hooks=[],
    excludes=["tkinter", "matplotlib", "IPython"],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, a.binaries, a.datas, [], name="tile_service", debug=False, strip=False, upx=False, console=True,
          disable_windowed_traceback=False, argv_emulation=False, target_arch=None)
