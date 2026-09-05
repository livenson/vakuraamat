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
  pickup       name item examine at              register  name [at]     (the vakuraamat itself)
  tree         name at scale [yaw scene]         repeat    count var children   (var is i by default)
  scatter      prefix count radius scale=[min,max] [seed scene]           random trees in a disc
  farm_plots   at count seeds                    trade_post  at key color
  manor_site   id at                             hunting     [max_animals]
  village      source                            massing boxes from a buildings json (x z w d h color)
  use          fragment with={param: value}
"""
import argparse, json, math, os, random, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DARKWOOD = (0.30, 0.22, 0.14)
SKIRT = (0.42, 0.38, 0.32)


def color(c):
    return "Color(%.3f, %.3f, %.3f, 1)" % tuple(c)


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

    def group(self, name, parent, x, z, flag=None, visible_when=True, min_chapter=0, lift=0.0):
        sc = self.ext_res("Script", "res://scripts/interaction/conditional.gd")
        props = f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0, {z})\nscript = ExtResource("{sc}")'
        if flag:
            props += f'\nflag = "{flag}"\nvisible_when = {"true" if visible_when else "false"}'
        if min_chapter:
            props += f'\nmin_chapter = {min_chapter}'
        if lift:
            props += f'\nmetadata/lift = {lift}'
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

    def npc(self, name, parent, npc_id, knot, label, c, x, z, height=1.7, yaw=0.0, pose="stand"):
        i = self.ext_res("PackedScene", "res://scenes/npc/npc.tscn")
        self.node(name, None, parent, f'{self.xf(x, z, yaw)}\nnpc_id = "{npc_id}"\nknot = "{knot}"\nlabel_key = "{label}"\nbody_color = {color(c)}\nheight = {height}\npose = "{pose}"', instance=i)

    def pickup(self, name, parent, item, examine, x, z):
        i = self.ext_res("PackedScene", "res://scenes/props/pickup.tscn")
        self.node(name, None, parent, f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0, {z})\nitem_id = "{item}"\nera_id = "{self.era}"\nexamine_key = "{examine}"', instance=i)

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

    def register(self, name, parent, x, z):
        rp = self.ext_res("Script", "res://scripts/interaction/register_pickup.gd")
        self.node(name, "Node3D", parent, f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0, {z})\nscript = ExtResource("{rp}")')
        path = f"{parent}/{name}" if parent != "." else name
        self.node("BookMesh", "CSGBox3D", path, f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.96, 0)\nsize = Vector3(0.45, 0.12, 0.32)\nmaterial = {self.mat((0.45, 0.25, 0.1), 0.6)}')
        self.node("Plinth", "CSGBox3D", path, f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.45, 0)\nsize = Vector3(0.9, 0.9, 0.7)\nmaterial = {self.mat((0.7, 0.68, 0.62))}')
        self.collider(path, self.sub_res("SphereShape3D", "radius = 1.2", "S"), 0.6)

    def story_point(self, name, parent, knot, speaker, text, loc, label, radius=1.8):
        sp = self.ext_res("Script", "res://scripts/interaction/story_point.gd")
        self.node(name, "Node3D", parent, f'script = ExtResource("{sp}")\nknot = "{knot}"\nspeaker_key = "{speaker}"\ntext_key = "{text}"\nlocation_id = "{loc}"\nlabel_key = "{label}"')
        path = f"{parent}/{name}" if parent != "." else name
        self.collider(path, self.sub_res("SphereShape3D", f"radius = {radius}", "S"), 1.0)

    def farm_plots(self, origin, n, seeds):
        """Farming: plots in a row plus a seed bin, all era-local."""
        self.group("Farming", ".", *origin)
        for i in range(n):
            self.instance(f"Plot{i}", "Farming", "res://scenes/farming/farm_plot.tscn",
                          f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {i * 5.5}, 0, 0)\nplot_id = "plot{i}"\nera_id = "{self.era}"')
        sb = self.ext_res("Script", "res://scripts/farming/seed_bin.gd")
        shape = self.sub_res("BoxShape3D", "size = Vector3(1.4, 1.2, 1.0)", f"SB_{self.era}_")
        self.node("SeedBin", "Node3D", "Farming", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -3.5, 0, 0)\nscript = ExtResource("{sb}")\nera_id = "{self.era}"\nseed_item_ids = Array[String]([{", ".join(chr(34) + x + chr(34) for x in seeds)}])')
        self.box("Bin", "Farming/SeedBin", (1.2, 0.9, 0.8), 0.45, DARKWOOD)
        self.collider("Farming/SeedBin", shape, 0.6)

    def trade_post(self, pos, key, box_color):
        """Trading: one post per era, era-local goods and money."""
        sc = self.ext_res("Script", "res://scripts/trading/trade_post.gd")
        shape = self.sub_res("BoxShape3D", "size = Vector3(2.6, 2.4, 2.2)", f"TP_{self.era}_")
        self.node("TradePost", "Node3D", ".", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, 0, {pos[1]})\nscript = ExtResource("{sc}")\nera_id = "{self.era}"\npost_name_key = "{key}"\nintro_key = "{key}_TEXT"')
        self.footprint("TradePost", 3.0, 2.4)
        self.box("Base", "TradePost", (3.0, 2.0, 2.4), -1.0, SKIRT)
        self.box("Stall", "TradePost", (2.4, 1.1, 1.2), 0.55, box_color)
        self.box("Awning", "TradePost", (2.8, 0.12, 2.0), 2.2, (0.5, 0.45, 0.3), 0, -0.3)
        self.box("PostA", "TradePost", (0.1, 2.2, 0.1), 1.1, DARKWOOD, -1.3, -1.2)
        self.box("PostB", "TradePost", (0.1, 2.2, 0.1), 1.1, DARKWOOD, 1.3, -1.2)
        self.collider("TradePost", shape, 1.1)

    def manor_site(self, manor_id, pos):
        """Base building: a marker post the player builds from."""
        sc = self.ext_res("Script", "res://scripts/base_building/manor_controller.gd")
        shape = self.sub_res("BoxShape3D", "size = Vector3(1.6, 2.4, 1.6)", f"MS_{manor_id}_")
        name = f"Manor_{manor_id}"
        self.node(name, "Node3D", ".", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, 0, {pos[1]})\nscript = ExtResource("{sc}")\nmanor_id = "{manor_id}"')
        self.box("Post", name, (0.25, 2.0, 0.25), 1.0, DARKWOOD)
        self.box("Sign", name, (1.2, 0.5, 0.08), 1.7, (0.85, 0.8, 0.6))
        self.collider(name, shape, 1.2)

    def hunting(self, max_animals=8):
        """Hunting: a spawner that keeps animals around the player on their land cover."""
        sc = self.ext_res("Script", "res://scripts/hunting/hunting_spawner.gd")
        self.node("HuntingSpawner", "Node3D", ".", f'script = ExtResource("{sc}")\nera_id = "{self.era}"\nmax_animals = {max_animals}')

    def village(self, buildings):
        """Real building footprints (from the nDSM) as simple massing boxes."""
        self.group("Village", ".", 0, 0)
        for i, b in enumerate(buildings):
            self.group(f"B{i}", "Village", b["x"], b["z"])
            self.footprint(f"Village/B{i}", b["w"], b["d"])
            self.box("Mass", f"Village/B{i}", (b["w"], b["h"] + 3.0, b["d"]), b["h"] / 2 - 1.5, tuple(min(1.0, k * 0.9) for k in b["color"]))
            self.box("Roof", f"Village/B{i}", (b["w"] + 0.6, 0.25, b["d"] + 0.6), b["h"] + 0.12, tuple(k * 0.6 for k in b["color"]))

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
                s.group(name, parent, x, z, n.get("flag"), n.get("visible_when", True), int(n.get("min_chapter", 0)), self.num(n.get("lift", 0.0), env))
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
            elif t == "story_point":
                s.story_point(name, parent, n["knot"], n.get("speaker", ""), self.txt(n.get("text", ""), env), n.get("loc", ""), n.get("label", ""), self.num(n.get("radius", 1.8), env))
            elif t == "npc":
                x, z = self.pos(n.get("at"), env)
                s.npc(name, parent, n["id"], n["knot"], n["label"], self.col(n.get("color", [0.5, 0.4, 0.3]), env), x, z, self.num(n.get("height", 1.7), env), self.yaw(n, env), n.get("pose", "stand"))
            elif t == "pickup":
                x, z = self.pos(n.get("at"), env)
                s.pickup(name, parent, n["item"], n.get("examine", ""), x, z)
            elif t == "register":
                x, z = self.pos(n.get("at"), env)
                s.register(name or "RegisterBook", parent, x, z)
            elif t == "tree":
                x, z = self.pos(n.get("at"), env)
                s.tree(name, parent, x, z, self.num(n.get("scale", 1.0), env), self.yaw(n, env), n.get("scene", "res://assets/vegetation/tree_juniper.tscn"))
            elif t == "scatter":
                rng = random.Random(int(n.get("seed", 1798)))
                r_max = self.num(n.get("radius", 40.0), env); smin, smax = self.nums(n.get("scale", [0.4, 0.7]), env)
                for i in range(int(self.num(n.get("count", 10), env))):
                    a = rng.random() * math.tau; r = rng.random() ** 0.5 * r_max
                    s.tree(f"{n.get('prefix', 'Tree')}{i}", parent, round(math.cos(a) * r, 1), round(math.sin(a) * r, 1), round(rng.uniform(smin, smax), 2), rng.random() * 6.28, n.get("scene", "res://assets/vegetation/tree_juniper.tscn"))
            elif t == "farm_plots":
                s.farm_plots(self.pos(n.get("at"), env), int(self.num(n.get("count", 2), env)), n.get("seeds", []))
            elif t == "trade_post":
                s.trade_post(self.pos(n.get("at"), env), n["key"], self.col(n.get("color", [0.7, 0.65, 0.5]), env))
            elif t == "manor_site":
                s.manor_site(n["id"], self.pos(n.get("at"), env))
            elif t == "hunting":
                s.hunting(int(self.num(n.get("max_animals", 8), env)))
            elif t == "village":
                src = os.path.join(self.site_dir, n.get("source", "buildings_2026.json"))
                if os.path.exists(src):
                    s.village(json.load(open(src)))
                else:
                    self.problems.append(f"village source missing: {src}")
            else:
                self.problems.append(f"unknown node type {t!r} ({name})")


def generate(site, check=False):
    site_dir = os.path.join(ROOT, "sites", site)
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
    a = ap.parse_args()
    sys.exit(0 if generate(a.site, a.check) else 1)
