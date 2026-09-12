#!/usr/bin/env python3
"""Local tile service: turns a point in a covered country into a playable site pack plus its terrain tile.
What differs per country - the agency, the download estimate, the register stages, the refine pass, the
address search - is the country's adapter in tools/pipeline/sources.py; nothing here names one.

    python3 tools/tile_service.py [--port 8765] [--workspace data_raw/service] [--raw-dir data_raw]

The game (scripts/autoload/locator.gd) talks to it:
    GET  /health                     -> {"ok": true}
    GET  /geocode?q=<text>[&country=<id>] -> [{"name", "x", "y"}]      (every country's address search, or one's)
    GET  /geocode_lv?q=<text>        -> the same as /geocode?country=lv (the name older games ask for)
    GET  /estimate?x=&y=&size=       -> what a pack for the point would download (HEAD requests to the
                                        geoportal for each DTM and nDSM sheet, cached ones marked), the
                                        service's measured rate and the mean job time: {"items", "bytes",
                                        "cached_bytes", "rate_bps", "seconds_download", "seconds_process", "free_bytes"}
    GET  /cache                      -> the service workspace: {"bytes", "packs", "free_bytes", "path"}
    POST /tile  {"id","name","x","y","size","eras","seed","blocks"} -> 202 {"id"}   starts a job (or reuses a cached zip)
    GET  /status?id=<id>             -> {"stage","progress","done","error"}   (error "cancelled" after /cancel)
    POST /cancel?id=<id>             -> 202: the job stops at its next stage or download chunk
    GET  /packs                      -> [{"id","name","x","y","size","eras","seed","blocks"}]  packs ready in the cache
    GET  /download?id=<id>           -> zip with site/<pack files> and tile/<engine files>
A job runs the same tools as `make site` + `make tile`, in a workspace outside the repo, with the
download cache shared (data_raw/, or --raw-dir). Needs python3 with numpy, Pillow, rasterio, pyogrio, shapely and pyproj;
the same script frozen with tools/service/build.sh ships beside the exported game as the tile_service sidecar.
Nothing here is exposed beyond the loopback interface unless you bind it so.
"""
import argparse, concurrent.futures, functools, time, json, os, re, shutil, sys, threading, traceback, urllib.parse, urllib.request, zipfile
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
import new_site, gen_era_scenes, extract_features  # noqa: E402
import fetch_tile, validate_site, sources  # noqa: E402
MIN_FREE_BYTES = 2 * 1024 ** 3   # a job needs raw sheets, the workspace and the zip: refuse under 2 GB
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


class Cancelled(Exception):
    """The client cancelled the job (POST /cancel): raised at its next stage or download chunk."""


def with_deadline(name, seconds, fn, *args, job=None, **kwargs):
    """Run an optional stage with a hard time budget. A stage that reaches national services can
    stall for minutes on a slow feed (the notices XML has a 180 s socket timeout, twice); the pack
    must not wait for it. On timeout the worker is abandoned to finish or die on its own and the
    job carries on without that layer. With `job`, a cancel is noticed within a second the same way,
    and raises Cancelled rather than carrying on. Returns (ok, result)."""
    ex = concurrent.futures.ThreadPoolExecutor(max_workers=1)   # not a with-block: shutdown must not wait
    fut = ex.submit(fn, *args, **kwargs)
    deadline = time.time() + seconds
    try:
        while True:
            try:
                return True, fut.result(timeout=max(0.0, min(1.0, deadline - time.time())))
            except concurrent.futures.TimeoutError:
                if job is not None and job.get("cancel"):
                    raise Cancelled() from None
                if time.time() >= deadline:
                    log(f"{name}: still running after {seconds} s; the pack goes without it")
                    return False, None
    except Cancelled:
        raise
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
    """What a pack for (x, y) downloads, each item with its size (HEAD) and whether data_raw already
    holds it - the country's adapter lists them (sources.py: Estonia's DTM and nDSM sheets and
    orthophoto, Latvia's laser sheets) - and how long that, the job and the refine pass should take."""
    raw_dir = paths.raw_root()
    half = size / 2
    items = []
    refine = sources.for_point(x, y).estimate((x - half, y - half, x + half, y + half), raw_dir, items, head_size)
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


def run_job(job):
    sid = job["id"]
    ws = os.path.join(WORKSPACE, sid)
    started = time.time()

    marks = []   # (seconds since the job started, stage name): printed as a breakdown when it is ready

    def stage(name, frac):
        # every stage and every download chunk (fetch_tile.PROGRESS below) passes here, so a cancel
        # stops the job at its next step, a download mid-file
        if job.get("cancel"):
            raise Cancelled()
        with LOCK:
            job["stage"] = name; job["progress"] = frac
        marks.append((time.time() - started, name))
        log(f"{sid}: {name} [{time.time() - started:.0f} s]")

    run = functools.partial(with_deadline, job=job)   # the time-boxed runner, cancellable
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
        source = sources.for_point(job["x"], job["y"])   # the country's adapter: its agency, registers, refine pass
        stage("scaffold", 0.05)
        new_site.scaffold(sid, job["name"], (job["x"], job["y"]), job["size"], job["eras"], tile=sid,
                          force=True, root=ws, texture_mode="path", seed=job.get("seed"), block_ids=job.get("blocks"))
        stage(f"{source.label} data", 0.1)

        def on_progress(frac, text):   # the fetcher's steps become the job's stage
            stage(f"{source.label}: " + text, 0.1 + 0.35 * float(frac))
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
        # the country's registers: cadastre, buildings, companies, roads, stops (sources.py); the
        # timetables come in the refine pass
        stops_thread = source.registers(sid, ws, stage, run)
        # a tile on a border: the neighbour's registers for its side
        stage("the other side of the border", 0.66)
        import cross_border
        run(f"{sid}: across the border", 900, cross_border.complete, sid, root=ws)
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
    except Cancelled:
        # the half-built workspace goes; what was downloaded stays in the raw cache, so going there
        # again starts from it
        log(f"{sid}: cancelled [{time.time() - started:.0f} s]")
        shutil.rmtree(ws, ignore_errors=True)
        with LOCK:
            job.update(stage="cancelled", done=True, error="cancelled")
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
        # the country's own pass (sources.py): Estonia's 1 m ground, measured trees and timetables,
        # Latvia's older photographs and timetables; (ok, the ground's resolution in metres)
        ok, res = sources.for_point(job["x"], job["y"]).refine(sid, ws, rstage, with_deadline)
        rstage("packing")
        write_zip(sid, ws)
        if ok:
            open(os.path.join(WORKSPACE, sid + ".refined"), "w").close()   # JOBS is memory only; this survives a restart
        with LOCK:
            job.update(refined=True, refine_stage="ready", ground_res_m=res)
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
        if u.path in ("/geocode", "/geocode_lv"):
            # every country's address search (sources.py), or one's with ?country=<id>; /geocode_lv is
            # Latvia's under the name games from before the descriptors ask for
            q = qs.get("q", [""])[0].strip()
            if not q:
                return self._json(400, {"error": "q missing"}) if u.path == "/geocode" else self._json(200, [])
            only = "lv" if u.path == "/geocode_lv" else qs.get("country", [""])[0]
            out = []
            for s in sources.SOURCES:
                if only and s.id != only:
                    continue
                try:
                    out += s.geocode(q)
                except Exception as e:  # noqa: BLE001 - one country's search down is not the others'
                    log(f"geocode: {s.name} unavailable ({e})")
            return self._json(200, out)
        if u.path == "/estimate":
            try:
                x, y = float(qs.get("x", [""])[0]), float(qs.get("y", [""])[0])
                size = int(qs.get("size", ["1024"])[0])
            except ValueError:
                return self._json(400, {"error": "need x and y (EPSG:3301)"})
            if country_of(x, y) is None:
                return self._json(400, {"error": "outside every country the service covers (tools/pipeline/sources.py --list)"})
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
        if u.path == "/cancel":
            sid = urllib.parse.parse_qs(u.query).get("id", [""])[0]
            with LOCK:
                job = JOBS.get(sid)
                if not job or job.get("done"):
                    return self._json(404, {"error": "no running job"})
                job["cancel"] = True   # run_job raises Cancelled at its next stage or download chunk
            return self._json(202, {"id": sid, "stage": "cancelling"})
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
