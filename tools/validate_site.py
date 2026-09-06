#!/usr/bin/env python3
"""Checks a site pack (sites/<site>/) for broken references before Godot ever sees it.

    python3 tools/validate_site.py [--site palupera] [--all]

Pure python. Errors (exit 1) are things the game would trip over: missing files, unknown
era/item/consequence ids, undefined translation keys, ink knots that do not exist.
Warnings are for things that are probably unintended but not fatal.
"""
import argparse, csv, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))


class Report:
    def __init__(self):
        self.errors = []; self.warnings = []

    def err(self, msg): self.errors.append(msg)
    def warn(self, msg): self.warnings.append(msg)


def read_tres(path):
    """Very small .tres reader: the [resource] section's key = value pairs, plus the script path."""
    props = {}
    text = open(path, encoding="utf-8").read()
    m = re.search(r'\[ext_resource type="Script" path="([^"]+)"', text)
    props["_script"] = m.group(1) if m else ""
    body = text.split("[resource]", 1)[1] if "[resource]" in text else ""
    for line in body.splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip(); v = v.strip()
        if v.startswith('"') and v.endswith('"'):
            props[k] = v[1:-1]
        elif v.startswith("Array[String]("):
            props[k] = re.findall(r'"([^"]*)"', v)
        elif v.startswith("{"):
            props[k] = dict(re.findall(r'"([^"]+)":\s*([-\d.]+)', v))
        else:
            props[k] = v
    return props


def load_dir(site_dir, sub, rep):
    out = {}
    d = os.path.join(site_dir, "data", sub)
    if not os.path.isdir(d):
        return out
    for f in sorted(os.listdir(d)):
        if f.endswith(".tres"):
            r = read_tres(os.path.join(d, f))
            if "id" not in r:
                rep.err(f"data/{sub}/{f}: no id"); continue
            if r["id"] in out:
                rep.err(f"data/{sub}/{f}: duplicate id {r['id']}")
            out[r["id"]] = r
    return out


def read_strings(path, rep, label):
    keys = set()
    if not os.path.exists(path):
        return keys
    rows = list(csv.reader(open(path, newline="", encoding="utf-8")))
    if not rows or rows[0][:1] != ["keys"]:
        rep.err(f"{label}: first row must start with 'keys'")
    for r in rows[1:]:
        if not r or not r[0].strip():
            continue
        if r[0] in keys:
            rep.warn(f"{label}: duplicate key {r[0]}")
        if len(r) < 3 or not r[1].strip() or not r[2].strip():
            rep.warn(f"{label}: {r[0]} lacks an et or en text")
        keys.add(r[0])
    return keys


def validate(site, rep, root=ROOT):
    site_dir = os.path.join(root, "sites", site)
    mpath = os.path.join(site_dir, "site.json")
    if not os.path.exists(mpath):
        rep.err(f"{site}: no site.json"); return
    try:
        m = json.load(open(mpath))
    except json.JSONDecodeError as e:
        rep.err(f"site.json: {e}"); return
    if m.get("id") != site:
        rep.err(f"site.json id {m.get('id')!r} != directory name {site!r}")
    core_keys = read_strings(os.path.join(ROOT, "assets/i18n/strings.csv"), rep, "core strings")
    site_keys = read_strings(os.path.join(site_dir, "strings.csv"), rep, "strings.csv")
    clash = core_keys & site_keys
    if clash:
        rep.warn(f"strings.csv redefines core keys: {sorted(clash)[:5]}")
    keys = core_keys | site_keys

    def key(k, where):
        if k and k not in keys:
            rep.err(f"{where}: translation key {k!r} not in strings.csv")

    # --- terrain / start
    t = m.get("terrain", {})
    for k in ("tile", "center", "size"):
        if k not in t:
            rep.err(f"site.json terrain.{k} missing")
    if isinstance(t.get("center"), list) and len(t["center"]) == 2:
        x, y = t["center"]
        if not (300000 < x < 800000 and 6300000 < y < 6700000):
            rep.warn("terrain.center does not look like EPSG:3301 metres inside Estonia")
    tile_dir = os.path.join(root, "assets/terrain", str(t.get("tile", site)))
    if not os.path.exists(os.path.join(tile_dir, "terrain_meta.json")):
        rep.warn(f"terrain tile not fetched yet: {tile_dir} (make tile SITE={site})")
    elif not os.path.exists(os.path.join(tile_dir, "data", "terrain3d_00_00.res")):
        rep.warn(f"terrain region data not built: make tile SITE={site}")
    key(m.get("name_key"), "site.json name_key")
    key(m.get("subtitle_key"), "site.json subtitle_key")

    # --- registries
    eras = load_dir(site_dir, "eras", rep)
    structures = load_dir(site_dir, "structures", rep)
    if not eras:
        rep.err("no eras in data/eras")
    elif len(eras) != 1:
        rep.err(f"data/eras must hold exactly one present-day layer, found {sorted(eras)}")

    def era(e, where):
        if e and e not in eras:
            rep.err(f"{where}: unknown era {e!r}")

    spec = None
    spath = os.path.join(site_dir, "scenes.json")
    if os.path.exists(spath):
        try:
            spec = json.load(open(spath))
        except json.JSONDecodeError as e:
            rep.err(f"scenes.json: {e}")
    for eid, e in eras.items():
        key(e.get("display_name_key"), f"era {eid}")
        sp = e.get("scene_path", "")
        if not (sp.startswith(f"res://sites/{site}/scenes/") or sp.startswith(f"user://sites/{site}/scenes/")):
            rep.warn(f"era {eid}: scene_path {sp!r} is outside the site pack")
        if not os.path.exists(os.path.join(root, sp.replace("res://", "").replace("user://", ""))) and not (spec and eid in spec.get("eras", {})):
            rep.err(f"era {eid}: scene {sp} missing and scenes.json does not define it (make scenes)")
    for sid, st in structures.items():
        key(st.get("display_name_key"), f"structure {sid}"); key(st.get("description_key"), f"structure {sid}")
        if st.get("requires") and st["requires"] not in structures:
            rep.err(f"structure {sid}: requires unknown structure {st['requires']!r}")
    if not os.path.exists(os.path.join(site_dir, "parcels.json")):
        rep.err("parcels.json missing (make parcels): the ledger has nothing to sell")

    # --- manifest rules
    start = m.get("start", {})
    era(start.get("era"), "site.json start.era")
    if not (isinstance(start.get("spawn"), list) and len(start["spawn"]) == 2):
        rep.err("site.json start.spawn must be [x, z]")
    layout = {}
    lpath = os.path.join(site_dir, "layout.json")
    if os.path.exists(lpath):
        layout = json.load(open(lpath))
    else:
        rep.err("layout.json missing")
    for loc_key, lk in m.get("locations", {}).items():
        key(loc_key, "site.json locations")
        if lk not in layout:
            rep.err(f"site.json locations: layout key {lk!r} not in layout.json")
    for k in m.get("codex", []):
        key(k, "site.json codex"); key(k + "_TITLE", "site.json codex")
    if m.get("water") and not os.path.exists(os.path.join(site_dir, m["water"])):
        rep.warn(f"water file {m['water']} missing (make features)")

    # --- economy data: parcels with land values, the market snapshot
    def load_json(name, required):
        path = os.path.join(site_dir, name)
        if not os.path.exists(path):
            return None
        try:
            d = json.load(open(path))
        except (json.JSONDecodeError, OSError) as e:
            rep.err(f"{name}: {e}"); return None
        for k in required:
            if k not in d:
                rep.err(f"{name}: missing top-level key {k!r}"); return None
        return d
    parcels = load_json("parcels.json", ("parcels",))
    if parcels:
        units = parcels["parcels"]
        for u in units:
            lv = u.get("land_value")
            if lv is not None and not isinstance(lv, (int, float)):
                rep.err(f"parcels.json {u.get('tunnus')}: land_value must be a number or null")
        if units and not any(u.get("land_value") for u in units):
            rep.warn("parcels.json has no land_value: re-run make parcels")
    buildings = load_json("buildings.json", ("buildings",))
    tunnus_set = {u.get("tunnus") for u in parcels["parcels"]} if parcels else set()
    building_ids = {b.get("id") for b in buildings["buildings"]} if buildings else set()
    tenants = load_json("tenants.json", ("attribution", "source", "fetched", "tenants"))
    if tenants:
        for t in tenants["tenants"]:
            who = f"tenants.json {t.get('registry_code')}"
            if not (str(t.get("registry_code") or "").isdigit() and t.get("name")):
                rep.err(f"{who}: needs a numeric registry_code and a name")
            if t.get("match") not in ("exact", "street", "none"):
                rep.err(f"{who}: match must be exact, street or none")
            if t.get("tunnus") is not None and t["tunnus"] not in tunnus_set:
                rep.err(f"{who}: tunnus {t['tunnus']!r} not in parcels.json")
            if t.get("building_id") is not None and t["building_id"] not in building_ids:
                rep.err(f"{who}: building_id {t['building_id']!r} not in buildings.json")
            if t.get("match") == "exact" and t.get("tunnus") is None and t.get("building_id") is None:
                rep.err(f"{who}: exact match without a parcel or building")
            if str(t.get("legal_form") or "").startswith("Füüsilisest isikust"):
                rep.err(f"{who}: sole proprietor (a private person) in tenants.json")
            # the register's people files are used as structure only: no names, contacts or ids of persons
            for k in ("eesnimi", "nimi_arinimi", "email", "phone", "isikukood", "board_names", "members"):
                if k in t:
                    rep.err(f"{who}: must not store {k}")
            for k, v in t.items():
                if isinstance(v, str) and (re.search(r"[\w.+-]+@[\w-]+\.[\w.]+", v) or re.search(r"\+372\s?\d{6,}", v)):
                    rep.err(f"{who}: {k} looks like a contact ({v[:30]})")
            for h in t.get("owners") or []:
                if not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|\d{6,}", str(h)):
                    rep.err(f"{who}: owners must be register hashes, got {str(h)[:20]!r}")
            if t.get("health") not in (None, "sound", "watch", "distressed"):
                rep.err(f"{who}: health must be sound, watch or distressed")
            if t.get("sector") not in (None, "farm", "industry", "construction", "trade", "transport", "hospitality", "media", "finance",
                                       "property", "services", "public", "culture"):
                rep.err(f"{who}: unknown sector {t.get('sector')!r}")
        if tenants["tenants"] and not any(t.get("match") == "exact" for t in tenants["tenants"]):
            rep.warn("tenants.json: no tenant matched a parcel or building")
    news = load_json("news.json", ("events",))
    if news:
        for e in news["events"]:
            if not (e.get("id") and e.get("kind") in ("news", "official", "macro") and e.get("title") and e.get("url")):
                rep.err(f"news.json {e.get('id')}: needs id, kind news|official|macro, title and url")
            for k in ("avaldaja", "andmeandja", "adressaat", "kinnitatud_sisu", "body", "description"):
                if k in e:
                    rep.err(f"news.json {e.get('id')}: must not store {k}")
    market = load_json("market.json", ("by_purpose", "source"))
    if market:
        if not market["by_purpose"]:
            rep.warn("market.json: by_purpose is empty")
        for k, v in market["by_purpose"].items():
            if not (isinstance(v, dict) and isinstance(v.get("median_eur_m2"), (int, float)) and v["median_eur_m2"] >= 0 and isinstance(v.get("n"), int) and v["n"] >= 1):
                rep.err(f"market.json by_purpose {k}: needs median_eur_m2 >= 0 and n >= 1")

    # --- scenes.json semantics
    if spec:
        try:
            import gen_era_scenes as gen
        except ImportError as e:
            rep.err(f"cannot import gen_era_scenes: {e}"); return
        it = gen.Interpreter(site_dir, spec, layout)
        allowed = {"group", "use", "repeat", "instance", "building", "box", "torus", "examine", "tree", "scatter", "traffic", "bicycle",
                   "roads", "parcels", "footprints", "village"}
        for eid in spec.get("eras", {}):
            era(eid, "scenes.json eras")
        for eid, body in spec.get("eras", {}).items():
            it.build(eid, body.get("nodes", []))

            def walk(nodes):
                for n in nodes:
                    t = n.get("type")
                    if t not in allowed:
                        rep.err(f"scenes.json {eid}: node type {t!r} is not part of the present-day game (allowed: {sorted(allowed)})")
                    elif t == "examine":
                        for k in ("key", "loc", "label"):
                            v = n.get(k, "")
                            if "{" not in v:
                                key(v, f"scenes.json {eid} examine {n.get('name')}")
                    elif t in ("group", "repeat"):
                        if n.get("flag"):
                            rep.err(f"scenes.json {eid}: group {n.get('name')} still carries a consequence flag")
                        walk(n.get("children", []))
                    elif t == "use":
                        walk(spec.get("fragments", {}).get(n.get("fragment"), {}).get("nodes", []))
            walk(body.get("nodes", []))
        for p in it.problems:
            rep.err(f"scenes.json: {p}")
    else:
        rep.warn("no scenes.json: the layer scene must be hand-made")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", default="palupera")
    ap.add_argument("--all", action="store_true", help="validate every site under sites/")
    ap.add_argument("--root", default=ROOT, help="project root holding sites/ (default: the repo)")
    a = ap.parse_args()
    sites = sorted(d for d in os.listdir(os.path.join(a.root, "sites")) if os.path.exists(os.path.join(a.root, "sites", d, "site.json"))) if a.all else [a.site]
    failed = False
    for s in sites:
        rep = Report()
        validate(s, rep, a.root)
        for w in rep.warnings:
            print(f"[{s}] warning: {w}")
        for e in rep.errors:
            print(f"[{s}] ERROR: {e}")
        print(f"[{s}] {'FAILED' if rep.errors else 'OK'}: {len(rep.errors)} errors, {len(rep.warnings)} warnings")
        failed = failed or bool(rep.errors)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
