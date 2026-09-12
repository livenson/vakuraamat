#!/usr/bin/env python3
"""Latvian place and address search for the menu (the tile service's /geocode_lv), from the address
register's open data (VZD VARIS, `varis-atvertie-dati`, CC BY 4.0). Maa-amet's gazetteer only knows
Estonia, and OpenStreetMap's Nominatim forbids search-as-you-type, so the register is searched here.

    python3 tools/pipeline/geocode_lv.py "Doma laukums"

Two files:
  * `aw_vietu_centroidi.csv` (0.9 MB): every city, town, village, parish and municipality with its
    centre. Answers at once.
  * `aw_eka.csv` (141 MB): every building and parcel address with its point. Downloaded and indexed
    into an SQLite table the first time a search needs it, on a thread, so the first searches return
    places only; refreshed when older than 30 days.
Results are [{name, x, y}] on the L-EST97 grid, like Maa-amet's.
"""
import csv, json, os, sqlite3, sys, threading, time, unicodedata, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402

CKAN = "https://data.gov.lv/dati/api/3/action/package_show?id=varis-atvertie-dati"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
MAX_AGE = 30 * 86400
# the kinds of place, in the order a search shows them: state cities and towns, then villages,
# parishes, municipalities (TIPS_CD in the register)
PLACE_RANK = {"104": 0, "106": 1, "105": 2, "113": 3}

_places = None
_index_state = "none"     # none | building | ready | failed
_lock = threading.Lock()


def log(msg):
    print(f"[geocode_lv] {msg}", flush=True)


def fold(s):
    """Lower case without diacritics or quotes: "Rīga" and "riga", "Kaļķu" and "kalku" meet."""
    s = unicodedata.normalize("NFKD", str(s).lower())
    return " ".join("".join(c for c in s if not unicodedata.combining(c) and c not in "\"'").replace(",", " ").split())


def _url(suffix):
    res = json.load(urllib.request.urlopen(urllib.request.Request(CKAN, headers=UA), timeout=60))["result"]["resources"]
    return next(r["url"] for r in res if r["url"].endswith(suffix))


def _fresh(path):
    return os.path.exists(path) and time.time() - os.path.getmtime(path) < MAX_AGE


def _download(suffix, path):
    if not _fresh(path):
        log(f"downloading {suffix}")
        tmp = path + ".part"
        with urllib.request.urlopen(urllib.request.Request(_url(suffix), headers=UA), timeout=900) as r, open(tmp, "wb") as f:
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
        os.replace(tmp, path)
    return path


def _to_lest(lats, lons):
    from pyproj import Transformer
    t = Transformer.from_crs("EPSG:4326", "EPSG:3301", always_xy=True)
    return t.transform(lons, lats)


def places():
    """[(key, name, x, y, rank)] for every place in the register, read once."""
    global _places
    if _places is None:
        path = _download("aw_vietu_centroidi.csv", os.path.join(paths.raw("lv", "var"), "aw_vietu_centroidi.csv"))
        rows = [r for r in csv.DictReader(open(path, encoding="utf-8-sig")) if r.get("DD_N") and r.get("DD_E")]
        xs, ys = _to_lest([float(r["DD_N"]) for r in rows], [float(r["DD_E"]) for r in rows])
        _places = [(fold(r["STD"]), r["STD"], round(x), round(y), PLACE_RANK.get(r["TIPS_CD"], 9))
                   for r, x, y in zip(rows, xs, ys)]
    return _places


def _db_path():
    return os.path.join(paths.raw("lv", "var"), "addresses.sqlite")


def _build_index():
    global _index_state
    try:
        src = _download("aw_eka.csv", os.path.join(paths.raw("lv", "var"), "aw_eka.csv"))
        tmp = _db_path() + ".part"
        if os.path.exists(tmp):
            os.remove(tmp)
        db = sqlite3.connect(tmp)
        db.execute("CREATE TABLE a (key TEXT, name TEXT, x INTEGER, y INTEGER)")
        batch = []

        def flush():
            xs, ys = _to_lest([b[2] for b in batch], [b[3] for b in batch])
            db.executemany("INSERT INTO a VALUES (?, ?, ?, ?)", [(b[0], b[1], round(x), round(y)) for b, x, y in zip(batch, xs, ys)])
            batch.clear()
        n = 0
        with open(src, encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f):
                if r.get("STATUSS") != "EKS" or not r.get("DD_N") or not r.get("DD_E"):
                    continue
                batch.append((fold(r["STD"]), r["STD"], float(r["DD_N"]), float(r["DD_E"])))
                n += 1
                if len(batch) >= 50000:
                    flush()
        if batch:
            flush()
        db.commit()
        db.close()
        os.replace(tmp, _db_path())
        _index_state = "ready"
        log(f"address index: {n:,} addresses")
    except Exception as e:  # noqa: BLE001 - places still answer
        _index_state = "failed"
        log(f"address index failed: {e}")


def _ensure_index():
    """Start building the address index if it is missing or old; True when it can be queried."""
    global _index_state
    with _lock:
        if _index_state == "ready" or (_index_state == "none" and _fresh(_db_path())):
            _index_state = "ready"
            return True
        if _index_state in ("none", "failed"):
            _index_state = "building"
            threading.Thread(target=_build_index, daemon=True).start()
    return False


def search(q, limit=8):
    """Places first (towns before villages before parishes), then addresses, every word of the query
    in the name."""
    words = fold(q).split()
    if not words:
        return []
    hits = sorted((p for p in places() if all(w in p[0] for w in words)), key=lambda p: (p[4], len(p[1])))
    out = [{"name": p[1], "x": p[2], "y": p[3]} for p in hits[:limit]]
    if len(out) < limit and _ensure_index():
        db = sqlite3.connect(_db_path())
        try:
            sql = "SELECT name, x, y FROM a WHERE " + " AND ".join("key LIKE ?" for _ in words) + " ORDER BY length(name) LIMIT ?"
            for name, x, y in db.execute(sql, [f"%{w}%" for w in words] + [limit - len(out)]):
                out.append({"name": name, "x": x, "y": y})
        finally:
            db.close()
    return out


if __name__ == "__main__":
    q = " ".join(sys.argv[1:]) or "Doma laukums"
    r = search(q)
    if _index_state == "building":
        log("building the address index; waiting")
        while _index_state == "building":
            time.sleep(2)
        r = search(q)
    print(json.dumps(r, ensure_ascii=False, indent=1))
