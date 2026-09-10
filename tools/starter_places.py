#!/usr/bin/env python3
"""The starter places: the eight tiles around each shipped place, built once and published as one zip
on a GitHub release, so a first boot downloads them from GitHub instead of making the tile service
fetch sixteen places from the national services on every machine.

    python3 tools/starter_places.py build [--places kvissentali,pirita] [--service http://127.0.0.1:8765]
    python3 tools/starter_places.py publish        # uploads build/starter-places.zip with gh

`build` asks the running tile service for each neighbour (a stale cached pack is refreshed, a missing
one is made), waits for its 1 m ground, repacks the zip without files the current pipeline no
longer writes, checks the pipeline stamp and writes build/starter-places.zip (one <id>.zip per tile)
and assets/data/starter_places.json, which the game reads (Locator.starter_*). `publish` creates the
release named in the manifest and uploads the zip; commit the manifest after it.
"""
import argparse, hashlib, io, json, os, subprocess, sys, time, urllib.request, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from new_site import PACK_VERSION  # noqa: E402

REPO = "livenson/vakuraamat"
OUT_ZIP = os.path.join(ROOT, "build", "starter-places.zip")
MANIFEST = os.path.join(ROOT, "assets", "data", "starter_places.json")
DROP = ("site/news.json",)          # written by pipelines before the news feed was removed
SIZE = 1024


def log(msg):
    print(f"[starter] {msg}", flush=True)


def ring(site):
    """The eight neighbour pack ids of a shipped site, as TileStreamer.pack_id names them."""
    t = json.load(open(os.path.join(ROOT, "sites", site, "site.json")))["terrain"]
    cx, cy = t["center"]
    size = t.get("size", SIZE)
    out = []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx or dy:
                x, y = cx + dx * size, cy - dy * size
                out.append((f"t{round(x)}_{round(y)}", x, y))
    return out


def call(url, body=None, timeout=60):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json"} if body is not None else {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read()
    return data


def make(service, pid, x, y):
    """One neighbour, current and refined, as zip bytes."""
    zpath = os.path.join(ROOT, "data_raw", "service", pid + ".zip")
    stale = True
    if os.path.exists(zpath):
        with zipfile.ZipFile(zpath) as z:
            m = json.loads(z.read("site/site.json")) if "site/site.json" in z.namelist() else {}
        stale = int(m.get("pipeline") or 0) < PACK_VERSION
    body = {"id": pid, "name": f"Tile {int(x)} {int(y)}", "x": x, "y": y, "size": SIZE, "eras": "2026", "refresh": stale}
    call(service + "/tile", body)
    started = time.time()
    while True:
        st = json.loads(call(f"{service}/status?id={pid}"))
        if st.get("error"):
            raise RuntimeError(f"{pid}: {st['error']}")
        if st.get("done") and st.get("refined"):
            break
        if time.time() - started > 3600:
            raise RuntimeError(f"{pid}: not refined after an hour ({st})")
        time.sleep(5)
    data = call(f"{service}/download?id={pid}", timeout=600)
    src = zipfile.ZipFile(io.BytesIO(data))
    m = json.loads(src.read("site/site.json"))
    if int(m.get("pipeline") or 0) < PACK_VERSION:
        raise RuntimeError(f"{pid}: stamped {m.get('pipeline')}, the build expects {PACK_VERSION}")
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as dst:
        for info in src.infolist():
            if info.filename not in DROP:
                dst.writestr(info, src.read(info.filename))
    log(f"{pid}: {len(out.getvalue()) // 1_000_000} MB, refined, pipeline {m.get('pipeline')} ({time.time() - started:.0f} s)")
    return out.getvalue()


def build(args):
    places = [p.strip() for p in args.places.split(",") if p.strip()]
    tag = args.tag or "places-" + time.strftime("%Y-%m-%d")
    os.makedirs(os.path.dirname(OUT_ZIP), exist_ok=True)
    per_place = {}
    with zipfile.ZipFile(OUT_ZIP, "w", zipfile.ZIP_STORED) as bundle:   # the inner zips are compressed already
        for site in places:
            per_place[site] = []
            for pid, x, y in ring(site):
                bundle.writestr(pid + ".zip", make(args.service, pid, x, y))
                per_place[site].append(pid)
    sha = hashlib.sha256(open(OUT_ZIP, "rb").read()).hexdigest()
    manifest = {
        "tag": tag,
        "url": f"https://github.com/{REPO}/releases/download/{tag}/starter-places.zip",
        "sha256": sha,
        "bytes": os.path.getsize(OUT_ZIP),
        "pipeline": PACK_VERSION,
        "built": time.strftime("%Y-%m-%d"),
        "places": per_place,
        "attribution": "Maa- ja Ruumiamet; Ehitisregister; Äriregistri avaandmed (CC BY 4.0); Maksu- ja Tolliamet; "
                       "bus stops © OpenStreetMap contributors (ODbL); Ühistranspordiregistri avaandmed; PRIA. "
                       "Each pack's files carry their own attribution.",
    }
    json.dump(manifest, open(MANIFEST, "w"), indent=1, ensure_ascii=False)
    log(f"{OUT_ZIP}: {manifest['bytes'] // 1_000_000} MB, {sum(len(v) for v in per_place.values())} tiles, sha256 {sha[:12]}")
    log(f"wrote {MANIFEST}; next: python3 tools/starter_places.py publish, then commit the manifest")


def publish(_args):
    m = json.load(open(MANIFEST))
    if hashlib.sha256(open(OUT_ZIP, "rb").read()).hexdigest() != m["sha256"]:
        sys.exit("build/starter-places.zip does not match the manifest: run build again")
    notes = ("The tiles around the shipped places (" + ", ".join(m["places"]) + "), pipeline " + str(m["pipeline"])
             + ", built " + m["built"] + ". The game downloads this once on first boot (Locator.starter_*); "
             "it is not a game release. Data: " + m["attribution"])
    subprocess.run(["gh", "release", "create", m["tag"], OUT_ZIP, "--repo", REPO, "--title", "Starter places " + m["built"],
                    "--notes", notes, "--latest=false"], check=True)
    log(f"published {m['url']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["build", "publish"])
    ap.add_argument("--places", default="kvissentali,pirita")
    ap.add_argument("--service", default="http://127.0.0.1:8765")
    ap.add_argument("--tag", default="")
    args = ap.parse_args()
    build(args) if args.command == "build" else publish(args)


if __name__ == "__main__":
    main()
