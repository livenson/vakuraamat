# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for the tile-service sidecar: tools/tile_service.py with the pipeline modules,
# the manifest and strings of the template pack (sites/palupera), the parcel rules and the core
# strings it reads.
#   pyinstaller --clean --noconfirm tools/service/tile_service.spec        (tools/service/build.sh)
import glob, os
from PyInstaller.utils.hooks import collect_all

ROOT = os.path.abspath(os.path.join(SPECPATH, "..", ".."))
datas = [
    (os.path.join(ROOT, "sites", "palupera", "site.json"), "sites/palupera"),
    (os.path.join(ROOT, "sites", "palupera", "strings.csv"), "sites/palupera"),
    # the parcel rules and every country's outline: sources.py tells a country's land by its outline
    # (Latvia's laser sheets reach over the Estonian border), cross_border.py the sides of a border tile
    *[(p, "assets/data") for p in sorted(glob.glob(os.path.join(ROOT, "assets", "data", "*.json")))],
    (os.path.join(ROOT, "assets", "i18n", "strings.csv"), "assets/i18n"),
]
binaries, hiddenimports = [], []
# certifi carries cacert.pem: a frozen binary has no system CA store, and without it every
# https call to the geoportal, the registers and the WMS fails to verify (tile_service points
# SSL_CERT_FILE at this copy when it runs frozen)
for pkg in ("rasterio", "pyogrio", "shapely", "pyproj", "certifi"):
    d, b, h = collect_all(pkg)
    datas += d; binaries += b; hiddenimports += h

a = Analysis(
    [os.path.join(ROOT, "tools", "tile_service.py")],
    pathex=[os.path.join(ROOT, "tools"), os.path.join(ROOT, "tools", "pipeline")],
    binaries=binaries,
    datas=datas,
    # the tools the service imports by name, and every pipeline module: a country's adapter
    # (sources.py) imports its fetchers lazily, where PyInstaller cannot see them
    hiddenimports=hiddenimports + ["new_site", "gen_era_scenes", "extract_features", "validate_site"]
                  + sorted(f[:-3] for f in os.listdir(os.path.join(ROOT, "tools", "pipeline")) if f.endswith(".py")),
    hookspath=[],
    runtime_hooks=[],
    excludes=["tkinter", "matplotlib", "IPython"],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, a.binaries, a.datas, [], name="tile_service", debug=False, strip=False, upx=False, console=True,
          disable_windowed_traceback=False, argv_emulation=False, target_arch=None)
