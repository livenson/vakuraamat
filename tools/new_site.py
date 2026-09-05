#!/usr/bin/env python3
"""Scaffolds a new location/story pack under sites/<id>/ and keeps its era ground maps linked.

    python3 tools/new_site.py --id kvissentali --name "Kvissentali" --center 657600 6477150
        [--size 1024] [--eras 1798,1938,2026] [--template palupera] [--force]
    python3 tools/new_site.py --id kvissentali --relink-era-maps

What you get: site.json (terrain centre, latitude/longitude, eras' historical map layers, start,
objectives, ending), layout.json (named spots around the tile centre), scenes.json (a register,
one NPC per era, one artifact whose delivery leaves a visible trace in every later era, a trade
post, farm plots, hunting, village massing), data/ (eras, one consequence point, the artifact,
and the template site's farming/hunting/trading/building content with era ids remapped),
narrative/<era>.ink (Estonian lines with '# en:' tags) and strings.csv. Everything is meant
to be rewritten; it is a working skeleton that passes validate_site.py and boots.

Then: make tile SITE=<id>   (fetch Maa-amet data, build terrain, era maps, buildings, water, scenes)
      make ink; make validate; godot --path . -- --site=<id>
"""
import argparse, csv, json, math, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------- EPSG:3301 (L-EST97) -> WGS84
A_GRS80 = 6378137.0
F_GRS80 = 1.0 / 298.257222101
LAT1, LAT2, LAT0, LON0, X0, Y0 = 59.33333333333334, 58.0, 57.51755393055556, 24.0, 500000.0, 6375000.0


def lest97_to_wgs84(x, y):
    """Inverse Lambert conformal conic (2SP) with GRS80, the Estonian national grid."""
    e = math.sqrt(2 * F_GRS80 - F_GRS80 ** 2)
    def m(phi): return math.cos(phi) / math.sqrt(1 - (e * math.sin(phi)) ** 2)
    def t(phi): return math.tan(math.pi / 4 - phi / 2) / ((1 - e * math.sin(phi)) / (1 + e * math.sin(phi))) ** (e / 2)
    p1, p2, p0 = map(math.radians, (LAT1, LAT2, LAT0))
    n = (math.log(m(p1)) - math.log(m(p2))) / (math.log(t(p1)) - math.log(t(p2)))
    F = m(p1) / (n * t(p1) ** n)
    r0 = A_GRS80 * F * t(p0) ** n
    dx, dy = x - X0, r0 - (y - Y0)
    r = math.copysign(math.hypot(dx, dy), n)
    tt = (r / (A_GRS80 * F)) ** (1 / n)
    lon = math.atan2(dx, dy) / n + math.radians(LON0)
    phi = math.pi / 2 - 2 * math.atan(tt)
    for _ in range(8):
        phi = math.pi / 2 - 2 * math.atan(tt * ((1 - e * math.sin(phi)) / (1 + e * math.sin(phi))) ** (e / 2))
    return round(math.degrees(phi), 5), round(math.degrees(lon), 5)


# ---------------------------------------------------------------- era ground maps (Maa-amet historical WMS)
def era_map_for(year):
    """(WMS layer, file stem, texture strength, tint) for an era's ground drape, or None for the orthophoto."""
    if year < 1923:
        return "yheverstakaart", "verst", 0.45, (0.93, 0.88, 0.72)        # one-verst map 1894-1922
    if year < 1945:
        return "kk1940", "cadastral", 0.4, (1.0, 0.97, 0.9)                # schematic cadastral map 1930-1944
    if year < 1991:
        return "nltopo_c63_10T", "soviet10k", 0.4, (0.95, 0.95, 0.9)      # Soviet 1:10 000 topographic map
    if year < 2005:
        return "vanaBaaskaart", "baaskaart", 0.4, (0.97, 0.97, 0.95)      # Estonian base map 1994-1998
    return None


def tres_header(script_path, texture_path=None):
    s = f'[gd_resource type="Resource" format=3]\n\n[ext_resource type="Script" path="{script_path}" id="1"]\n'
    if texture_path:
        s += f'[ext_resource type="Texture2D" path="{texture_path}" id="2"]\n'
    return s + "\n[resource]\nscript = ExtResource(\"1\")\n"


def q(s):
    return '"' + str(s).replace('"', '\\"') + '"'


def gd_array(items):
    return "Array[String]([" + ", ".join(q(i) for i in items) + "])"


def read_tres(path):
    props = {}
    text = open(path, encoding="utf-8").read()
    m = re.search(r'\[ext_resource type="Script" path="([^"]+)"', text)
    props["_script"] = m.group(1) if m else ""
    body = text.split("[resource]", 1)[1] if "[resource]" in text else ""
    for line in body.splitlines():
        if "=" in line and not line.startswith("script"):
            k, v = line.split("=", 1)
            props[k.strip()] = v.strip()
    return props


def write_tres(path, script_path, props, texture_path=None):
    out = tres_header(script_path, texture_path)
    for k, v in props.items():
        if k.startswith("_"):
            continue
        out += f"{k} = {v}\n"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(out)


def unquote(v):
    return v[1:-1] if v.startswith('"') and v.endswith('"') else v


def era_texture(tile, era_id, year, tile_dir, texture_mode="import"):
    """Texture path + strength + tint for an era's ground drape: the fetched historical map if present,
    else the orthophoto if fetched, else None (no drape until make tile / make era-maps).
    texture_mode "import": res:// paths (Godot imports the image); "path": user://tiles paths loaded at runtime."""
    base = f"res://assets/terrain/{tile}" if texture_mode == "import" else f"user://tiles/{tile}"
    ortho = f"{base}/ortho.jpg" if os.path.exists(os.path.join(tile_dir, "ortho.jpg")) else None
    em = era_map_for(year)
    if em:
        layer, stem, strength, tint = em
        fname = f"{era_id}_{stem}.png"
        if os.path.exists(os.path.join(tile_dir, fname)):
            return f"{base}/{fname}", strength, tint
        return ortho, 0.6, (0.9, 0.86, 0.75)   # placeholder until make era-maps
    return ortho, 1.0, (1.0, 1.0, 1.0)


def set_texture(props, tex, texture_mode):
    """Point an era's props at its ground texture: an ext_resource for imported images, a path otherwise."""
    props.pop("terrain_texture", None); props.pop("terrain_texture_path", None)
    if not tex:
        return None
    if texture_mode == "import":
        props["terrain_texture"] = 'ExtResource("2")'
        return tex
    props["terrain_texture_path"] = q(tex)
    return None


def relink_era_maps(site, root=ROOT, texture_mode="import"):
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tile = m["terrain"]["tile"]
    tile_dir = os.path.join(root, "assets/terrain", tile)
    eras_dir = os.path.join(site_dir, "data/eras")
    for f in sorted(os.listdir(eras_dir)):
        if not f.endswith(".tres"):
            continue
        p = os.path.join(eras_dir, f)
        props = read_tres(p)
        era_id = unquote(props["id"]); year = int(re.sub(r"\D", "", unquote(props.get("year_label", "0"))) or 0)
        tex, strength, tint = era_texture(tile, era_id, year, tile_dir, texture_mode)
        props["texture_strength"] = str(strength)
        props["ground_tint"] = "Color(%s, %s, %s, 1)" % tint
        ext = set_texture(props, tex, texture_mode)
        write_tres(p, "res://scripts/era/era_definition.gd", props, ext)
        print(f"[new_site] {era_id}: ground texture {tex or '(none yet: make tile)'}")


# ---------------------------------------------------------------- scaffold
def anchor_layout(half, anchors=None):
    """Named spots for the story skeleton: from detected anchors (tile service) or a ring around the centre."""
    cx = cz = half
    a = {"spawn": [cx, cz + 20], "register": [cx, cz], "landmark": [cx + 40, cz - 30], "farm": [cx - 60, cz + 40],
         "trade": [cx + 30, cz + 30], "field": [cx + 80, cz + 90]}
    for k, v in (anchors or {}).items():
        if k in a and isinstance(v, list) and len(v) >= 2:
            a[k] = [round(float(v[0]), 1), round(float(v[1]), 1)]
    layout = dict(a)
    layout["exclusions"] = [[*a["register"], 6], [*a["landmark"], 6], [*a["farm"], 14], [*a["trade"], 4]]
    layout["pads"] = []
    return layout


def apply_anchors(site, anchors, root=ROOT):
    """Re-place a scaffolded pack's layout (and spawn) on detected anchors; rerun `make scenes` after."""
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    layout = anchor_layout(m["terrain"]["size"] / 2, anchors)
    json.dump(layout, open(os.path.join(site_dir, "layout.json"), "w"), indent=1)
    m["start"]["spawn"] = layout["spawn"]
    reg, sp = layout["register"], layout["spawn"]
    m["start"]["yaw_deg"] = round(math.degrees(math.atan2(-(reg[0] - sp[0]), -(reg[1] - sp[1]))) % 360, 1)   # face the register (0 = north)
    manor = os.path.join(site_dir, "data/manors/home_farm.tres")
    if os.path.exists(manor):
        props = read_tres(manor)
        props["position"] = "Vector2(%d, %d)" % (layout["farm"][0], layout["farm"][1])
        write_tres(manor, props["_script"], props)
    json.dump(m, open(os.path.join(site_dir, "site.json"), "w"), indent=2)
    return layout


def scaffold(site, name=None, center=None, size=1024, eras="1798,1938,2026", tile=None, template="palupera",
             force=False, root=ROOT, template_root=ROOT, texture_mode="import", anchors=None):
    if not re.fullmatch(r"[a-z][a-z0-9_]*", site):
        sys.exit("--id must be lowercase letters, digits, underscores")
    site_dir = os.path.join(root, "sites", site)
    if os.path.exists(site_dir) and not force:
        sys.exit(f"{site_dir} exists (use --force to overwrite the scaffold files)")
    tile = tile or site
    tile_dir = os.path.join(root, "assets/terrain", tile)
    years = sorted(int(y) for y in eras.split(","))
    eras = [f"era_{y}" for y in years]
    newest, oldest = eras[-1], eras[0]
    mid = eras[-2] if len(eras) > 1 else eras[0]
    lat, lon = lest97_to_wgs84(*center)
    half = size / 2
    pack = f"res://sites/{site}" if texture_mode == "import" else f"user://sites/{site}"   # where Godot will find the pack
    SITE_KEY = f"SITE_{site.upper()}"
    name = name or site.capitalize()
    strings = [["keys", "et", "en"], [SITE_KEY, name, name],
               [f"{SITE_KEY}_SUBTITLE", f"{name}: kolm aastat, sama maa.", f"{name}: three years, the same ground."]]

    def S(key, et, en):
        strings.append([key, et, en])

    # --- era maps + era resources ------------------------------------------------------------
    era_maps = {}
    for e, y in zip(eras, years):
        em = era_map_for(y)
        if em:
            era_maps[e] = {"layer": em[0], "file": f"{e}_{em[1]}.png"}
    os.makedirs(os.path.join(site_dir, "data/eras"), exist_ok=True)
    tods = [13.5, 9.5, 14.5]
    for i, (e, y) in enumerate(zip(eras, years)):
        tex, strength, tint = era_texture(tile, e, y, tile_dir, texture_mode)
        props = {
            "id": q(e), "display_name_key": q(f"ERA_{y}_NAME"), "year_label": q(str(y)), "scene_path": q(f"{pack}/scenes/{e}.tscn"),
            "texture_strength": str(strength), "ground_tint": "Color(%s, %s, %s, 1)" % tint,
            "default_time_of_day": str(tods[i % len(tods)]), "order": str(i), "narrative_story": q(f"{pack}/narrative/{e}.ink.json"),
            "currency_key": q(f"CUR_{y}"), "starting_money": str([12, 150, 2000][min(i, 2)]),
        }
        ext = set_texture(props, tex, texture_mode)
        write_tres(os.path.join(site_dir, f"data/eras/{e}.tres"), "res://scripts/era/era_definition.gd", props, ext)
        S(f"ERA_{y}_NAME", f"Aasta {y}", f"The year {y}")

    # --- gameplay content copied from the template, eras remapped by order ------------------------
    tmpl_dir = os.path.join(template_root, "sites", template)
    tmpl_strings = {}
    tp = os.path.join(tmpl_dir, "strings.csv")
    if os.path.exists(tp):
        for r in list(csv.reader(open(tp, newline="", encoding="utf-8")))[1:]:
            if r and r[0].strip():
                tmpl_strings[r[0]] = r
    tmpl_eras = []
    ted = os.path.join(tmpl_dir, "data/eras")
    if os.path.isdir(ted):
        tmpl_eras = sorted((int(read_tres(os.path.join(ted, f)).get("order", "0")), unquote(read_tres(os.path.join(ted, f))["id"]), read_tres(os.path.join(ted, f)))
                           for f in os.listdir(ted) if f.endswith(".tres"))
    era_map = {}
    for i, (_, tid, tprops) in enumerate(tmpl_eras):
        j = round(i * (len(eras) - 1) / max(len(tmpl_eras) - 1, 1)) if len(tmpl_eras) > 1 else len(eras) - 1
        era_map[tid] = eras[min(j, len(eras) - 1)]
    # currency texts follow the mapped template era
    for i, (_, tid, tprops) in enumerate(tmpl_eras):
        ck = unquote(tprops.get("currency_key", '""'))
        target = era_map[tid]; y = target[4:]
        if ck in tmpl_strings and not any(r[0] == f"CUR_{y}" for r in strings):
            S(f"CUR_{y}", tmpl_strings[ck][1], tmpl_strings[ck][2])
    for e, y in zip(eras, years):
        if not any(r[0] == f"CUR_{y}" for r in strings):
            S(f"CUR_{y}", "senti", "cents")

    needed_items = set(); used_keys = set()

    def remap_eras(v):
        ids = re.findall(r'"([^"]*)"', v)
        out = []
        for i in ids:
            n = era_map.get(i, i)
            if n not in out:
                out.append(n)
        return gd_array(out)

    def copy_dir(sub, fix):
        src = os.path.join(tmpl_dir, "data", sub)
        if not os.path.isdir(src):
            return
        for f in sorted(os.listdir(src)):
            if not f.endswith(".tres"):
                continue
            props = read_tres(os.path.join(src, f))
            name = fix(f, props)
            if name is None:
                continue
            for k in ("display_name_key", "description_key"):
                if k in props:
                    used_keys.add(unquote(props[k]))
            write_tres(os.path.join(site_dir, "data", sub, name), props["_script"], props)

    def fix_crop(f, p):
        p["eras"] = remap_eras(p.get("eras", "Array[String]([])")); needed_items.update(unquote(p.get("seed_item_id", '""')).split() + unquote(p.get("yield_item_id", '""')).split()); return f
    def fix_animal(f, p):
        p["eras"] = remap_eras(p.get("eras", "Array[String]([])")); needed_items.add(unquote(p.get("yield_item_id", '""'))); return f
    def fix_structure(f, p):
        needed_items.update(re.findall(r'"([^"]+)":', p.get("cost_items", "{}"))); return f
    seen_goods = set()
    def fix_good(f, p):
        old = unquote(p["era_id"]); new = era_map.get(old, eras[-1]); p["era_id"] = q(new)
        item = unquote(p["item_id"]); needed_items.add(item)
        key = (new, item)
        if key in seen_goods:
            return None
        seen_goods.add(key); return f"{new}_{item}.tres"
    copy_dir("crops", fix_crop); copy_dir("animals", fix_animal); copy_dir("structures", fix_structure); copy_dir("trade_goods", fix_good)
    isrc = os.path.join(tmpl_dir, "data/items")
    if os.path.isdir(isrc):
        for f in sorted(os.listdir(isrc)):
            if f.endswith(".tres"):
                p = read_tres(os.path.join(isrc, f))
                if unquote(p["id"]) in needed_items and not p["_script"].endswith("artifact_item.gd"):
                    used_keys.update(unquote(p[k]) for k in ("display_name_key", "description_key") if k in p)
                    write_tres(os.path.join(site_dir, "data/items", f), p["_script"], p)
    for k in sorted(used_keys):
        if k in tmpl_strings:
            strings.append(tmpl_strings[k])
    structures = sorted(unquote(read_tres(os.path.join(site_dir, "data/structures", f))["id"]) for f in os.listdir(os.path.join(site_dir, "data/structures"))) if os.path.isdir(os.path.join(site_dir, "data/structures")) else []
    crops_by_era = {}
    cdir = os.path.join(site_dir, "data/crops")
    if os.path.isdir(cdir):
        for f in os.listdir(cdir):
            p = read_tres(os.path.join(cdir, f))
            for e in re.findall(r'"([^"]*)"', p.get("eras", "")):
                crops_by_era.setdefault(e, []).append(unquote(p["seed_item_id"]))

    # --- the story block: one artifact, one consequence, a visible trace ---------------------------
    write_tres(os.path.join(site_dir, "data/consequence_points/cp1_keepsake_returned.tres"), "res://scripts/consequence/consequence_point.gd", {
        "id": q("cp1_keepsake_returned"), "flag_name": q("keepsake_returned"), "trigger_era": q(oldest),
        "affected_eras": gd_array(eras[1:]), "trigger_description_key": q("CP1_KEEPSAKE_TRIGGER"), "effect_description_key": q("CP1_KEEPSAKE_EFFECT")})
    write_tres(os.path.join(site_dir, "data/items/keepsake.tres"), "res://scripts/items/artifact_item.gd", {
        "id": q("keepsake"), "display_name_key": q("ITEM_KEEPSAKE"), "description_key": q("ITEM_KEEPSAKE_DESC"), "can_cross_eras": "true",
        "linked_consequence_point_id": q("cp1_keepsake_returned"), "valid_delivery_target": q(f"npc_{oldest}"), "origin_era": q(newest), "delivery_era": q(oldest)})
    layout = anchor_layout(half, anchors)
    write_tres(os.path.join(site_dir, "data/manors/home_farm.tres"), "res://scripts/base_building/manor_definition.gd", {
        "id": q("home_farm"), "display_name_key": q("MANOR_HOME"), "era_id": q(mid), "cadastral_parcel_id": q(""), "position": "Vector2(%d, %d)" % (layout["farm"][0], layout["farm"][1]),
        "unlock_condition_flag": q(""), "structures": gd_array(structures)})
    S("CP1_KEEPSAKE_TRIGGER", f"Sa andsid mälestuseseme tagasi aastal {years[0]}.", f"You returned the keepsake in {years[0]}.")
    S("CP1_KEEPSAKE_EFFECT", "Mälestusese jõudis koju. Hilisematel aastatel seisab maamärgi juures kivi.", "The keepsake came home. In the later years a stone stands by the landmark.")
    S("ITEM_KEEPSAKE", "Mälestusese", "Keepsake"); S("ITEM_KEEPSAKE_DESC", "Vana ese, mis ei kuulu sellesse aastasse.", "An old thing that does not belong to this year.")
    S("MANOR_HOME", "Kodutalu", "Home farm")
    S("LOC_LANDMARK", "Maamärk", "The landmark"); S("LOC_FARMSTEAD", "Talu", "The farmstead")
    S("ITEM_REGISTER", "Vakuraamat", "The register"); S("EX_REGISTER", "Raamat aastate vahel. Võta see.", "A book between the years. Take it.")
    S("NOTICE_REGISTER_FOUND", "Vakuraamat. Ava see (Tab) ja vali lehekülg.", "The register. Open it (Tab) and choose a page.")
    S("OBJ_FIND_REGISTER", "Leia raamat.", "Find the register."); S("OBJ_VISIT_ERAS", "Käi läbi kõik aastad.", "Visit every year.")
    S("OBJ_RETURN", f"Vii mälestusese aastasse {years[0]}.", f"Take the keepsake back to {years[0]}."); S("OBJ_SIT", f"Mine tagasi aastasse {years[-1]} ja räägi lõpuni.", f"Go back to {years[-1]} and finish the conversation.")
    S("ENDING_KEPT_TITLE", "Alles", "Kept"); S("ENDING_KEPT_TEXT", "Kivi seisab. Keegi mäletab.", "The stone stands. Somebody remembers.")
    S("ENDING_LOST_TITLE", "Kadunud", "Lost"); S("ENDING_LOST_TEXT", "Maa võttis omad tagasi. Lood jäid.", "The land took back its own. The stories stayed.")
    S("ENDING_KEPT", "Alles %d / %d", "Kept %d of %d")
    S("CODEX_REAL_TITLE", "Päris", "Real"); S("CODEX_REAL", f"Maa: {name}, Maa- ja Ruumiameti kõrgusandmed ja ortofoto.", f"The ground: {name}, from the Land Board's elevation data and orthophoto.")
    S("CODEX_INVENTED_TITLE", "Välja mõeldud", "Invented"); S("CODEX_INVENTED", "Inimesed ja lugu.", "The people and the story.")
    for e, y in zip(eras, years):
        S(f"NPC_{y}", f"Kohalik ({y})", f"A local ({y})")
        S(f"EX_LANDMARK_{y}", f"Maamärk aastal {y}.", f"The landmark in {y}.")
        S(f"EX_KEPT_{y}", "Kivi, mille keegi siia pani. Nimi on veel loetav.", "A stone somebody set here. The name is still legible.")
        S(f"POST_{y}", f"Pood ({y})", f"The shop ({y})"); S(f"POST_{y}_TEXT", "Ostetakse ja müüakse selle aasta raha eest.", "Buying and selling for this year's money.")

    # --- layout -----------------------------------------------------------------------------------
    json.dump(layout, open(os.path.join(site_dir, "layout.json"), "w"), indent=1)
    reg, sp = layout["register"], layout["spawn"]
    yaw = round(math.degrees(math.atan2(-(reg[0] - sp[0]), -(reg[1] - sp[1]))) % 360, 1)   # face the register (0 = north)

    # --- scenes -----------------------------------------------------------------------------------
    def era_nodes(e, y, i):
        nodes = [{"type": "npc", "name": f"Local{y}", "id": f"npc_{e}", "knot": "greeter", "label": f"NPC_{y}", "color": [0.4 + 0.1 * i, 0.35, 0.3], "at": {"ref": "register", "offset": [6, 4]}, "height": 1.7, "yaw": 2.6},
                 {"type": "group", "name": "Landmark", "at": "landmark", "children": [
                     {"type": "examine", "name": "LandmarkExamine", "key": f"EX_LANDMARK_{y}", "loc": "LOC_LANDMARK", "label": "LOC_LANDMARK"}]},
                 {"type": "trade_post", "at": "trade", "key": f"POST_{y}", "color": [0.7, 0.65, 0.5]}]
        if e != oldest:
            nodes.append({"type": "group", "name": "Kept", "at": "landmark", "flag": "keepsake_returned", "visible_when": True, "children": [
                {"type": "instance", "name": "Stone", "scene": "res://assets/models/props/boundary_stone.glb", "at": [3, 0], "yaw_deg": 20},
                {"type": "examine", "name": "KeptExamine", "key": f"EX_KEPT_{y}", "label": "LOC_LANDMARK", "at": [3, 0]}]})
        if e == newest:
            nodes.insert(0, {"type": "register", "name": "RegisterBook", "at": "register"})
            nodes.append({"type": "pickup", "name": "Keepsake", "item": "keepsake", "examine": "ITEM_KEEPSAKE_DESC", "at": {"ref": "register", "offset": [-4, 3]}})
            nodes.append({"type": "village", "source": "buildings_2026.json"})
        if e == mid:
            nodes.append({"type": "manor_site", "id": "home_farm", "at": "farm"})
        if crops_by_era.get(e):
            nodes.append({"type": "farm_plots", "at": {"ref": "farm", "offset": [8, 12]}, "count": 2, "seeds": crops_by_era[e][:3]})
        if i < len(eras) - 1:
            nodes.append({"type": "hunting", "max_animals": 6})
        return nodes
    scenes = {"colors": {"darkwood": [0.30, 0.22, 0.14], "stone": [0.55, 0.53, 0.50]}, "fragments": {},
              "eras": {e: {"nodes": era_nodes(e, y, i)} for i, (e, y) in enumerate(zip(eras, years))}}
    json.dump(scenes, open(os.path.join(site_dir, "scenes.json"), "w"), indent=1)

    # --- ink ---------------------------------------------------------------------------------------
    ext = "\n".join(f"EXTERNAL {d}" for d in ["flag(name)", "has_item(id)", "give_item(id, target)", "take_item(id)", "set_flag(name)", "end_chapter()", "chapter()", "trigger(cp_id)"]) + "\n-> END\n\n"
    os.makedirs(os.path.join(site_dir, "narrative"), exist_ok=True)
    for e, y in zip(eras, years):
        ink = ext + f"== greeter ==\n{{ not flag(\"met_{e}\"):\n    ~ set_flag(\"met_{e}\")\n    Sa ei ole siit. Aasta on {y}. # en: You're not from here. The year is {y}.\n- else:\n    Jälle sina. # en: You again.\n}}\n-> menu\n\n= menu\n"
        if e == oldest:
            ink += f"+ {{ has_item(\"keepsake\") and not flag(\"keepsake_returned\") }} [Anna mälestusese. %% Hand over the keepsake.]\n    ~ give_item(\"keepsake\", \"npc_{e}\")\n    Ta hoiab seda kaua käes. # en: They hold it for a long time.\n    {{ chapter() == 2:\n        ~ end_chapter()\n    }}\n    -> menu\n"
        else:
            ink += "+ { flag(\"keepsake_returned\") } [Kivi maamärgi juures. %% The stone by the landmark.]\n    Keegi pani selle sinna ammu. Nimi on veel peal. # en: Somebody set it there long ago. The name is still on it.\n    -> menu\n"
        if e == newest:
            ink += "+ { chapter() >= 3 and not flag(\"epilogue\") } [Räägime lõpuni. %% Let's finish the conversation.]\n    -> sit\n"
        ink += "+ [Mis koht see on? %% What is this place?]\n    Vaata ringi. Maa räägib ise. # en: Look around. The ground speaks for itself.\n    -> menu\n+ [Ma lähen. %% I'll go.]\n    Mine. # en: Go.\n    -> END\n"
        if e == newest:
            ink += "\n= sit\n~ set_flag(\"epilogue\")\n~ end_chapter()\nNoh. Räägime siis sellest, mis alles on. # en: Well. Let's talk about what's still here.\n-> END\n"
        open(os.path.join(site_dir, "narrative", f"{e}.ink"), "w", encoding="utf-8").write(ink)

    # --- manifest + strings ---------------------------------------------------------------------------
    manifest = {
        "id": site, "name_key": SITE_KEY, "subtitle_key": f"{SITE_KEY}_SUBTITLE",
        "description": f"{name}: scaffolded site pack. Replace the placeholder story.",
        "terrain": {"tile": tile, "center": [float(center[0]), float(center[1])], "size": size, "latitude": lat, "longitude": lon, "utc_offset": 3.0, "date": [2026, 9, 3], "era_maps": era_maps},
        "start": {"era": newest, "spawn": layout["spawn"], "yaw_deg": yaw},
        "water": "water_2026.json", "buildings": "buildings_2026.json",
        "locations": {"LOC_LANDMARK": "landmark", "LOC_FARMSTEAD": "farm"},
        "objectives": [
            {"when": "register_locked", "key": "OBJ_FIND_REGISTER", "target": "RegisterBook", "lift": 1.2},
            {"chapter": 1, "key": "OBJ_VISIT_ERAS"},
            {"chapter": 2, "key": "OBJ_RETURN", "target": f"Local{years[0]}", "era": oldest, "lift": 2.2},
            {"chapter": 3, "not_flag": "epilogue", "key": "OBJ_SIT", "target": f"Local{years[-1]}", "era": newest, "lift": 2.2}],
        "register_nudge": {"chapter": 1, "era": oldest},
        "ending": {"trigger_flag": "epilogue", "counted_flags": ["keepsake_returned"],
                   "tiers": [{"min_kept": 1, "key": "ENDING_KEPT_TEXT"}, {"key": "ENDING_LOST_TEXT"}]},
        "codex": ["CODEX_REAL", "CODEX_INVENTED"],
        "debug": {"build_node": "Manor_home_farm"},
    }
    # ending tier keys need <key>_TITLE: alias the titles
    S("ENDING_KEPT_TEXT_TITLE", "Alles", "Kept"); S("ENDING_LOST_TEXT_TITLE", "Kadunud", "Lost")
    json.dump(manifest, open(os.path.join(site_dir, "site.json"), "w"), indent=2)
    seen = set(); rows = []
    for r in strings:
        if r[0] not in seen:
            seen.add(r[0]); rows.append(r)
    with open(os.path.join(site_dir, "strings.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        for r in rows:
            w.writerow(r)
    for fn in ("buildings_2026.json", "water_2026.json"):
        p = os.path.join(site_dir, fn)
        if not os.path.exists(p):
            json.dump([], open(p, "w"))
    print(f"[new_site] {os.path.relpath(site_dir, root)}: eras {', '.join(eras)}; centre EPSG:3301 {center[0]:.0f} {center[1]:.0f} = {lat} N {lon} E")
    if root == ROOT:
        print(f"[new_site] next: make tile SITE={site}   (or make era-maps / make features / make scenes separately), make ink, make validate")
    return site_dir


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--id", required=True, help="site id: lowercase, becomes sites/<id>/")
    ap.add_argument("--name", help="display name (default: id capitalised)")
    ap.add_argument("--center", nargs=2, type=float, metavar=("X", "Y"), help="tile centre in EPSG:3301 (easting northing)")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--eras", default="1798,1938,2026", help="comma-separated years, default 1798,1938,2026")
    ap.add_argument("--tile", help="terrain tile name (default: the site id)")
    ap.add_argument("--template", default="palupera", help="site whose farming/hunting/trading/building content to copy")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--relink-era-maps", action="store_true", help="only re-point the era resources at fetched ground maps")
    ap.add_argument("--root", default=ROOT, help="project root holding sites/ and assets/terrain/ (default: the repo)")
    ap.add_argument("--texture-mode", choices=["import", "path"], default="import", help="era textures as imported res:// resources or runtime user:// paths")
    ap.add_argument("--anchors", help="anchors.json from extract_features.py to place the layout on")
    a = ap.parse_args()
    if a.relink_era_maps:
        relink_era_maps(a.id, a.root, a.texture_mode)
    else:
        if not a.center:
            sys.exit("--center X Y is required")
        anchors = json.load(open(a.anchors)) if a.anchors else None
        scaffold(a.id, a.name, a.center, a.size, a.eras, a.tile, a.template, a.force, a.root, ROOT, a.texture_mode, anchors)
