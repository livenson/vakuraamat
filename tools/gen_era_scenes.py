#!/usr/bin/env python3
"""Generates sites/<site>/scenes/<era>.tscn from sites/<site>/scenes.json and layout.json.

    python3 tools/gen_era_scenes.py [--site palupera] [--check]

The era scenes are plain Godot text scenes and can be inspected in the editor; re-running
this script overwrites them, so keep authored changes in scenes.json or layout.json.
Positions are tile metres (x east, z south); children sit at y = 0 and EraController
drops them onto the terrain at activation.

scenes.json
-----------
{
  "colors":    {"darkwood": [0.30, 0.22, 0.14], ...},          named RGB triples
  "fragments": {"oak": {"params": ["scale", "year"], "nodes": [...]}},  reusable blocks
  "eras":      {"era_2026": {"nodes": [...]}, ...}             one entry per EraDefinition id
}
Every node is an object with a "type" (see PRIMITIVES below) and a "name". Numbers may be
expression strings evaluated with the layout keys as variables ("manor[0] - manor_size[0]/2",
"i * 4.5"), text may interpolate parameters ("EX_OAK_{year}"). "at" is a layout key
("manor"), a pair [x, z] or an object {"ref": "manor", "offset": [dx, dz]}; inside a group it
is relative to the group. Rotations "yaw" are radians (yaw_deg for degrees).

PRIMITIVES
  group        name at [flag visible_when min_chapter lift children]   Conditional Node3D
  instance     name scene [scale yaw yaw_deg]                            any PackedScene
  building     name model [yaw yaw_deg footprint=[w,h,d] scale skirt]    glb + collider, tags the group's footprint
  box          name size y color [at rot]        torus  name inner outer color [y]
  examine      name key [loc label at]           story_point  name knot speaker text [loc label radius]
  npc          name id knot label color at [height yaw pose]
  pickup       name item examine at              register  name [at text]  (the vakuraamat itself)
  tree         name at scale [yaw scene]         repeat    count var children   (var is i by default)
  scatter      prefix count radius scale=[min,max] [seed scene]           random trees in a disc
  farm_plots   at count seeds                    trade_post  at key color
  manor_site   id at                             hunting     [max_animals]
  village      source                            massing boxes from a buildings json (x z w d h color)
  roads        [source]                         ETAK roads/paths as terrain ribbons (roads.json)
  traffic      [year density max_agents]        ambient walkers/cyclists/cars/carts on the roads
  bicycle      name at                          a parked bicycle the player can ride
  parcels      [source year]                     cadastral units -> kits by assets/data/parcel_rules.json
  footprints   source [year include_undated respect_exclusions]  real ETAK/EHR footprints built <= year;
                                                 buildings inside layout exclusion circles are skipped
  use          fragment with={param: value}
"""
import argparse, json, math, os, random, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "pipeline"))
import paths  # noqa: E402
ROOT = paths.ROOT   # the bundle directory when frozen into the tile-service sidecar
DARKWOOD = (0.30, 0.22, 0.14)
SKIRT = (0.42, 0.38, 0.32)


def color(c):
    return "Color(%.3f, %.3f, %.3f, 1)" % tuple(c)



def stripe_rows(ortho_path, size_m, polygon):
    """Regular rows in the orthophoto inside a parcel (solar parks, orchards, greenhouses): returns
    (period_m, row_angle_deg) when a strong periodic pattern with a 3-20 m period exists, else None.
    row_angle is the direction the rows run, degrees from +x (east) towards +z (south)."""
    try:
        import numpy as np
        from PIL import Image, ImageDraw
    except ImportError:
        return None
    if not ortho_path or not os.path.exists(ortho_path):
        return None
    key = ("ortho", ortho_path)
    img = stripe_rows.cache.get(key)
    if img is None:
        img = np.asarray(Image.open(ortho_path).convert("L"), dtype=np.float32)
        stripe_rows.cache[key] = img
    px = img.shape[0] / float(size_m)
    poly = [(p[0] * px, p[1] * px) for p in polygon]
    mask_img = Image.new("L", img.shape[::-1], 0)
    ImageDraw.Draw(mask_img).polygon(poly, fill=255)
    mask = np.asarray(mask_img) > 0
    if mask.sum() < 200:
        return None
    ys, xs = np.where(mask)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    m = mask[y0:y1, x0:x1]
    patch = img[y0:y1, x0:x1].copy()
    patch -= patch[m].mean()
    patch[~m] = 0.0
    spec = np.abs(np.fft.fftshift(np.fft.fft2(patch)))
    h, w = spec.shape
    yy, xx = np.mgrid[0:h, 0:w]
    fy = (yy - h // 2) / float(h)
    fx = (xx - w // 2) / float(w)
    freq = np.hypot(fx, fy)
    with np.errstate(divide="ignore"):
        period = np.where(freq > 0, 1.0 / (freq * px + 1e-9), 0.0)
    band = (period > 3.0) & (period < 20.0)
    if not band.any():
        return None
    peak_i = np.unravel_index(np.argmax(np.where(band, spec, 0.0)), spec.shape)
    peak = spec[peak_i]
    median = float(np.median(spec[band]))
    if median <= 0 or peak / median < 25.0:
        return None
    freq_angle = math.degrees(math.atan2(fy[peak_i], fx[peak_i]))
    return float(period[peak_i]), freq_angle + 90.0


stripe_rows.cache = {}


class Scene:
    """Text-scene writer: external/sub resources and a flat node list with parent paths."""

    def __init__(self, era):
        self.era = era; self.ext = []; self.sub = []; self.nodes = []; self.ext_ids = {}; self._sub_n = 0

    def ext_res(self, typ, path):
        if path in self.ext_ids:
            return self.ext_ids[path]
        i = len(self.ext) + 1
        self.ext.append(f'[ext_resource type="{typ}" path="{path}" id="{i}"]'); self.ext_ids[path] = i
        return i

    def sub_res(self, typ, body, prefix):
        self._sub_n += 1
        sid = f"{prefix}{self._sub_n}"
        self.sub.append(f'[sub_resource type="{typ}" id="{sid}"]\n{body}')
        return f'SubResource("{sid}")'

    def mat(self, c, rough=0.9):
        return self.sub_res("StandardMaterial3D", f"albedo_color = {color(c)}\nroughness = {rough}", "M")

    def node(self, name, typ, parent, props="", instance=None):
        head = f'[node name="{name}" ' + (f'type="{typ}" ' if typ else '') + f'parent="{parent}"' + (f' instance=ExtResource("{instance}")' if instance else '') + ']'
        self.nodes.append(head + ("\n" + props if props else ""))

    @staticmethod
    def xf(x, z, yaw=0.0, scale=1.0, y=0.0):
        cy = math.cos(yaw) * scale; sy = math.sin(yaw) * scale
        return f'transform = Transform3D({cy:.4f}, 0, {sy:.4f}, 0, {scale}, 0, {-sy:.4f}, 0, {cy:.4f}, {x}, {y}, {z})'

    def group(self, name, parent, x, z, lift=0.0):
        props = self.xf(x, z)
        if lift:
            props += f"\nmetadata/lift = {lift}"
        self.node(name, "Node3D", parent, props)
    def box(self, name, parent, size, y_center, c, x=0, z=0, rot=0):
        m = self.mat(c)
        self.node(name, "CSGBox3D", parent, f'{self.xf(x, z, rot, 1.0, y_center)}\nsize = Vector3({size[0]}, {size[1]}, {size[2]})\nmaterial = {m}')

    def torus(self, name, parent, inner, outer, c, y=0.0):
        m = self.mat(c)
        self.node(name, "CSGTorus3D", parent, f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {y}, 0)\ninner_radius = {inner}\nouter_radius = {outer}\nsides = 12\nring_sides = 6\nmaterial = {m}')

    def examine(self, name, parent, key, loc="", label="", x=0, z=0):
        i = self.ext_res("PackedScene", "res://scenes/props/examine_point.tscn")
        p = f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0, {z})\ntext_key = "{key}"'
        if loc: p += f'\nlocation_id = "{loc}"'
        if label: p += f'\nlabel_key = "{label}"'
        self.node(name, None, parent, p, instance=i)

    def tree(self, name, parent, x, z, scale, yaw=0.0, scene="res://assets/vegetation/tree_juniper.tscn"):
        i = self.ext_res("PackedScene", scene)
        self.node(name, None, parent, self.xf(x, z, yaw, scale), instance=i)

    def instance(self, name, parent, path, props=""):
        i = self.ext_res("PackedScene", path)
        self.node(name, None, parent, props, instance=i)

    def collider(self, parent, shape_ref, y, layer=2):
        self.node("Body3D", "StaticBody3D", parent, f"collision_layer = {layer}\ncollision_mask = 0")
        self.node("Shape", "CollisionShape3D", f"{parent}/Body3D", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {y}, 0)\nshape = {shape_ref}')

    def building(self, name, parent, path, yaw=0.0, footprint=None, scale=1.0, skirt=True):
        """A glb building at the parent's origin; optional box collider (w, h, d) so the player can't walk through.
        The parent group gets metadata/footprint so EraController snaps it to the LOWEST corner, and a
        foundation skirt fills the gap on the uphill side."""
        self.instance(name, parent, path, self.xf(0, 0, yaw, scale))
        if footprint:
            w, h, d = footprint
            self.footprint(parent, w, d)
            if skirt:
                self.box(f"{name}Skirt", parent, (w - 0.2, 3.0, d - 0.2), -1.5, SKIRT)
            shape = self.sub_res("BoxShape3D", f"size = Vector3({w}, {h}, {d})", f"BS_{self.era}_")
            self.node(f"{name}Body", "StaticBody3D", parent, "collision_layer = 1\ncollision_mask = 0")
            self.node("Shape", "CollisionShape3D", f"{parent}/{name}Body", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {h / 2}, 0)\nshape = {shape}')

    def footprint(self, parent, w, d):
        """Tag the group node so EraController samples the whole footprint when snapping."""
        for i, n in enumerate(self.nodes):
            if n.startswith(f'[node name="{parent.split("/")[-1]}" ') and 'metadata/footprint' not in n:
                self.nodes[i] = n + f'\nmetadata/footprint = Vector2({w}, {d})'
                return

    def mesh_box(self, name, parent, size, y_center, c):
        """A BoxMesh instance: cheaper than CSG when there are hundreds (village massing)."""
        mesh = self.sub_res("BoxMesh", f"size = Vector3({size[0]}, {size[1]}, {size[2]})", "BM")
        m = self.mat(c)
        self.node(name, "MeshInstance3D", parent, f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {y_center}, 0)\nmesh = {mesh}\nsurface_material_override/0 = {m}')

    def footprints(self, buildings, year, include_undated, source_rel="buildings.json", exclusions=()):
        """Real footprints (sites/<id>/buildings.json from ETAK + EHR): one FootprintBuilding per building
        whose first year of use is <= year (undated ones only when include_undated). The node reads the
        LOD2 roof model at runtime from the pack's buildings.json by id."""
        sc = self.ext_res("Script", "res://scripts/world/footprint_building.gd")
        self.group("Buildings", ".", 0, 0)
        n = 0
        for b in buildings:
            y = b.get("year")
            if (y is None and not include_undated) or (y is not None and year is not None and y > year):
                continue
            if str(b.get("status") or "").endswith("LAMMUTATUD"):
                continue
            if any(math.hypot(b["x"] - e[0], b["z"] - e[1]) < float(e[2]) + max(b["w"], b["d"]) / 2 for e in exclusions):
                continue   # hand-placed content (manor, farm...) stands here
            pts = ", ".join(f"{p[0] - b['x']:.2f}, {p[1] - b['z']:.2f}" for p in b["polygon"])
            c = b.get("wall_color") or b.get("color", [0.6, 0.6, 0.58])
            rc = b.get("roof_color") or [k * 0.45 for k in c]
            name = f"B{b.get('id', n)}"
            self.group(name, "Buildings", b["x"], b["z"])
            self.footprint(f"Buildings/{name}", b["w"], b["d"])
            extras = ""
            if b.get("chimney"):
                extras += "\nchimney = true"
            if b.get("solar") and year is not None and year >= 2005:
                extras += "\nsolar = true"
            if b.get("well"):
                extras += "\nwell = true"
            kind = "ruin" if str(b.get("type") or "") == "Vare" else b.get("kind", "dwelling")
            mats = b.get("materials") or {}
            extras += f'\nkind = "{kind}"\nfloors = {int(b.get("floors") or 0)}\nfacade = "{(mats.get("facade") or mats.get("wall_type") or "").replace(chr(34), "")}"\nroof_cover = "{(mats.get("roof_cover") or "").replace(chr(34), "")}"'
            q = lambda v: str(v or "").replace(chr(34), "").replace("\n", " ")  # noqa: E731
            extras += f'\nehr = "{q(b.get("ehr"))}"\naddress = "{q(b.get("address"))}"\npurpose = "{q(b.get("purpose"))}"\nyear = {int(b.get("year") or 0)}\ntunnus = "{q((b.get("cadastral") or [None])[0])}"'
            self.node("Footprint", "Node3D", f"Buildings/{name}", f'script = ExtResource("{sc}")\npolygon = PackedVector2Array({pts})\nheight = {b["h"]}\nwall_color = {color(c)}\nroof_color = {color(rc)}\nsource = "{source_rel}"\nbuilding_id = {b.get("id", 0)}{extras}')
            n += 1
        return n

    def traffic(self, year, density=1.0, max_agents=40):
        """Ambient walkers, cyclists, cars (or carts) on the road graph (scripts/world/traffic_system.gd)."""
        sc = self.ext_res("Script", "res://scripts/world/traffic_system.gd")
        self.node("Traffic", "Node3D", ".", f'script = ExtResource("{sc}")\nyear = {int(year)}\ndensity = {density}\nmax_agents = {int(max_agents)}\nmetadata/no_snap = true')

    def bicycle(self, name, x, z):
        """A parked bicycle the player can ride (scripts/interaction/bicycle.gd)."""
        sc = self.ext_res("Script", "res://scripts/interaction/bicycle.gd")
        self.node(name, "Node3D", ".", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0, {z})\nscript = ExtResource("{sc}")')

    def roads(self, source_rel="roads.json"):
        """ETAK roads drawn on the terrain at runtime (scripts/world/road_network.gd)."""
        sc = self.ext_res("Script", "res://scripts/world/road_network.gd")
        self.node("Roads", "Node3D", ".", f'script = ExtResource("{sc}")\nsource = "{source_rel}"\nmetadata/no_snap = true')

    def parcels(self, units, rules, year, exclusions=(), ortho_path=None, size_m=1024):
        """Cadastral units -> kits by assets/data/parcel_rules.json (first matching rule; kit null = nothing).
        A rule with "needs_rows" only matches when the orthophoto shows regular rows on the unit
        (solar parks); the kit then gets row_period and row_angle."""
        sc = self.ext_res("Script", "res://scripts/world/parcel_kit.gd")
        self.group("Parcels", ".", 0, 0)
        n = 0
        for u in units:
            purposes = u.get("purpose") or []
            kit = None
            rows = None
            matched = {}
            for r in rules:
                if r.get("purpose") and not any(p in r["purpose"] for p in purposes):
                    continue
                area = float(u.get("area") or 0)
                if "min_area" in r and area < r["min_area"]:
                    continue
                if "max_area" in r and area > r["max_area"]:
                    continue
                if r.get("ownership") and u.get("ownership") not in r["ownership"]:
                    continue
                if r.get("tunnus") and u.get("tunnus") not in r["tunnus"]:
                    continue
                if year is not None and (("from_year" in r and year < r["from_year"]) or ("until_year" in r and year > r["until_year"])):
                    continue
                if r.get("needs_rows"):
                    rows = stripe_rows(ortho_path, size_m, u["polygon"])
                    if rows is None:
                        continue
                kit = r.get("kit")
                matched = r
                break
            if not kit:
                continue
            if any(math.hypot(u["x"] - e[0], u["z"] - e[1]) < float(e[2]) + 10 for e in exclusions):
                continue
            pts = ", ".join(f"{p[0] - u['x']:.1f}, {p[1] - u['z']:.1f}" for p in u["polygon"])
            name = "P" + str(u.get("tunnus", n)).replace(":", "_")
            self.group(name, "Parcels", u["x"], u["z"])
            extra = f"\nrow_period = {rows[0]:.2f}\nrow_angle = {rows[1]:.1f}" if rows else ""
            if matched.get("at"):   # a pinned spot for the kit, tile metres, and a heading in degrees from north
                extra += f"\nanchor = Vector2({float(matched['at'][0]) - u['x']:.1f}, {float(matched['at'][1]) - u['z']:.1f})\nanchor_yaw = {float(matched.get('yaw', 0.0)):.1f}"
            self.node("Kit", "Node3D", f"Parcels/{name}", f'script = ExtResource("{sc}")\nkit = "{kit}"\ntunnus = "{u.get("tunnus", "")}"\npolygon = PackedVector2Array({pts}){extra}')
            n += 1
        return n

    def village(self, buildings):
        """Real building footprints (from the nDSM) as simple massing boxes."""
        self.group("Village", ".", 0, 0)
        for i, b in enumerate(buildings):
            self.group(f"B{i}", "Village", b["x"], b["z"])
            self.footprint(f"Village/B{i}", b["w"], b["d"])
            self.mesh_box("Mass", f"Village/B{i}", (b["w"], b["h"] + 3.0, b["d"]), b["h"] / 2 - 1.5, tuple(min(1.0, k * 0.9) for k in b["color"]))
            self.mesh_box("Roof", f"Village/B{i}", (b["w"] + 0.6, 0.25, b["d"] + 0.6), b["h"] + 0.12, tuple(k * 0.6 for k in b["color"]))

    def write(self, path):
        sc = self.ext_res("Script", "res://scripts/era/era_controller.gd")
        root = f'[node name="{self.era}" type="Node3D"]\nscript = ExtResource("{sc}")\nera_id = "{self.era}"'
        out = f'[gd_scene load_steps={len(self.ext) + len(self.sub) + 1} format=3]\n\n' + "\n".join(self.ext) + "\n\n" + "\n\n".join(self.sub) + "\n\n" + root + "\n\n" + "\n\n".join(self.nodes) + "\n"
        open(path, "w").write(out)


class Interpreter:
    """Turns the scenes.json node lists into Scene calls."""

    def __init__(self, site_dir, spec, layout):
        self.site_dir = site_dir; self.spec = spec; self.layout = layout
        self.colors = {k: tuple(v) for k, v in spec.get("colors", {}).items()}
        self.fragments = spec.get("fragments", {})
        self.base_env = {k: (list(v) if isinstance(v, list) else v) for k, v in layout.items() if k not in ("exclusions", "pads")}
        self.base_env.update({n: getattr(math, n) for n in ("pi", "tau", "cos", "sin", "sqrt", "radians")})
        self.problems = []

    def manifest(self):
        try:
            return json.load(open(os.path.join(self.site_dir, "site.json")))
        except (OSError, ValueError):
            return {}

    def tile_size(self):
        return int(self.manifest().get("terrain", {}).get("size", 1024))

    def ortho_path(self):
        """The tile's orthophoto (assets/terrain/<tile>/ortho.jpg next to the sites/ root), if fetched."""
        tile = self.manifest().get("terrain", {}).get("tile") or os.path.basename(self.site_dir)
        root = os.path.dirname(os.path.dirname(self.site_dir))
        p = os.path.join(root, "assets", "terrain", tile, "ortho.jpg")
        return p if os.path.exists(p) else None

    # --- values --------------------------------------------------------------
    def num(self, v, env, default=None):
        if v is None:
            return default
        if isinstance(v, str):
            try:
                return eval(v, {"__builtins__": {}}, env)
            except Exception as e:
                self.problems.append(f"bad expression {v!r}: {e}"); return default if default is not None else 0.0
        return v

    def nums(self, seq, env):
        return [self.num(v, env) for v in seq]

    def txt(self, v, env):
        if isinstance(v, str) and "{" in v:
            try:
                return v.format_map(env)
            except KeyError as e:
                self.problems.append(f"unknown parameter {e} in {v!r}"); return v
        return v

    def col(self, v, env):
        if isinstance(v, str):
            if v in self.colors:
                return self.colors[v]
            self.problems.append(f"unknown color {v!r}"); return (1.0, 0.0, 1.0)
        return tuple(self.nums(v, env))

    def pos(self, at, env, default=(0.0, 0.0)):
        """Layout key, [x, z] or {"ref": key, "offset": [dx, dz]} -> (x, z)."""
        if at is None:
            return default
        if isinstance(at, str):
            if at not in self.layout:
                self.problems.append(f"unknown layout key {at!r}"); return default
            return tuple(self.layout[at][:2])
        if isinstance(at, dict):
            x, z = self.pos(at.get("ref"), env)
            dx, dz = self.nums(at.get("offset", [0, 0]), env)
            return (x + dx, z + dz)
        return tuple(self.nums(at, env))

    def yaw(self, n, env):
        if "yaw_deg" in n:
            return math.radians(self.num(n["yaw_deg"], env))
        return self.num(n.get("yaw", 0.0), env)

    # --- nodes ---------------------------------------------------------------
    def build(self, era, nodes):
        s = Scene(era)
        self.emit(s, ".", nodes, dict(self.base_env, era=era))
        return s

    def emit(self, s, parent, nodes, env):
        for n in nodes:
            t = n.get("type")
            name = self.txt(n.get("name", ""), env)
            child_path = name if parent == "." else f"{parent}/{name}"
            if t == "group":
                x, z = self.pos(n.get("at"), env)
                s.group(name, parent, x, z, self.num(n.get("lift", 0.0), env))
                self.emit(s, child_path, n.get("children", []), env)
            elif t == "use":
                frag = self.fragments.get(n.get("fragment"))
                if frag is None:
                    self.problems.append(f"unknown fragment {n.get('fragment')!r}"); continue
                sub = dict(env); sub.update(n.get("with", {}))   # parameters: numbers, or text for {name} interpolation
                self.emit(s, parent, frag.get("nodes", []), sub)
            elif t == "repeat":
                var = n.get("var", "i")
                for i in range(int(self.num(n.get("count", 0), env))):
                    sub = dict(env); sub[var] = i
                    self.emit(s, parent, n.get("children", []), sub)
            elif t == "instance":
                x, z = self.pos(n.get("at"), env)
                s.instance(name, parent, n["scene"], Scene.xf(x, z, self.yaw(n, env), self.num(n.get("scale", 1.0), env)))
            elif t == "building":
                fp = n.get("footprint")
                s.building(name, parent, n["model"], self.yaw(n, env), tuple(self.nums(fp, env)) if fp else None, self.num(n.get("scale", 1.0), env), n.get("skirt", True))
            elif t == "box":
                x, z = self.pos(n.get("at"), env)
                s.box(name, parent, self.nums(n["size"], env), self.num(n.get("y", 0.0), env), self.col(n["color"], env), x, z, self.num(n.get("rot", 0.0), env))
            elif t == "torus":
                s.torus(name, parent, self.num(n["inner"], env), self.num(n["outer"], env), self.col(n["color"], env), self.num(n.get("y", 0.0), env))
            elif t == "examine":
                x, z = self.pos(n.get("at"), env)
                s.examine(name, parent, self.txt(n["key"], env), self.txt(n.get("loc", ""), env), self.txt(n.get("label", ""), env), x, z)
            elif t == "tree":
                x, z = self.pos(n.get("at"), env)
                s.tree(name, parent, x, z, self.num(n.get("scale", 1.0), env), self.yaw(n, env), n.get("scene", "res://assets/vegetation/tree_juniper.tscn"))
            elif t == "scatter":
                rng = random.Random(int(n.get("seed", 1798)))
                r_max = self.num(n.get("radius", 40.0), env); smin, smax = self.nums(n.get("scale", [0.4, 0.7]), env)
                for i in range(int(self.num(n.get("count", 10), env))):
                    a = rng.random() * math.tau; r = rng.random() ** 0.5 * r_max
                    s.tree(f"{n.get('prefix', 'Tree')}{i}", parent, round(math.cos(a) * r, 1), round(math.sin(a) * r, 1), round(rng.uniform(smin, smax), 2), rng.random() * 6.28, n.get("scene", "res://assets/vegetation/tree_juniper.tscn"))
            elif t == "traffic":
                if os.path.exists(os.path.join(self.site_dir, "roads.json")):
                    s.traffic(self.num(n.get("year", 2026), env), self.num(n.get("density", 1.0), env), self.num(n.get("max_agents", 40), env))
            elif t == "bicycle":
                x, z = self.pos(n.get("at"), env)
                s.bicycle(name or "Bicycle", x, z)
            elif t == "roads":
                if os.path.exists(os.path.join(self.site_dir, n.get("source", "roads.json"))):
                    s.roads(n.get("source", "roads.json"))
            elif t == "parcels":
                src = os.path.join(self.site_dir, n.get("source", "parcels.json"))
                rules_path = os.path.join(self.site_dir, "parcel_rules.json")
                if not os.path.exists(rules_path):
                    rules_path = os.path.join(ROOT, "assets/data/parcel_rules.json")
                if os.path.exists(src) and os.path.exists(rules_path):
                    units = json.load(open(src)).get("parcels", [])
                    rules_doc = json.load(open(rules_path))
                    rules = rules_doc.get("rules", [])
                    if rules_doc.get("extend_global"):   # a pack's own rules first, then the shared ones
                        rules = rules + json.load(open(os.path.join(ROOT, "assets/data/parcel_rules.json"))).get("rules", [])
                    year = self.num(n.get("year"), env) if n.get("year") is not None else None
                    s.parcels(units, rules, int(year) if year is not None else None, self.layout.get("exclusions", []), self.ortho_path(), self.tile_size())
            elif t == "footprints":
                src = os.path.join(self.site_dir, n.get("source", "buildings.json"))
                if os.path.exists(src):
                    data = json.load(open(src))
                    blist = data.get("buildings", data) if isinstance(data, dict) else data
                    year = self.num(n.get("year"), env) if n.get("year") is not None else None
                    excl = self.layout.get("exclusions", []) if n.get("respect_exclusions", True) else []
                    s.footprints(blist, int(year) if year is not None else None, bool(n.get("include_undated", False)), n.get("source", "buildings.json"), excl)
                else:
                    self.problems.append(f"footprints source missing: {src}")
            elif t == "village":
                src = os.path.join(self.site_dir, n.get("source", "buildings_2026.json"))
                if os.path.exists(src):
                    s.village(json.load(open(src)))
                else:
                    self.problems.append(f"village source missing: {src}")
            else:
                self.problems.append(f"unknown node type {t!r} ({name})")


def generate(site, check=False, root=ROOT):
    site_dir = os.path.join(root, "sites", site)
    spec = json.load(open(os.path.join(site_dir, "scenes.json")))
    layout = json.load(open(os.path.join(site_dir, "layout.json")))
    it = Interpreter(site_dir, spec, layout)
    out_dir = os.path.join(site_dir, "scenes")
    os.makedirs(out_dir, exist_ok=True)
    for era, body in spec.get("eras", {}).items():
        s = it.build(era, body.get("nodes", []))
        if not check:
            s.write(os.path.join(out_dir, f"{era}.tscn")); print("wrote", site, era, f"({len(s.nodes)} nodes)")
    for p in it.problems:
        print("problem:", p)
    return not it.problems


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Generate era scenes from a site's scenes.json")
    ap.add_argument("--site", default="palupera")
    ap.add_argument("--check", action="store_true", help="only report problems, write nothing")
    ap.add_argument("--root", default=ROOT, help="project root holding sites/ (default: the repo)")
    a = ap.parse_args()
    sys.exit(0 if generate(a.site, a.check, a.root) else 1)
