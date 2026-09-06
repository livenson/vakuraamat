#!/usr/bin/env python3
"""Local tile service: turns a point in Estonia into a playable site pack plus its terrain tile.

    python3 tools/tile_service.py [--port 8765] [--workspace data_raw/service]

The game (scripts/autoload/locator.gd) talks to it:
    GET  /health                     -> {"ok": true}
    GET  /geocode?q=<text>           -> [{"name", "x", "y"}]           (Maa-amet in-ADS gazetteer)
    GET  /estimate?x=&y=&size=       -> what a pack for the point would download (HEAD requests to the
                                        geoportal for each DTM and nDSM sheet, cached ones marked), the
                                        service's measured rate and the mean job time: {"items", "bytes",
                                        "cached_bytes", "rate_bps", "seconds_download", "seconds_process", "free_bytes"}
    GET  /cache                      -> the service workspace: {"bytes", "packs", "free_bytes", "path"}
    POST /tile  {"id","name","x","y","size","eras","seed","blocks"} -> 202 {"id"}   starts a job (or reuses a cached zip)
    GET  /status?id=<id>             -> {"stage","progress","done","error"}
    GET  /packs                      -> [{"id","name","x","y","size","eras","seed","blocks"}]  packs ready in the cache
    GET  /download?id=<id>           -> zip with site/<pack files> and tile/<engine files>
A job runs the same tools as `make site` + `make tile`, in a workspace outside the repo, with the
download cache shared (data_raw/). Needs python3, numpy and GDAL.
Nothing here is exposed beyond the loopback interface unless you bind it so.
"""
import argparse, time, json, os, re, shutil, subprocess, sys, threading, traceback, urllib.parse, urllib.request, zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools")); sys.path.insert(0, os.path.join(ROOT, "tools", "pipeline"))
import new_site, gen_era_scenes, extract_features, fetch_buildings, fetch_trees, fetch_parcels, fetch_roads, fetch_stops, fetch_tenants, fetch_fields, market  # noqa: E402

import fetch_tile  # noqa: E402
STATS_PATH = os.path.join(ROOT, "data_raw", "service_stats.json")
MIN_FREE_BYTES = 2 * 1024 ** 3   # a job needs raw sheets, the workspace and the zip: refuse under 2 GB
ORTHO_BYTES = 6 * 1024 ** 2      # the WMS orthophoto JPEG (4096 px) and the small historical maps
GEOCODER = "https://inaadress.maaamet.ee/inaadress/gazetteer?results=8&features=EHAK,TANAV,KATASTRIYKSUS,EHITISHOONE&address="
JOBS = {}
LOCK = threading.Lock()
WORKSPACE = os.path.join(ROOT, "data_raw", "service")


def log(msg):
    print(f"[tile_service] {msg}", flush=True)


def slug(name):
    s = re.sub(r"[^a-z0-9]+", "_", name.lower().replace("õ", "o").replace("ä", "a").replace("ö", "o").replace("ü", "u").replace("š", "s").replace("ž", "z")).strip("_")
    return (s if s and s[0].isalpha() else "site_" + s) or "site"


def geocode(q):
    """Maa-amet in-ADS: returns [{name, x, y}] with L-EST97 reference points."""
    with urllib.request.urlopen(GEOCODER + urllib.parse.quote(q), timeout=20) as r:
        data = json.load(r)
    out = []
    for a in data.get("addresses", []):
        try:
            out.append({"name": a.get("pikkaadress") or a.get("ipikkaadress") or q, "x": float(a["viitepunkt_x"]), "y": float(a["viitepunkt_y"])})
        except (KeyError, ValueError):
            continue
    return out


def load_stats():
    try:
        return json.load(open(STATS_PATH))
    except (OSError, ValueError):
        return {"rate_bps": 0.0, "jobs": []}


def save_stats(st):
    os.makedirs(os.path.dirname(STATS_PATH), exist_ok=True)
    json.dump(st, open(STATS_PATH, "w"))


def note_rate(text):
    """Keep the fetcher's last reported download rate ("... 12/74 MB, 3.1 MB/s")."""
    m = re.search(r"([\d.]+) MB/s", text)
    if m and float(m.group(1)) > 0:
        st = load_stats()
        st["rate_bps"] = float(m.group(1)) * 1e6
        save_stats(st)


def note_job(seconds):
    st = load_stats()
    st["jobs"] = (st.get("jobs") or [])[-9:] + [round(seconds)]
    save_stats(st)


def head_size(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "vakuraamat-pipeline/0.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return int(r.headers.get("Content-Length") or 0)


def estimate(x, y, size):
    """What a pack for (x, y) downloads: the DTM sheets of the tile's corners, the 1:2000 nDSM sheets,
    the orthophoto; each with its size (HEAD) and whether data_raw already holds it."""
    raw_dir = os.path.join(ROOT, "data_raw")
    half = size / 2
    xmin, ymin, xmax, ymax = x - half, y - half, x + half, y + half
    items = []

    def add(name, url, fname):
        cached = os.path.exists(os.path.join(raw_dir, fname))
        n = os.path.getsize(os.path.join(raw_dir, fname)) if cached else head_size(url)
        items.append({"name": name, "bytes": n, "cached": cached})

    sheets = sorted({fetch_tile.sheet_for_point(px, py, raw_dir) for px, py in [(xmin + 1, ymin + 1), (xmax - 1, ymin + 1), (xmin + 1, ymax - 1), (xmax - 1, ymax - 1)]})
    for sh in sheets:
        url = fetch_tile.dtm_download_url(sh)
        add("DTM %s" % sh, url, urllib.parse.parse_qs(urllib.parse.urlparse(url).query)["f"][0])
    for sheet in fetch_tile.sheets_2000_for_bbox(xmin, ymin, xmax, ymax, raw_dir):
        links = sorted(fetch_tile.geoportal_links(sheet, "ndsm_rel_1m_geotiff"), key=fetch_tile.link_year)
        if links:
            add("nDSM %s" % sheet, links[-1], urllib.parse.parse_qs(urllib.parse.urlparse(links[-1]).query)["f"][0])
    items.append({"name": "orthophoto, maps", "bytes": ORTHO_BYTES, "cached": False})
    st = load_stats()
    rate = float(st.get("rate_bps") or 0.0) or 4e6
    jobs = st.get("jobs") or []
    to_get = sum(i["bytes"] for i in items if not i["cached"])
    return {"items": items, "bytes": sum(i["bytes"] for i in items), "cached_bytes": sum(i["bytes"] for i in items if i["cached"]),
            "download_bytes": to_get, "rate_bps": rate, "seconds_download": round(to_get / rate),
            "seconds_process": round(sum(jobs) / len(jobs)) if jobs else 360, "free_bytes": shutil.disk_usage(WORKSPACE).free}


def cache_info():
    total = 0
    packs = []
    for f in sorted(os.listdir(WORKSPACE)):
        full = os.path.join(WORKSPACE, f)
        if os.path.isdir(full):
            n = sum(os.path.getsize(os.path.join(dp, fn)) for dp, _, fns in os.walk(full) for fn in fns)
            zpath = full + ".zip"
            if os.path.exists(zpath):
                n += os.path.getsize(zpath)
            packs.append({"id": f, "bytes": n})
            total += n
    return {"bytes": total, "packs": packs, "free_bytes": shutil.disk_usage(WORKSPACE).free, "path": WORKSPACE}


def run_job(job):
    sid = job["id"]
    ws = os.path.join(WORKSPACE, sid)
    started = time.time()

    def stage(name, frac):
        with LOCK:
            job["stage"] = name; job["progress"] = frac
        log(f"{sid}: {name}")
    try:
        free = shutil.disk_usage(WORKSPACE).free
        if free < MIN_FREE_BYTES:
            raise RuntimeError("only %.1f GB free on the service's disk (%s); a world needs about 2 GB" % (free / 1024 ** 3, WORKSPACE))
        if os.path.exists(ws) and job.get("force"):
            shutil.rmtree(ws)
        os.makedirs(os.path.join(ws, "sites"), exist_ok=True)
        os.makedirs(os.path.join(ws, "assets", "terrain"), exist_ok=True)
        open(os.path.join(ws, ".gdignore"), "a").close()
        stage("scaffold", 0.05)
        new_site.scaffold(sid, job["name"], (job["x"], job["y"]), job["size"], job["eras"], tile=sid, template="palupera",
                          force=True, root=ws, template_root=ROOT, texture_mode="path", seed=job.get("seed"), block_ids=job.get("blocks"))
        stage("Maa-amet data", 0.1)
        # the fetcher reports its steps as "[progress] <0..1> <text>" lines: they become the stage
        proc = subprocess.Popen([sys.executable, os.path.join(ROOT, "tools/pipeline/fetch_tile.py"), "--project", ws, "--site", sid,
                                 "--raw-dir", os.path.join(ROOT, "data_raw")], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in proc.stdout:
            line = line.rstrip("\n")
            if line.startswith("[progress] "):
                _, frac, text = line.split(" ", 2)
                stage("Maa-amet: " + text, 0.1 + 0.35 * float(frac))
                note_rate(text)
            elif line:
                print(line, flush=True)
        if proc.wait() != 0:
            raise RuntimeError("fetch_tile.py failed")
        stage("measured trees", 0.46)
        try:
            fetch_trees.fetch(sid, root=ws)
        except Exception as e:  # noqa: BLE001 - optional layer
            log(f"{sid}: tree dataset unavailable ({e}); statistical scatter")
        stage("building register", 0.5)
        try:
            fetch_buildings.fetch(sid, root=ws, progress=lambda f, t: stage(t, 0.5 + 0.1 * f))
        except Exception as e:  # noqa: BLE001 - the register is optional; the nDSM massing stands in
            log(f"{sid}: building register unavailable ({e}); using laser massing")
        stage("cadastre", 0.61)
        try:
            fetch_parcels.fetch(sid, root=ws)
        except Exception as e:  # noqa: BLE001 - optional layer
            log(f"{sid}: fetch_parcels unavailable ({e})")
        stage("roads", 0.63)
        try:
            fetch_roads.fetch(sid, root=ws)
        except Exception as e:  # noqa: BLE001 - optional layer
            log(f"{sid}: fetch_roads unavailable ({e})")
        # Overpass queues requests for tens of seconds: the stops fetch runs beside the register stages
        def stops_job():
            try:
                fetch_stops.fetch(sid, root=ws)
            except Exception as e:  # noqa: BLE001 - optional layer
                log(f"{sid}: fetch_stops unavailable ({e})")
        stops_thread = threading.Thread(target=stops_job, daemon=True)
        stops_thread.start()
        stage("fields (PRIA)", 0.635)
        try:
            fetch_fields.fetch(sid, root=ws)
        except Exception as e:  # noqa: BLE001 - optional layer
            log(f"{sid}: fetch_fields unavailable ({e})")
        stage("tenants (business register)", 0.64)
        try:
            fetch_tenants.fetch(sid, root=ws)
        except Exception as e:  # noqa: BLE001 - optional layer
            log(f"{sid}: tenants unavailable ({e})")
        stage("market snapshot", 0.66)
        try:
            market.derive(sid, root=ws)
        except Exception as e:  # noqa: BLE001 - optional layer
            log(f"{sid}: market unavailable ({e})")
        if stops_thread.is_alive():
            stage("bus stops (OpenStreetMap)", 0.665)
            stops_thread.join(60)
            if stops_thread.is_alive():
                log(f"{sid}: bus stops still queued at Overpass; the pack goes without them")
        stage("buildings, water, boats, anchors", 0.67)
        _, _, anchors = extract_features.extract(sid, root=ws)
        stage("layout", 0.7)
        new_site.apply_anchors(sid, anchors, root=ws)
        new_site.scaffold(sid, job["name"], (job["x"], job["y"]), job["size"], job["eras"], tile=sid, template="palupera", force=True,
                          root=ws, template_root=ROOT, texture_mode="path", anchors=anchors, seed=job.get("seed"), block_ids=job.get("blocks"))
        new_site.relink_era_maps(sid, root=ws, texture_mode="path")
        stage("scenes", 0.75)
        if not gen_era_scenes.generate(sid, root=ws):
            raise RuntimeError("scene generation reported problems")
        stage("validation", 0.85)
        subprocess.run([sys.executable, os.path.join(ROOT, "tools/validate_site.py"), "--site", sid, "--root", ws], check=True)
        stage("packing", 0.9)
        zpath = os.path.join(WORKSPACE, sid + ".zip")
        with zipfile.ZipFile(zpath + ".part", "w", zipfile.ZIP_DEFLATED) as z:
            site_dir = os.path.join(ws, "sites", sid)
            for dp, _, files in os.walk(site_dir):
                for f in files:
                    if f.endswith(".import"):
                        continue
                    full = os.path.join(dp, f)
                    z.write(full, "site/" + os.path.relpath(full, site_dir))
            tile_dir = os.path.join(ws, "assets", "terrain", sid)
            for f in sorted(os.listdir(tile_dir)):
                full = os.path.join(tile_dir, f)
                if os.path.isfile(full) and not f.endswith(".import"):
                    z.write(full, "tile/" + f)   # includes trees.json when the dataset covers the tile
        os.replace(zpath + ".part", zpath)
        with LOCK:
            job.update(stage="ready", progress=1.0, done=True, zip=zpath)
        note_job(time.time() - started)
        log(f"{sid}: ready ({os.path.getsize(zpath) / 1e6:.1f} MB, {time.time() - started:.0f} s)")
    except Exception as e:  # noqa: BLE001 - report anything to the client
        traceback.print_exc()
        with LOCK:
            job.update(stage="failed", done=True, error=str(e))


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        log(fmt % args)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        qs = urllib.parse.parse_qs(u.query)
        if u.path == "/health":
            return self._json(200, {"ok": True, "version": 1})
        if u.path == "/geocode":
            q = qs.get("q", [""])[0].strip()
            if not q:
                return self._json(400, {"error": "q missing"})
            try:
                return self._json(200, geocode(q))
            except Exception as e:  # noqa: BLE001
                return self._json(502, {"error": str(e)})
        if u.path == "/estimate":
            try:
                x, y = float(qs.get("x", [""])[0]), float(qs.get("y", [""])[0])
                size = int(qs.get("size", ["1024"])[0])
            except ValueError:
                return self._json(400, {"error": "need x and y (EPSG:3301)"})
            if not (369000 < x < 740000 and 6377000 < y < 6635000):
                return self._json(400, {"error": "outside Estonia"})
            try:
                return self._json(200, estimate(x, y, size))
            except Exception as e:  # noqa: BLE001
                return self._json(502, {"error": str(e)})
        if u.path == "/cache":
            return self._json(200, cache_info())
        if u.path == "/packs":
            packs = []
            for f in sorted(os.listdir(WORKSPACE)):
                if f.endswith(".zip"):
                    sid = f[:-4]
                    mpath = os.path.join(WORKSPACE, sid, "sites", sid, "site.json")
                    if os.path.exists(mpath):
                        m = json.load(open(mpath))
                        packs.append({"id": sid, "name": m.get("description", sid).split(":")[0], "x": m["terrain"]["center"][0], "y": m["terrain"]["center"][1],
                                      "size": m["terrain"]["size"], "eras": ",".join(str(e).rsplit("_", 1)[-1] for e in sorted(os.listdir(os.path.join(WORKSPACE, sid, "sites", sid, "data", "eras"))) if e.endswith(".tres")).replace(".tres", ""),
                                      "seed": m.get("story", {}).get("seed"), "blocks": m.get("story", {}).get("blocks")})
            return self._json(200, packs)
        if u.path == "/status":
            sid = qs.get("id", [""])[0]
            with LOCK:
                job = dict(JOBS.get(sid, {}))
            if not job:
                zpath = os.path.join(WORKSPACE, sid + ".zip")
                if sid and os.path.exists(zpath):
                    return self._json(200, {"id": sid, "stage": "ready", "progress": 1.0, "done": True})
                return self._json(404, {"error": "unknown job"})
            job.pop("zip", None)
            return self._json(200, job)
        if u.path == "/download":
            sid = qs.get("id", [""])[0]
            zpath = os.path.join(WORKSPACE, sid + ".zip")
            if not sid or not os.path.exists(zpath):
                return self._json(404, {"error": "not ready"})
            self.send_response(200); self.send_header("Content-Type", "application/zip"); self.send_header("Content-Length", str(os.path.getsize(zpath))); self.end_headers()
            with open(zpath, "rb") as f:
                shutil.copyfileobj(f, self.wfile)
            return None
        return self._json(404, {"error": "no such route"})

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        if u.path != "/tile":
            return self._json(404, {"error": "no such route"})
        n = int(self.headers.get("Content-Length", "0"))
        try:
            req = json.loads(self.rfile.read(n) or b"{}")
            x, y = float(req["x"]), float(req["y"])
        except (ValueError, KeyError, json.JSONDecodeError):
            return self._json(400, {"error": "need x and y (EPSG:3301)"})
        name = str(req.get("name") or "Site").strip()[:60]
        sid = slug(str(req.get("id") or name))
        size = int(req.get("size") or 1024)
        eras = "2026"   # the present-day layer; older eras belong to the historical game (tag v0.9-historical)
        if not (369000 < x < 740000 and 6377000 < y < 6635000):
            return self._json(400, {"error": "outside Estonia"})
        with LOCK:
            job = JOBS.get(sid)
            if job and not job.get("done"):
                return self._json(202, {"id": sid, "stage": job["stage"]})
            if os.path.exists(os.path.join(WORKSPACE, sid + ".zip")) and not req.get("force"):
                JOBS[sid] = {"id": sid, "stage": "ready", "progress": 1.0, "done": True}
                return self._json(202, {"id": sid, "stage": "ready"})
            job = {"id": sid, "name": name, "x": x, "y": y, "size": size, "eras": eras, "force": bool(req.get("force")),
                   "seed": int(req["seed"]) if req.get("seed") is not None else None, "blocks": req.get("blocks") or None,
                   "stage": "queued", "progress": 0.0, "done": False}
            JOBS[sid] = job
        threading.Thread(target=run_job, args=(job,), daemon=True).start()
        return self._json(202, {"id": sid, "stage": "queued"})


def main():
    global WORKSPACE
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--workspace", default=WORKSPACE)
    a = ap.parse_args()
    WORKSPACE = a.workspace
    os.makedirs(WORKSPACE, exist_ok=True)
    open(os.path.join(WORKSPACE, ".gdignore"), "a").close()
    srv = ThreadingHTTPServer((a.bind, a.port), Handler)
    log(f"listening on http://{a.bind}:{a.port}  workspace {WORKSPACE}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
