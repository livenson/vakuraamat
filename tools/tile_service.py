#!/usr/bin/env python3
"""Local tile service: turns a point in Estonia or Latvia into a playable site pack plus its terrain tile.

    python3 tools/tile_service.py [--port 8765] [--workspace data_raw/service] [--raw-dir data_raw]

The game (scripts/autoload/locator.gd) talks to it:
    GET  /health                     -> {"ok": true}
    GET  /geocode?q=<text>           -> [{"name", "x", "y"}]           (Maa-amet in-ADS gazetteer, then Latvia's)
    GET  /geocode_lv?q=<text>        -> [{"name", "x", "y"}]           (Latvia's address register, tools/pipeline/geocode_lv.py)
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
download cache shared (data_raw/, or --raw-dir). Needs python3 with numpy, Pillow, rasterio, pyogrio, shapely and pyproj;
the same script frozen with tools/service/build.sh ships beside the exported game as the tile_service sidecar.
Nothing here is exposed beyond the loopback interface unless you bind it so.
"""
import argparse, concurrent.futures, time, json, os, re, shutil, sys, threading, traceback, urllib.parse, urllib.request, zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "pipeline"))
# The service shares the machine with a running game: the pipeline's numeric libraries stay on a
# couple of threads (set before numpy loads with the pipeline modules) and the process runs at a
# lower priority (main()).
for _v in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "GDAL_NUM_THREADS"):
    os.environ.setdefault(_v, "2")
# A frozen build (tools/service/build.sh) carries no system CA store, so OpenSSL's default paths
# point at nothing and every https call - the geoportal, the registers, the WMS - fails to verify.
# certifi's bundle is packed beside the binary; point OpenSSL at it before anything opens a socket.
if getattr(sys, "frozen", False):
    try:
        import certifi
        os.environ.setdefault("SSL_CERT_FILE", certifi.where())
        os.environ.setdefault("REQUESTS_CA_BUNDLE", certifi.where())
    except ImportError:
        print("[tile_service] warning: certifi is missing; https calls will fail to verify", flush=True)
import paths  # noqa: E402
ROOT = paths.ROOT   # the repository, or the bundle directory of the frozen sidecar (tools/service/build.sh)
import new_site, gen_era_scenes, extract_features, fetch_buildings, fetch_trees, fetch_parcels, fetch_roads, fetch_stops, fetch_tenants, fetch_fields, market  # noqa: E402
import fetch_tile, fetch_departures, validate_site, sources  # noqa: E402
MIN_FREE_BYTES = 2 * 1024 ** 3   # a job needs raw sheets, the workspace and the zip: refuse under 2 GB
ORTHO_BYTES = 6 * 1024 ** 2      # the WMS orthophoto JPEG (4096 px) and the small historical maps
GEOCODER = "https://inaadress.maaamet.ee/inaadress/gazetteer?results=8&features=EHAK,TANAV,KATASTRIYKSUS,EHITISHOONE&address="
JOBS = {}
LOCK = threading.Lock()
WORKSPACE = os.path.join(paths.raw_root(), "service")   # data_raw/service in the repo; the game's user directory for the sidecar


def stats_path():
    return os.path.join(paths.raw_root(), "service_stats.json")


def log(msg):
    print(f"[tile_service] {msg}", flush=True)


def slug(name):
    import unicodedata   # õ, ä, ö, ü, š, ž and Latvian ā, ē, ī, ķ, ļ, ņ ... lose their marks: "Rīga" is "riga"
    folded = "".join(c for c in unicodedata.normalize("NFKD", name.lower()) if not unicodedata.combining(c))
    s = re.sub(r"[^a-z0-9]+", "_", folded).strip("_")
    return (s if s and s[0].isalpha() else "site_" + s) or "site"


def country_of(x, y):
    """The adapter covering an L-EST97 point ("ee", "lv"), or None."""
    s = sources.for_point(x, y)
    return s.id if s else None


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
        return json.load(open(stats_path()))
    except (OSError, ValueError):
        return {"rate_bps": 0.0, "jobs": []}


def save_stats(st):
    os.makedirs(os.path.dirname(stats_path()), exist_ok=True)
    json.dump(st, open(stats_path(), "w"))


def note_rate(text):
    """Keep a running mean of the fetcher's reported download rate ("... 12/74 MB, 3.1 MB/s").
    A single value is whatever the last burst happened to reach, and the estimate then promises a
    minute where the link delivers a quarter of an hour; the mean of the last twenty is closer."""
    m = re.search(r"([\d.]+) MB/s", text)
    if m and float(m.group(1)) > 0:
        st = load_stats()
        rates = (st.get("rates") or [])[-19:] + [float(m.group(1)) * 1e6]
        st["rates"] = rates
        st["rate_bps"] = sum(rates) / len(rates)
        save_stats(st)


def note_job(seconds):
    st = load_stats()
    st["jobs"] = (st.get("jobs") or [])[-9:] + [round(seconds)]
    save_stats(st)


def with_deadline(name, seconds, fn, *args, **kwargs):
    """Run an optional stage with a hard time budget. A stage that reaches national services can
    stall for minutes on a slow feed (the notices XML has a 180 s socket timeout, twice); the pack
    must not wait for it. On timeout the worker is abandoned to finish or die on its own and the
    job carries on without that layer. Returns (ok, result)."""
    ex = concurrent.futures.ThreadPoolExecutor(max_workers=1)   # not a with-block: shutdown must not wait
    fut = ex.submit(fn, *args, **kwargs)
    try:
        return True, fut.result(timeout=seconds)
    except concurrent.futures.TimeoutError:
        log(f"{name}: still running after {seconds} s; the pack goes without it")
        return False, None
    except Exception as e:  # noqa: BLE001 - every one of these layers is optional
        log(f"{name}: unavailable ({e})")
        return False, None
    finally:
        ex.shutdown(wait=False)


def head_size(url):
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "vakuraamat-pipeline/0.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return int(r.headers.get("Content-Length") or 0)


def estimate(x, y, size):
    """What a pack for (x, y) downloads: the DTM sheets of the tile's corners, the 1:2000 nDSM sheets,
    the orthophoto; each with its size (HEAD) and whether data_raw already holds it. In Latvia: the
    laser sheets under the tile (the ground, the canopy and the building heights all come from them)."""
    raw_dir = paths.raw_root()
    half = size / 2
    xmin, ymin, xmax, ymax = x - half, y - half, x + half, y + half
    items = []
    if country_of(x, y) == "lv":
        import fetch_tile_lv
        index = fetch_tile_lv.las_index()
        for sh in fetch_tile_lv._sheets_over(fetch_tile_lv.lks_bbox((xmin, ymin, xmax, ymax)), 1000.0, fetch_tile_lv.las_sheet):
            if sh in index:
                local = os.path.join(raw_dir, "lv", "las", sh + ".las")
                cached = os.path.exists(local)
                items.append({"name": "laser points %s" % sh, "bytes": os.path.getsize(local) if cached else head_size(index[sh]), "cached": cached})
        items.append({"name": "orthophoto, cadastre", "bytes": 60 * 1024 ** 2, "cached": False})
        st = load_stats()
        rate = float(st.get("rate_bps") or 0.0) or 4e6
        jobs = st.get("jobs") or []
        to_get = sum(i["bytes"] for i in items if not i["cached"])
        return {"items": items, "bytes": sum(i["bytes"] for i in items), "cached_bytes": sum(i["bytes"] for i in items if i["cached"]),
                "download_bytes": to_get, "rate_bps": rate, "seconds_download": round(to_get / rate),
                "seconds_process": round(sum(jobs) / len(jobs)) if jobs else 120, "refine_bytes": 0, "seconds_refine": 0,
                "free_bytes": shutil.disk_usage(WORKSPACE).free}

    def add(name, url, fname):
        cached = os.path.exists(os.path.join(raw_dir, fname))
        n = os.path.getsize(os.path.join(raw_dir, fname)) if cached else head_size(url)
        items.append({"name": name, "bytes": n, "cached": cached})

    sheets = sorted({fetch_tile.sheet_for_point(px, py, raw_dir) for px, py in [(xmin + 1, ymin + 1), (xmax - 1, ymin + 1), (xmin + 1, ymax - 1), (xmax - 1, ymax - 1)]})
    refine = 0
    for sh in sheets:
        url = fetch_tile.dtm_download_url(sh, "dem_5m_geotiff")   # the ground the first pack ships
        add("DTM %s (5 m)" % sh, url, urllib.parse.parse_qs(urllib.parse.urlparse(url).query)["f"][0])
        fine = fetch_tile.dtm_download_url(sh)                     # fetched afterwards, not part of the wait
        fname = urllib.parse.parse_qs(urllib.parse.urlparse(fine).query)["f"][0]
        refine += 0 if os.path.exists(os.path.join(raw_dir, fname)) else head_size(fine)
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
            "seconds_process": round(sum(jobs) / len(jobs)) if jobs else 120,
            "refine_bytes": refine, "seconds_refine": round(refine / rate),   # the 1 m ground, fetched after the pack is playable
            "free_bytes": shutil.disk_usage(WORKSPACE).free}


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


def write_zip(sid, ws):
    """The pack the game installs: the site files and the tile's engine files. Written to a .part
    first and moved into place, so the refinement pass can replace it under a client that is
    downloading."""
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
    return zpath


def estonian_registers(sid, ws, stage):
    """The Estonian register stages of a job; returns the bus-stop thread still running beside them."""
    stage("building register", 0.5)
    with_deadline(f"{sid}: building register", 240, fetch_buildings.fetch, sid, root=ws,
                  progress=lambda f, t: stage(t, 0.5 + 0.1 * f))
    stage("cadastre", 0.61)
    with_deadline(f"{sid}: cadastre", 120, fetch_parcels.fetch, sid, root=ws)
    stage("roads", 0.63)
    with_deadline(f"{sid}: roads", 120, fetch_roads.fetch, sid, root=ws)
    # Overpass queues requests for tens of seconds: the stops fetch runs beside the register stages
    def stops_job():
        try:
            fetch_stops.fetch(sid, root=ws)
        except Exception as e:  # noqa: BLE001 - optional layer
            log(f"{sid}: fetch_stops unavailable ({e})")
    stops_thread = threading.Thread(target=stops_job, daemon=True)
    stops_thread.start()
    stage("fields (PRIA)", 0.635)
    with_deadline(f"{sid}: fields", 120, fetch_fields.fetch, sid, root=ws)
    stage("tenants (business register)", 0.64)
    with_deadline(f"{sid}: tenants", 180, fetch_tenants.fetch, sid, root=ws)
    stage("market snapshot", 0.66)
    with_deadline(f"{sid}: market", 60, market.derive, sid, root=ws)
    return stops_thread


def run_job(job):
    sid = job["id"]
    ws = os.path.join(WORKSPACE, sid)
    started = time.time()

    marks = []   # (seconds since the job started, stage name): printed as a breakdown when it is ready

    def stage(name, frac):
        with LOCK:
            job["stage"] = name; job["progress"] = frac
        marks.append((time.time() - started, name))
        log(f"{sid}: {name} [{time.time() - started:.0f} s]")
    try:
        free = shutil.disk_usage(WORKSPACE).free
        if free < MIN_FREE_BYTES:
            raise RuntimeError("only %.1f GB free on the service's disk (%s); a world needs about 2 GB" % (free / 1024 ** 3, WORKSPACE))
        if os.path.exists(ws) and job.get("force"):
            shutil.rmtree(ws)
        # A rebuild starts from an empty slate as far as the client is concerned: the marker and the
        # zip from the previous build are both still on disk, and /status and /download would keep
        # handing them out for the whole run.
        if job.get("force") or job.get("refresh"):
            marker = os.path.join(WORKSPACE, sid + ".refined")
            if os.path.exists(marker):
                os.remove(marker)
        os.makedirs(os.path.join(ws, "sites"), exist_ok=True)
        os.makedirs(os.path.join(ws, "assets", "terrain"), exist_ok=True)
        open(os.path.join(ws, ".gdignore"), "a").close()
        country = country_of(job["x"], job["y"])
        stage("scaffold", 0.05)
        new_site.scaffold(sid, job["name"], (job["x"], job["y"]), job["size"], job["eras"], tile=sid,
                          force=True, root=ws, texture_mode="path", seed=job.get("seed"), block_ids=job.get("blocks"))
        source = "LĢIA" if country == "lv" else "Maa-amet"
        stage(f"{source} data", 0.1)

        def on_progress(frac, text):   # the fetcher's steps become the job's stage
            stage(f"{source}: " + text, 0.1 + 0.35 * float(frac))
            note_rate(text)
        fetch_tile.PROGRESS = on_progress
        try:
            # the 5 m ground model (4 MB a sheet against 75 MB) so the place can be walked in a
            # minute; refine_job fetches the 1 m one afterwards and the game picks it up next visit.
            # A refresh is about the registers, so it keeps the ground it has - including the 1 m one
            # a refine pass may already have paid for, which a re-fetch would throw away.
            if job.get("refresh") and os.path.exists(os.path.join(ws, "assets", "terrain", sid, "heightmap.r32")):
                log(f"{sid}: refresh, keeping the ground already fetched")
            else:
                fetch_tile.main(["--project", ws, "--site", sid, "--raw-dir", paths.raw_root(), "--dem-res", "5"])
        finally:
            fetch_tile.PROGRESS = None
        if country == "lv":
            # Latvia (docs/latvia-plan.md): the cadastre gives parcels and buildings in one pass, the
            # register and VID the companies; roads, stops, fields and timetables are later steps
            stage("cadastre (VZD), buildings, Rīga's roofs", 0.5)
            import fetch_cadastre_lv
            ok, _ = with_deadline(f"{sid}: cadastre", 1500, fetch_cadastre_lv.fetch, sid, root=ws)
            if not ok:
                raise RuntimeError("the Latvian cadastre could not be read (see the service log)")
            stage("companies (UR) and taxes (VID)", 0.62)
            import fetch_tenants_lv
            with_deadline(f"{sid}: tenants", 600, fetch_tenants_lv.fetch, sid, root=ws)
            stops_thread = None
        else:
            stops_thread = estonian_registers(sid, ws, stage)
        if stops_thread is not None and stops_thread.is_alive():
            stage("bus stops (OpenStreetMap)", 0.665)
            stops_thread.join(60)
            if stops_thread.is_alive():
                log(f"{sid}: bus stops still queued at Overpass; the pack goes without them")
        stage("buildings, water, boats, anchors", 0.67)
        _, _, anchors = extract_features.extract(sid, root=ws)
        stage("layout", 0.7)
        new_site.apply_anchors(sid, anchors, root=ws)
        new_site.scaffold(sid, job["name"], (job["x"], job["y"]), job["size"], job["eras"], tile=sid, force=True,
                          root=ws, texture_mode="path", anchors=anchors, seed=job.get("seed"), block_ids=job.get("blocks"))
        new_site.relink_era_maps(sid, root=ws, texture_mode="path")
        stage("scenes", 0.75)
        if not gen_era_scenes.generate(sid, root=ws):
            raise RuntimeError("scene generation reported problems")
        stage("validation", 0.85)
        rep = validate_site.Report()
        validate_site.validate(sid, rep, ws)
        for w in rep.warnings:
            log(f"{sid}: validation warning: {w}")
        if rep.errors:
            raise RuntimeError("validation: " + "; ".join(rep.errors[:5]))
        stage("packing", 0.9)
        zpath = write_zip(sid, ws)
        with LOCK:
            job.update(stage="ready", progress=1.0, done=True, zip=zpath, refined=False, refine_stage="queued")
        note_job(time.time() - started)
        threading.Thread(target=refine_job, args=(job, ws), daemon=True).start()
        marks.append((time.time() - started, "ready"))
        # what the wait was actually spent on, so a slow stage can be found without a profiler
        spans = [(marks[i + 1][0] - marks[i][0], marks[i][1]) for i in range(len(marks) - 1)]
        log(f"{sid}: stages " + ", ".join(f"{n} {d:.0f}s" for d, n in sorted(spans, reverse=True)[:8] if d >= 1))
        log(f"{sid}: ready ({os.path.getsize(zpath) / 1e6:.1f} MB, {time.time() - started:.0f} s)")
    except (Exception, SystemExit) as e:  # noqa: BLE001 - report anything to the client (the tools sys.exit on bad input)
        traceback.print_exc()
        with LOCK:
            job.update(stage="failed", done=True, error=str(e) or "failed")


def refine_job(job, ws):
    """What a pack does not need to be walked in, fetched after it is playable: the 1 m ground
    model in place of the 5 m one and the measured trees. Each has a budget, the zip is
    rewritten when they are in, and /status reports `refined`; the game downloads the pack again on
    its next visit to the place and rebuilds the tile from the finer ground."""
    sid = job["id"]
    started = time.time()

    def rstage(name):
        with LOCK:
            job["refine_stage"] = name
        log(f"{sid}: refining - {name} [{time.time() - started:.0f} s]")
    try:
        if country_of(job["x"], job["y"]) == "lv":
            # the ground is 1 m from the start (the laser sheets), and trees and timetables are later steps
            open(os.path.join(WORKSPACE, sid + ".refined"), "w").close()
            with LOCK:
                job.update(refined=True, refine_stage="ready", ground_res_m=1)
            return
        rstage("1 m ground model")
        ok, _ = with_deadline(f"{sid}: 1 m ground model", 900, fetch_tile.main,
                              ["--project", ws, "--site", sid, "--raw-dir", paths.raw_root(), "--dem-res", "1", "--only-dem"])
        rstage("measured trees")
        with_deadline(f"{sid}: measured trees", 600, fetch_trees.fetch, sid, root=ws)
        rstage("bus departures (public transport register)")
        # the national GTFS is one 52 MB zip for the whole country, cached a week like the register dumps
        with_deadline(f"{sid}: departures", 300, fetch_departures.fetch, sid, root=ws)
        rstage("packing")
        write_zip(sid, ws)
        if ok:
            open(os.path.join(WORKSPACE, sid + ".refined"), "w").close()   # JOBS is memory only; this survives a restart
        with LOCK:
            job.update(refined=True, refine_stage="ready", ground_res_m=1 if ok else 5)
        log(f"{sid}: refined ({time.time() - started:.0f} s)")
    except Exception as e:  # noqa: BLE001 - the pack already stands; a failed refinement is not fatal
        traceback.print_exc()
        with LOCK:
            job.update(refined=False, refine_stage="failed: " + (str(e) or "failed"))


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
            out = []
            try:
                out = geocode(q)
            except Exception as e:  # noqa: BLE001
                log(f"geocode: in-ADS unavailable ({e})")
            try:
                import geocode_lv
                out += geocode_lv.search(q)
            except Exception as e:  # noqa: BLE001
                log(f"geocode: Latvian register unavailable ({e})")
            return self._json(200, out)
        if u.path == "/geocode_lv":
            q = qs.get("q", [""])[0].strip()
            try:
                import geocode_lv
                return self._json(200, geocode_lv.search(q) if q else [])
            except Exception as e:  # noqa: BLE001
                return self._json(502, {"error": str(e)})
        if u.path == "/estimate":
            try:
                x, y = float(qs.get("x", [""])[0]), float(qs.get("y", [""])[0])
                size = int(qs.get("size", ["1024"])[0])
            except ValueError:
                return self._json(400, {"error": "need x and y (EPSG:3301)"})
            if country_of(x, y) is None:
                return self._json(400, {"error": "outside Estonia and Latvia"})
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
            refined = bool(sid) and os.path.exists(os.path.join(WORKSPACE, sid + ".refined"))
            with LOCK:
                job = dict(JOBS.get(sid, {}))
            if not job:
                zpath = os.path.join(WORKSPACE, sid + ".zip")
                if sid and os.path.exists(zpath):
                    return self._json(200, {"id": sid, "stage": "ready", "progress": 1.0, "done": True, "refined": refined})
                return self._json(404, {"error": "unknown job"})
            job.pop("zip", None)
            job["refined"] = bool(job.get("refined")) or refined
            return self._json(200, job)
        if u.path == "/download":
            sid = qs.get("id", [""])[0]
            zpath = os.path.join(WORKSPACE, sid + ".zip")
            if not sid or not os.path.exists(zpath):
                return self._json(404, {"error": "not ready"})
            # the zip is only replaced at the packing stage, so while a job runs this file is still
            # the previous build: handing it out would install the very pack the client asked to
            # have rebuilt
            with LOCK:
                running = JOBS.get(sid, {})
            if running and not running.get("done"):
                return self._json(409, {"error": "still building", "stage": running.get("stage", "")})
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
        if country_of(x, y) is None:
            return self._json(400, {"error": "outside Estonia and Latvia"})
        with LOCK:
            job = JOBS.get(sid)
            if job and not job.get("done"):
                return self._json(202, {"id": sid, "stage": job["stage"]})
            rebuild = bool(req.get("force")) or bool(req.get("refresh"))
            if os.path.exists(os.path.join(WORKSPACE, sid + ".zip")) and not rebuild:
                JOBS[sid] = {"id": sid, "stage": "ready", "progress": 1.0, "done": True}
                return self._json(202, {"id": sid, "stage": "ready"})
            job = {"id": sid, "name": name, "x": x, "y": y, "size": size, "eras": eras,
                   "force": bool(req.get("force")), "refresh": bool(req.get("refresh")),
                   "seed": int(req["seed"]) if req.get("seed") is not None else None, "blocks": req.get("blocks") or None,
                   "stage": "queued", "progress": 0.0, "done": False}
            JOBS[sid] = job
        threading.Thread(target=run_job, args=(job,), daemon=True).start()
        return self._json(202, {"id": sid, "stage": "queued"})


def parent_alive(pid):
    if os.name == "nt":
        import ctypes
        h = ctypes.windll.kernel32.OpenProcess(0x00100000, False, pid)   # SYNCHRONIZE
        if not h:
            return False
        gone = ctypes.windll.kernel32.WaitForSingleObject(h, 0) == 0
        ctypes.windll.kernel32.CloseHandle(h)
        return not gone
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def watch_parent(pid):
    """A sidecar started by the game ends with it: the game cannot kill a PyInstaller child through
    its bootloader, so the service polls the game's pid and exits when it is gone."""
    while parent_alive(pid):
        time.sleep(2.0)
    log(f"parent {pid} gone, exiting")
    os._exit(0)


def main():
    global WORKSPACE
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--workspace", default=None, help="generated packs (default: <raw dir>/service)")
    ap.add_argument("--raw-dir", default=None, help="download cache shared by every job (default: data_raw/ in the repo, or VAKURAAMAT_RAW_DIR)")
    ap.add_argument("--parent-pid", type=int, default=0, help="exit when this process is gone (the game that started the sidecar)")
    ap.add_argument("--log", default=None, help="append stdout and stderr to this file (the game passes it: a sidecar "
                    "started by the game has nowhere else to report, and a silent one is undiagnosable)")
    a = ap.parse_args()
    if a.log:
        try:
            os.makedirs(os.path.dirname(os.path.abspath(a.log)), exist_ok=True)
            f = open(a.log, "a", buffering=1)
            os.dup2(f.fileno(), sys.stdout.fileno())
            os.dup2(f.fileno(), sys.stderr.fileno())
        except OSError as e:
            print(f"[tile_service] cannot write {a.log}: {e}", flush=True)
        print(f"[tile_service] --- started {time.strftime('%Y-%m-%d %H:%M:%S')} ---", flush=True)
    try:
        os.nice(10)   # the game's frames come first; not on Windows
    except (AttributeError, OSError):
        pass
    if a.parent_pid:
        threading.Thread(target=watch_parent, args=(a.parent_pid,), daemon=True).start()
    if a.raw_dir:
        os.environ["VAKURAAMAT_RAW_DIR"] = os.path.abspath(a.raw_dir)
    WORKSPACE = os.path.abspath(a.workspace) if a.workspace else os.path.join(paths.raw_root(), "service")
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
