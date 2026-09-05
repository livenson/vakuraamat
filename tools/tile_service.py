#!/usr/bin/env python3
"""Local tile service: turns a point in Estonia into a playable site pack plus its terrain tile.

    python3 tools/tile_service.py [--port 8765] [--workspace data_raw/service]

The game (scripts/autoload/locator.gd) talks to it:
    GET  /health                     -> {"ok": true}
    GET  /geocode?q=<text>           -> [{"name", "x", "y"}]           (Maa-amet in-ADS gazetteer)
    POST /tile  {"id","name","x","y","size","eras","seed","blocks"} -> 202 {"id"}   starts a job (or reuses a cached zip)
    GET  /status?id=<id>             -> {"stage","progress","done","error"}
    GET  /packs                      -> [{"id","name","x","y","size","eras","seed","blocks"}]  packs ready in the cache
    GET  /download?id=<id>           -> zip with site/<pack files> and tile/<engine files>
A job runs the same tools as `make site` + `make tile`, in a workspace outside the repo, with the
download cache shared (data_raw/). Needs python3, numpy, GDAL and node (for the ink compiler).
Nothing here is exposed beyond the loopback interface unless you bind it so.
"""
import argparse, json, os, re, shutil, subprocess, sys, threading, traceback, urllib.parse, urllib.request, zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools")); sys.path.insert(0, os.path.join(ROOT, "tools", "pipeline"))
import new_site, gen_era_scenes, extract_features, fetch_buildings, fetch_trees, fetch_parcels, fetch_roads, fetch_tenants, market  # noqa: E402

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


def run_job(job):
    sid = job["id"]
    ws = os.path.join(WORKSPACE, sid)

    def stage(name, frac):
        with LOCK:
            job["stage"] = name; job["progress"] = frac
        log(f"{sid}: {name}")
    try:
        if os.path.exists(ws) and job.get("force"):
            shutil.rmtree(ws)
        os.makedirs(os.path.join(ws, "sites"), exist_ok=True)
        os.makedirs(os.path.join(ws, "assets", "terrain"), exist_ok=True)
        open(os.path.join(ws, ".gdignore"), "a").close()
        stage("scaffold", 0.05)
        new_site.scaffold(sid, job["name"], (job["x"], job["y"]), job["size"], job["eras"], tile=sid, template="palupera",
                          force=True, root=ws, template_root=ROOT, texture_mode="path", seed=job.get("seed"), block_ids=job.get("blocks"))
        stage("fetching Maa-amet data", 0.1)
        subprocess.run([sys.executable, os.path.join(ROOT, "tools/pipeline/fetch_tile.py"), "--project", ws, "--site", sid,
                        "--raw-dir", os.path.join(ROOT, "data_raw")], check=True)
        stage("measured trees", 0.5)
        try:
            fetch_trees.fetch(sid, root=ws)
        except Exception as e:  # noqa: BLE001 - optional layer
            log(f"{sid}: tree dataset unavailable ({e}); statistical scatter")
        stage("building register", 0.55)
        try:
            fetch_buildings.fetch(sid, root=ws)
        except Exception as e:  # noqa: BLE001 - the register is optional; the nDSM massing stands in
            log(f"{sid}: building register unavailable ({e}); using laser massing")
        stage("cadastre and roads", 0.58)
        for mod in (fetch_parcels, fetch_roads):
            try:
                mod.fetch(sid, root=ws)
            except Exception as e:  # noqa: BLE001 - optional layers
                log(f"{sid}: {mod.__name__} unavailable ({e})")
        stage("tenants and market", 0.59)
        for name, fn in (("tenants", fetch_tenants.fetch), ("market", market.derive)):
            try:
                fn(sid, root=ws)
            except Exception as e:  # noqa: BLE001 - optional layers
                log(f"{sid}: {name} unavailable ({e})")
        stage("buildings, water, anchors", 0.6)
        _, _, anchors = extract_features.extract(sid, root=ws)
        stage("layout", 0.7)
        new_site.apply_anchors(sid, anchors, root=ws)
        new_site.scaffold(sid, job["name"], (job["x"], job["y"]), job["size"], job["eras"], tile=sid, template="palupera", force=True,
                          root=ws, template_root=ROOT, texture_mode="path", anchors=anchors, seed=job.get("seed"), block_ids=job.get("blocks"))
        new_site.relink_era_maps(sid, root=ws, texture_mode="path")
        stage("scenes", 0.75)
        if not gen_era_scenes.generate(sid, root=ws):
            raise RuntimeError("scene generation reported problems")
        stage("dialogue", 0.8)
        subprocess.run(["node", os.path.join(ROOT, "tools/ink/compile.js"), sid, os.path.join(ws, "sites")], check=True)
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
        log(f"{sid}: ready ({os.path.getsize(zpath) / 1e6:.1f} MB)")
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
