#!/usr/bin/env python3
"""Tiles on the Estonian-Latvian border (docs/latvia-plan.md, step 7): a pack is built by the country
its centre lies in, and that country's registers stop at the border, so a tile over Valga and Valka
would show one town and an empty field where the other stands. This runs the other country's
register fetchers for the same tile and merges in what lies on that country's side.

    python3 tools/pipeline/cross_border.py --site t620139_6405171

What is merged, each row kept only when its centre lies inside the other country's outline
(assets/data/estonia.json, latvia.json):
  parcels.json    the other cadastre's units (Maa-amet's WFS, or VZD's)
  buildings.json  the other register's buildings (ETAK + EHR + Maa-amet LOD2, or VZD + laser roofs)
  tenants.json    the other business register's companies matched exactly to those units or buildings
  roads.json      only for an Estonian pack: ETAK stops at the border, so OpenStreetMap's roads on the
                  Latvian side are added (a Latvian pack's roads are OpenStreetMap's on both sides)
The ground needs nothing: LĢIA's laser sheets reach about a kilometre into Estonia (Valga's centre
included), and a Latvian pack's ground comes from them; an Estonian pack's DTM holes over Latvia are
filled as any other NoData. The pack keeps its own `country`; rows say theirs by their shape (a
Latvian building's 14-digit designation, a parcel's `tunnus`), which is what the building sheet reads.
"""
import argparse, json, os, shutil, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402

MIN_SHARE = 0.01     # the other country's share of the tile below which nothing is fetched


def log(msg):
    print(f"[cross_border] {msg}", flush=True)


_OUTLINES = {}


def outline(country):
    """The country's land (shapely, L-EST97) from its adapter's outline file, or None."""
    if country not in _OUTLINES:
        import sources
        _OUTLINES[country] = sources.by_id(country).land()
    return _OUTLINES[country]


def share(meta, country):
    """The fraction of the tile inside a country's outline."""
    from shapely.geometry import box
    land = outline(country)
    if land is None:
        return 0.0
    t = box(meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"])
    return t.intersection(land).area / t.area


def _on_side(rows, meta, land, key=lambda r: (r.get("x"), r.get("z"))):
    """The rows whose tile position (x east, z south) lies inside `land`."""
    from shapely import contains_xy
    import numpy as np
    pts = [key(r) for r in rows]
    ok = [p[0] is not None and p[1] is not None for p in pts]
    xs = np.array([meta["xmin"] + (p[0] if o else 0) for p, o in zip(pts, ok)], dtype=float)
    ys = np.array([meta["ymax"] - (p[1] if o else 0) for p, o in zip(pts, ok)], dtype=float)
    inside = contains_xy(land, xs, ys) if len(rows) else []
    return [r for r, o, i in zip(rows, ok, inside) if o and i]


def _mid(r):
    pts = r.get("points") or []
    if not pts:
        return (None, None)
    p = pts[len(pts) // 2]
    return (p[0], p[1])


def _load(path, key):
    return json.load(open(path)).get(key, []) if os.path.exists(path) else []


def complete(site, root=paths.ROOT):
    """Merge the other country's rows into a pack on the border. Returns what was added, or {}."""
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tile = m["terrain"]["tile"]
    tdir = os.path.join(root, "assets", "terrain", tile)
    meta = json.load(open(os.path.join(tdir, "terrain_meta.json")))
    import sources
    mine = m.get("country") or "ee"
    # the neighbour holding most of the tile (one on a tile over three countries: the largest)
    near = sorted(((share(meta, s.id), s) for s in sources.SOURCES if s.id != mine and s.outline), key=lambda p: -p[0])
    if not near or near[0][0] < MIN_SHARE:
        return {}
    part, src = near[0]
    other = src.id
    log(f"{site}: {part:.0%} of the tile lies in {src.name}; fetching its registers")
    land = outline(other)
    # the other country's fetchers write whole files, so they run in a scratch copy of the pack with
    # the tile's ground linked in
    tmp = tempfile.mkdtemp(prefix=f"xb_{site}_", dir=paths.raw("service") if os.path.isdir(paths.raw("service")) else None)
    try:
        os.makedirs(os.path.join(tmp, "sites", site))
        os.makedirs(os.path.join(tmp, "assets", "terrain"))
        os.symlink(tdir, os.path.join(tmp, "assets", "terrain", tile))
        m2 = dict(m, country=other)
        json.dump(m2, open(os.path.join(tmp, "sites", site, "site.json"), "w"))
        added = {}
        try:
            src.border(site, tmp)
        except (Exception, SystemExit) as e:  # noqa: BLE001 - the pack stands on its own side without them
            log(f"{site}: the other side's registers failed ({e}); the pack keeps its own")
            return {}
        tsite = os.path.join(tmp, "sites", site)
        # --- parcels and buildings on the other side
        for name, key, ident in (("parcels.json", "parcels", "tunnus"), ("buildings.json", "buildings", "id")):
            path = os.path.join(site_dir, name)
            if not os.path.exists(os.path.join(tsite, name)) or not os.path.exists(path):
                continue
            doc = json.load(open(path))
            have = {r.get(ident) for r in doc.get(key, [])}
            theirs = [r for r in _on_side(_load(os.path.join(tsite, name), key), meta, land) if r.get(ident) not in have]
            doc[key] = doc.get(key, []) + theirs
            other_doc = json.load(open(os.path.join(tsite, name)))
            doc["attribution"] = _merge_attr(doc.get("attribution"), other_doc.get("attribution"))
            if key == "parcels":
                s = doc.setdefault("summary", {})
                s["ehak"] = sorted(set(s.get("ehak") or []) | set((other_doc.get("summary") or {}).get("ehak") or []))
                s["municipalities"] = sorted(set(s.get("municipalities") or []) | set((other_doc.get("summary") or {}).get("municipalities") or []))
            json.dump(doc, open(path, "w"), ensure_ascii=False, separators=(",", ":") if key == "buildings" else None)
            added[key] = len(theirs)
        # --- the other register's companies on those parcels and buildings
        parcels = {u["tunnus"] for u in _load(os.path.join(site_dir, "parcels.json"), "parcels")}
        bids = {b["id"] for b in _load(os.path.join(site_dir, "buildings.json"), "buildings")}
        tpath = os.path.join(site_dir, "tenants.json")
        if os.path.exists(os.path.join(tsite, "tenants.json")):
            doc = json.load(open(tpath)) if os.path.exists(tpath) else {"attribution": "", "source": "", "fetched": "", "tenants": []}
            have = {t.get("registry_code") for t in doc["tenants"]}
            theirs = [t for t in _load(os.path.join(tsite, "tenants.json"), "tenants")
                      if t.get("match") == "exact" and t.get("registry_code") not in have
                      and (t.get("tunnus") in parcels or t.get("building_id") in bids)]
            for t in theirs:   # a unit or building the other side's fetch knew but this tile dropped
                if t.get("tunnus") not in parcels:
                    t["tunnus"] = None
                if t.get("building_id") not in bids:
                    t["building_id"] = None
            doc["tenants"] += [t for t in theirs if t.get("tunnus") or t.get("building_id")]
            doc["attribution"] = _merge_attr(doc.get("attribution"), json.load(open(os.path.join(tsite, "tenants.json"))).get("attribution"))
            json.dump(doc, open(tpath, "w"), ensure_ascii=False, indent=0)
            added["tenants"] = len(theirs)
        # --- a pack whose own roads end at the border (Estonia's ETAK): the neighbour's, where its
        # adapter has a source that crosses (Latvia's OpenStreetMap)
        try:
            road_credit = src.border_roads(site, tmp)
            if road_credit:
                rpath = os.path.join(site_dir, "roads.json")
                doc = json.load(open(rpath)) if os.path.exists(rpath) else {"attribution": "", "roads": []}
                theirs = _on_side(_load(os.path.join(tsite, "roads.json"), "roads"), meta, land, key=_mid)
                doc["roads"] = doc.get("roads", []) + theirs
                doc["attribution"] = _merge_attr(doc.get("attribution"), road_credit)
                json.dump(doc, open(rpath, "w"), ensure_ascii=False)
                added["roads"] = len(theirs)
        except Exception as e:  # noqa: BLE001
            log(f"{site}: the other side's roads unavailable ({e})")
        log(f"{site}: merged from the other side {added}")
        return added
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def _merge_attr(a, b):
    """Two attribution values, strings or {source: text} dicts, as one of the first's kind."""
    if isinstance(a, dict):
        out = dict(a)
        if isinstance(b, dict):
            out.update({k: v for k, v in b.items() if k not in out})
        elif b:
            out["other_side"] = b
        return out
    parts = [p for p in (a if isinstance(a, str) else "", b if isinstance(b, str) else "; ".join((b or {}).values())) if p]
    return "; ".join(dict.fromkeys(parts))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=paths.ROOT)
    a = ap.parse_args()
    complete(a.site, a.root)
