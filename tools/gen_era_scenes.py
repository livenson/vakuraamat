#!/usr/bin/env python3
"""Generates scenes/eras/era_*.tscn from data/site_layout.json.

The era scenes are plain Godot text scenes and can be edited in the editor afterwards;
re-running this script overwrites them, so keep authored changes here or in the layout.
Positions are tile metres (x east, z south); children sit at y = 0 and EraController
drops them onto the terrain at activation.
"""
import json, math, os, random

random.seed(1798)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
L = json.load(open(os.path.join(ROOT, "data/site_layout.json")))
OAK, MANOR, ORCH, FARM, WELL, FIELD, STONE = (tuple(L[k]) for k in ["oak", "manor", "orchard", "farm", "well", "field", "stone"])
MW, MD = L.get("manor_size", [22, 11])   # manor footprint: width (x) and depth (z) in metres
LEIDA = tuple(L["leida"])
PALE = (0.85, 0.78, 0.55); DARKWOOD = (0.30, 0.22, 0.14); STONE_C = (0.55, 0.53, 0.5); RED = (0.55, 0.25, 0.2); GREY = (0.45, 0.45, 0.42)


def color(c):
    return "Color(%.3f, %.3f, %.3f, 1)" % c


class Scene:
    def __init__(self, era):
        self.era = era; self.ext = []; self.sub = []; self.nodes = []; self.ext_ids = {}

    def ext_res(self, typ, path):
        if path in self.ext_ids:
            return self.ext_ids[path]
        i = len(self.ext) + 1
        self.ext.append(f'[ext_resource type="{typ}" path="{path}" id="{i}"]'); self.ext_ids[path] = i
        return i

    def mat(self, c, rough=0.9):
        i = len(self.sub) + 1
        self.sub.append(f'[sub_resource type="StandardMaterial3D" id="M{i}"]\nalbedo_color = {color(c)}\nroughness = {rough}')
        return f'SubResource("M{i}")'

    def node(self, name, typ, parent, props="", instance=None):
        head = f'[node name="{name}" ' + (f'type="{typ}" ' if typ else '') + f'parent="{parent}"' + (f' instance=ExtResource("{instance}")' if instance else '') + ']'
        self.nodes.append(head + ("\n" + props if props else ""))

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
        m = self.mat(c); cy = math.cos(rot); sy = math.sin(rot)
        self.node(name, "CSGBox3D", parent, f'transform = Transform3D({cy:.4f}, 0, {sy:.4f}, 0, 1, 0, {-sy:.4f}, 0, {cy:.4f}, {x}, {y_center}, {z})\nsize = Vector3({size[0]}, {size[1]}, {size[2]})\nmaterial = {m}')

    def torus(self, name, parent, inner, outer, c, y=0.0):
        m = self.mat(c)
        self.node(name, "CSGTorus3D", parent, f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {y}, 0)\ninner_radius = {inner}\nouter_radius = {outer}\nsides = 12\nring_sides = 6\nmaterial = {m}')

    def examine(self, name, parent, key, loc="", label="", x=0, z=0):
        i = self.ext_res("PackedScene", "res://scenes/props/examine_point.tscn")
        p = f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0, {z})\ntext_key = "{key}"'
        if loc: p += f'\nlocation_id = "{loc}"'
        if label: p += f'\nlabel_key = "{label}"'
        self.node(name, None, parent, p, instance=i)

    def npc(self, name, parent, npc_id, knot, label, c, x, z, height=1.7, yaw=0.0):
        i = self.ext_res("PackedScene", "res://scenes/npc/npc.tscn"); cy = math.cos(yaw); sy = math.sin(yaw)
        self.node(name, None, parent, f'transform = Transform3D({cy:.4f}, 0, {sy:.4f}, 0, 1, 0, {-sy:.4f}, 0, {cy:.4f}, {x}, 0, {z})\nnpc_id = "{npc_id}"\nknot = "{knot}"\nlabel_key = "{label}"\nbody_color = {color(c)}\nheight = {height}', instance=i)

    def pickup(self, name, parent, item, examine, x, z):
        i = self.ext_res("PackedScene", "res://scenes/props/pickup.tscn")
        self.node(name, None, parent, f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x}, 0, {z})\nitem_id = "{item}"\nera_id = "{self.era}"\nexamine_key = "{examine}"', instance=i)

    def tree(self, name, parent, x, z, scale, yaw=0.0, scene="res://assets/vegetation/tree_juniper.tscn"):
        i = self.ext_res("PackedScene", scene); cy = math.cos(yaw) * scale; sy = math.sin(yaw) * scale
        self.node(name, None, parent, f'transform = Transform3D({cy:.4f}, 0, {sy:.4f}, 0, {scale}, 0, {-sy:.4f}, 0, {cy:.4f}, {x}, 0, {z})', instance=i)

    def instance(self, name, parent, path, props=""):
        i = self.ext_res("PackedScene", path)
        self.node(name, None, parent, props, instance=i)

    def write(self, path):
        sc = self.ext_res("Script", "res://scripts/era/era_controller.gd")
        root = f'[node name="{self.era}" type="Node3D"]\nscript = ExtResource("{sc}")\nera_id = "{self.era}"'
        out = f'[gd_scene load_steps={len(self.ext) + len(self.sub) + 1} format=3]\n\n' + "\n".join(self.ext) + "\n\n" + "\n\n".join(self.sub) + "\n\n" + root + "\n\n" + "\n\n".join(self.nodes) + "\n"
        open(path, "w").write(out)


def common(s, era):
    s.group("Oak", ".", *OAK)
    sc = {"era_1798": 0.45, "era_1938": 0.75, "era_2026": 1.0}[era]
    s.instance("OakTree", "Oak", "res://assets/models/props/oak.glb", f'transform = Transform3D({sc * 0.76:.3f}, 0, {sc * 0.64:.3f}, 0, {sc}, 0, {-sc * 0.64:.3f}, 0, {sc * 0.76:.3f}, 0, 0, 0)')
    s.examine("OakExamine", "Oak", f"EX_OAK_{era[-4:]}", "LOC_OAK", "LOC_OAK", 1.5, 1.5)


def build_2026():
    s = Scene("era_2026"); common(s, "era_2026")
    s.group("Ruin", ".", *MANOR)
    # north wall has a doorway in the middle so the book is visible from the spawn point
    walls = [((MW - 5) / 2, 0.6, -(MW + 5) / 4, -MD / 2, 2.4), ((MW - 5) / 2, 0.6, (MW + 5) / 4, -MD / 2, 2.0),
             (MW, 0.6, 0, MD / 2, 1.6), (0.6, MD, -MW / 2, 0, 2.8), (0.6, MD * 0.55, MW / 2, -MD * 0.22, 1.2)]
    for i, (sx, sz, x, z, h) in enumerate(walls):
        s.box(f"Wall{i}", "Ruin", (sx, h, sz), h / 2, STONE_C, x, z)
    s.examine("RuinExamine", "Ruin", "EX_MANOR_2026", "LOC_MANOR", "LOC_MANOR", 0, -MD / 2 - 3)
    rp = s.ext_res("Script", "res://scripts/interaction/register_pickup.gd")
    s.node("RegisterBook", "Node3D", "Ruin", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, {-MD / 2 + 5})\nscript = ExtResource("{rp}")')
    s.node("BookMesh", "CSGBox3D", "Ruin/RegisterBook", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.96, 0)\nsize = Vector3(0.45, 0.12, 0.32)\nmaterial = {s.mat((0.45, 0.25, 0.1), 0.6)}')
    s.node("Plinth", "CSGBox3D", "Ruin/RegisterBook", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.45, 0)\nsize = Vector3(0.9, 0.9, 0.7)\nmaterial = {s.mat((0.7, 0.68, 0.62))}')
    s.node("Body3D", "StaticBody3D", "Ruin/RegisterBook", "collision_layer = 2\ncollision_mask = 0")
    s.sub.append('[sub_resource type="SphereShape3D" id="S1"]\nradius = 1.2')
    s.node("Shape", "CollisionShape3D", "Ruin/RegisterBook/Body3D", 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.6, 0)\nshape = SubResource("S1")')
    s.group("OrchardKept", ".", *ORCH, flag="cellar_opened", visible_when=True)
    for i in range(6):
        s.tree(f"Apple{i}", "OrchardKept", i * 4.5, 0, 0.55 + 0.1 * (i % 3), i * 1.1)
    s.examine("OrchardExamine", "OrchardKept", "EX_ORCHARD_2026", "LOC_ORCHARD", "LOC_ORCHARD", 11, 2.5)
    s.group("OrchardScrub", ".", *ORCH, flag="cellar_opened", visible_when=False)
    for i in range(4):
        s.tree(f"Scrub{i}", "OrchardScrub", i * 6 + 2, 1.5, 1.3, i * 0.9, scene="res://assets/vegetation/bush_jello.tscn")
    s.examine("ScrubExamine", "OrchardScrub", "EX_ORCHARD_SCRUB_2026", "LOC_ORCHARD", "LOC_ORCHARD", 11, 2.5)
    s.group("Farm", ".", *FARM)
    s.box("Foundation", "Farm", (14, 0.35, 8), 0.17, GREY)
    s.examine("FarmExamine", "Farm", "EX_FARM_2026", "LOC_FARMSTEAD", "LOC_FARMSTEAD", 0, 5.5)
    s.group("WellRing", ".", *WELL, flag="well_kept_open", visible_when=True)
    s.torus("Ring", "WellRing", 0.8, 1.2, STONE_C, 0.3)
    s.examine("WellExamine", "WellRing", "EX_WELL_2026", "LOC_WELL", "LOC_WELL", 0, 0)
    s.group("WellDip", ".", *WELL, flag="well_kept_open", visible_when=False)
    s.examine("DipExamine", "WellDip", "EX_WELL_DIP_2026", "LOC_WELL", "LOC_WELL", 0, 0)
    s.group("StoneKept", ".", *STONE, flag="family_recorded_1798", visible_when=True)
    s.instance("BoundaryStone", "StoneKept", "res://assets/models/props/boundary_stone.glb", 'transform = Transform3D(0.9397, 0, 0.342, 0, 1, 0, -0.342, 0, 0.9397, 0, 0, 0)')
    s.examine("StoneExamine", "StoneKept", "EX_STONE_2026", "", "LOC_NORTH_FIELD", 0, 0)
    s.group("FieldMeadow", ".", *FIELD, flag="north_field_ploughed", visible_when=True)
    s.examine("MeadowExamine", "FieldMeadow", "EX_FIELD_MEADOW_2026", "LOC_NORTH_FIELD", "LOC_NORTH_FIELD", 0, 0)
    s.group("FieldForest", ".", *FIELD, flag="north_field_ploughed", visible_when=False)
    for i in range(36):
        a = random.random() * math.tau; r = random.random() ** 0.5 * 45
        s.tree(f"Young{i}", "FieldForest", round(math.cos(a) * r, 1), round(math.sin(a) * r, 1), round(0.35 + random.random() * 0.3, 2), random.random() * 6.28)
    s.examine("ForestExamine", "FieldForest", "EX_FIELD_FOREST_2026", "LOC_NORTH_FIELD", "LOC_NORTH_FIELD", 0, 0)
    s.npc("Leida", ".", "npc_leida", "leida", "NPC_LEIDA", (0.45, 0.5, 0.62), LEIDA[0], LEIDA[1], 1.55, 2.4)
    s.pickup("RustedTool", ".", "rusted_tool", "EX_RUSTED_TOOL", OAK[0] + 3, OAK[1] + 2)
    farm_plots(s, "era_2026", (FARM[0] + 2, FARM[1] + 14), 2, ["seed_potato", "seed_cabbage"])
    trade_post(s, "era_2026", (MANOR[0] - MW / 2 - 12, MANOR[1] - 10), "POST_2026", (0.85, 0.85, 0.8))
    return s


def build_1938():
    s = Scene("era_1938"); common(s, "era_1938")
    s.group("School", ".", *MANOR)
    s.box("House", "School", (MW, 7, MD), 3.5, PALE)
    s.box("Roof", "School", (MW + 1, 1.2, MD + 1), 7.6, RED)
    s.examine("SchoolExamine", "School", "EX_MANOR_1938", "LOC_MANOR", "LOC_MANOR", 0, -MD / 2 - 3)
    s.group("Farm", ".", *FARM)
    s.box("House", "Farm", (14, 3.6, 8), 1.8, DARKWOOD)
    s.box("Roof", "Farm", (15, 1.0, 9), 4.1, (0.5, 0.42, 0.25))
    s.box("Chimney", "Farm", (0.8, 2.2, 0.8), 5.2, RED, 3, 0)
    s.box("Extension", "Farm", (6, 2.2, 5), 1.1, (0.6, 0.5, 0.35), 10, -1)
    s.examine("FarmExamine", "Farm", "EX_FARM_1938", "LOC_FARMSTEAD", "LOC_FARMSTEAD", 0, 5.5)
    s.group("WellKept", ".", *WELL, flag="well_kept_open", visible_when=True)
    s.torus("Ring", "WellKept", 0.8, 1.2, STONE_C, 0.35)
    s.box("PostA", "WellKept", (0.15, 2.2, 0.15), 1.1, DARKWOOD, -1.1, 0)
    s.box("PostB", "WellKept", (0.15, 2.2, 0.15), 1.1, DARKWOOD, 1.1, 0)
    s.box("Beam", "WellKept", (2.4, 0.15, 0.15), 2.2, DARKWOOD, 0, 0)
    s.examine("WellExamine", "WellKept", "EX_WELL_1938", "LOC_WELL", "LOC_WELL", 0, 0)
    s.group("WellGone", ".", *WELL, flag="well_kept_open", visible_when=False)
    s.examine("DipExamine", "WellGone", "EX_WELL_DIP_1938", "LOC_WELL", "LOC_WELL", 0, 0)
    s.group("OrchardPlanted", ".", *ORCH, flag="cellar_opened", visible_when=True)
    for i in range(6):
        s.tree(f"Sapling{i}", "OrchardPlanted", i * 4.5, 0, 0.22, i * 1.1)
        s.box(f"Stake{i}", "OrchardPlanted", (0.06, 1.4, 0.06), 0.7, DARKWOOD, i * 4.5 + 0.4, 0)
    s.examine("OrchardExamine", "OrchardPlanted", "EX_ORCHARD_SAPLINGS_1938", "LOC_ORCHARD", "LOC_ORCHARD", 11, 2.5)
    s.group("OrchardBare", ".", *ORCH, flag="cellar_opened", visible_when=False)
    s.examine("BareExamine", "OrchardBare", "EX_ORCHARD_BARE_1938", "LOC_ORCHARD", "LOC_ORCHARD", 11, 2.5)
    s.group("Field", ".", *FIELD)
    s.box("PloughBeam", "Field", (2.2, 0.12, 0.12), 0.5, DARKWOOD, 0, 0, 0.3)
    s.box("PloughShare", "Field", (0.5, 0.35, 0.08), 0.18, (0.3, 0.3, 0.32), 0.9, 0.1, 0.3)
    s.examine("FieldExamine", "Field", "EX_FIELD_1938", "LOC_NORTH_FIELD", "LOC_NORTH_FIELD", 0, 0)
    s.group("Chapter2", ".", 0, 0, min_chapter=2)
    s.npc("Aino", "Chapter2", "npc_aino", "aino", "NPC_AINO", (0.7, 0.35, 0.3), FARM[0] + 3, FARM[1] + 6, 1.62, 3.0)
    s.npc("Juhan", "Chapter2", "npc_juhan", "juhan", "NPC_JUHAN", (0.33, 0.36, 0.5), FIELD[0] + 3, FIELD[1] + 2, 1.8, -1.2)
    s.npc("Villem", "Chapter2", "npc_villem", "villem", "NPC_VILLEM", (0.28, 0.28, 0.3), MANOR[0] - 9, MANOR[1] - MD / 2 - 6, 1.75, 0.8)
    s.pickup("RegisterPage", "Chapter2", "register_page", "ITEM_REGISTER_PAGE_DESC", MANOR[0] + 9, MANOR[1] - MD / 2 - 3)
    s.pickup("AinoLetter", "Chapter2", "aino_letter", "ITEM_AINO_LETTER_DESC", FARM[0] - 5, FARM[1] + 5)
    s.pickup("ChurnLid", ".", "milk_churn_lid", "ITEM_MILK_CHURN_LID_DESC", 520, 600)
    extras_1938(s)
    return s


def build_1798():
    s = Scene("era_1798"); common(s, "era_1798")
    s.group("Manor", ".", *MANOR)
    s.box("House", "Manor", (MW, 7, MD), 3.5, PALE)
    s.box("Roof", "Manor", (MW + 1, 1.4, MD + 1), 7.7, (0.35, 0.3, 0.25))
    s.examine("ManorExamine", "Manor", "EX_MANOR_1798", "LOC_MANOR", "LOC_MANOR", 0, -MD / 2 - 3)
    s.pickup("ManorKey", "Manor", "manor_key", "ITEM_MANOR_KEY_DESC", 4, -MD / 2 - 2.5)
    s.npc("Hans", "Manor", "npc_hans", "hans", "NPC_HANS", (0.2, 0.2, 0.26), -6, -MD / 2 - 5, 1.72, 0.5)
    s.group("Farm", ".", *FARM)
    s.box("Rehielamu", "Farm", (16, 3.0, 8), 1.5, DARKWOOD)
    s.box("Thatch", "Farm", (17, 1.6, 9), 3.8, (0.55, 0.45, 0.25))
    s.examine("FarmExamine", "Farm", "EX_FARM_1798", "LOC_FARMSTEAD", "LOC_FARMSTEAD", 0, 5.5)
    s.pickup("Ploughshare", "Farm", "ploughshare", "ITEM_PLOUGHSHARE_DESC", 6, 5.5)
    s.pickup("Hymnbook", "Farm", "hymnbook", "ITEM_HYMNBOOK_DESC", -4, 5.2)
    s.npc("Mart", "Farm", "npc_mart", "mart", "NPC_MART", (0.4, 0.3, 0.2), 3, -7, 1.68, 2.8)
    s.group("WellSite", ".", *WELL)
    s.torus("HalfRing", "WellSite", 0.8, 1.2, STONE_C, 0.15)
    sp = s.ext_res("Script", "res://scripts/interaction/story_point.gd")
    s.sub.append('[sub_resource type="SphereShape3D" id="S2"]\nradius = 1.8')
    s.node("WellStory", "Node3D", "WellSite", f'script = ExtResource("{sp}")\nknot = "well"\nspeaker_key = "NPC_MART"\ntext_key = "EX_WELL_1798"\nlocation_id = "LOC_WELL"\nlabel_key = "LOC_WELL"')
    s.node("Body3D", "StaticBody3D", "WellSite/WellStory", "collision_layer = 2\ncollision_mask = 0")
    s.node("Shape", "CollisionShape3D", "WellSite/WellStory/Body3D", 'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0)\nshape = SubResource("S2")')
    s.group("Strips", ".", *FIELD)
    s.examine("FieldExamine", "Strips", "EX_FIELD_1798", "LOC_NORTH_FIELD", "LOC_NORTH_FIELD", 0, 0)
    extras_1798(s)
    return s


# Hooks for later phases (farming, hunting, trading) to add era-local content.
def farm_plots(s, era, origin, n, seeds):
    """Farming (Phase 2): plots in a row plus a seed bin, all era-local."""
    s.group("Farming", ".", *origin)
    for i in range(n):
        s.instance(f"Plot{i}", "Farming", "res://scenes/farming/farm_plot.tscn",
                   f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {i * 5.5}, 0, 0)\nplot_id = "plot{i}"\nera_id = "{era}"')
    sb = s.ext_res("Script", "res://scripts/farming/seed_bin.gd")
    s.sub.append(f'[sub_resource type="BoxShape3D" id="SB_{era}"]\nsize = Vector3(1.4, 1.2, 1.0)')
    s.node("SeedBin", "Node3D", "Farming", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -3.5, 0, 0)\nscript = ExtResource("{sb}")\nera_id = "{era}"\nseed_item_ids = Array[String]([{", ".join(chr(34) + x + chr(34) for x in seeds)}])')
    s.box("Bin", "Farming/SeedBin", (1.2, 0.9, 0.8), 0.45, DARKWOOD)
    s.node("Body3D", "StaticBody3D", "Farming/SeedBin", "collision_layer = 2\ncollision_mask = 0")
    s.node("Shape", "CollisionShape3D", "Farming/SeedBin/Body3D", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.6, 0)\nshape = SubResource("SB_{era}")')


def trade_post(s, era, pos, key, box_color):
    """Trading (Phase 4): one post per era, era-local goods and money."""
    sc = s.ext_res("Script", "res://scripts/trading/trade_post.gd")
    s.sub.append(f'[sub_resource type="BoxShape3D" id="TP_{era}"]\nsize = Vector3(2.6, 2.4, 2.2)')
    s.node("TradePost", "Node3D", ".", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, 0, {pos[1]})\nscript = ExtResource("{sc}")\nera_id = "{era}"\npost_name_key = "{key}"\nintro_key = "{key}_TEXT"')
    s.box("Stall", "TradePost", (2.4, 1.1, 1.2), 0.55, box_color)
    s.box("Awning", "TradePost", (2.8, 0.12, 2.0), 2.2, (0.5, 0.45, 0.3), 0, -0.3)
    s.box("PostA", "TradePost", (0.1, 2.2, 0.1), 1.1, DARKWOOD, -1.3, -1.2)
    s.box("PostB", "TradePost", (0.1, 2.2, 0.1), 1.1, DARKWOOD, 1.3, -1.2)
    s.node("Body3D", "StaticBody3D", "TradePost", "collision_layer = 2\ncollision_mask = 0")
    s.node("Shape", "CollisionShape3D", "TradePost/Body3D", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.1, 0)\nshape = SubResource("TP_{era}")')


def manor_site(s, manor_id, pos):
    """Base building (Phase 5): a marker post the player builds from."""
    sc = s.ext_res("Script", "res://scripts/base_building/manor_controller.gd")
    s.sub.append(f'[sub_resource type="BoxShape3D" id="MS_{manor_id}"]\nsize = Vector3(1.6, 2.4, 1.6)')
    s.node(f"Manor_{manor_id}", "Node3D", ".", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]}, 0, {pos[1]})\nscript = ExtResource("{sc}")\nmanor_id = "{manor_id}"')
    s.box("Post", f"Manor_{manor_id}", (0.25, 2.0, 0.25), 1.0, DARKWOOD)
    s.box("Sign", f"Manor_{manor_id}", (1.2, 0.5, 0.08), 1.7, (0.85, 0.8, 0.6))
    s.node("Body3D", "StaticBody3D", f"Manor_{manor_id}", "collision_layer = 2\ncollision_mask = 0")
    s.node("Shape", "CollisionShape3D", f"Manor_{manor_id}/Body3D", f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.2, 0)\nshape = SubResource("MS_{manor_id}")')


def extras_1938(s):
    trade_post(s, "era_1938", (FARM[0] + 22, FARM[1] - 4), "POST_1938", (0.7, 0.65, 0.5))
    manor_site(s, "kaseoja_farm", (FARM[0] + 10, FARM[1] - 8))
    manor_site(s, "manor_park", (MANOR[0] + 30, MANOR[1] + 10))
    farm_plots(s, "era_1938", (FARM[0] - 6, FARM[1] + 14), 3, ["seed_rye", "seed_oats", "seed_potato"])
    hunting(s, "era_1938", 6)


def hunting(s, era, max_animals=8):
    """Hunting (Phase 3): a spawner that keeps animals around the player on their land cover."""
    sc = s.ext_res("Script", "res://scripts/hunting/hunting_spawner.gd")
    s.node("HuntingSpawner", "Node3D", ".", f'script = ExtResource("{sc}")\nera_id = "{era}"\nmax_animals = {max_animals}')


def extras_1798(s):
    hunting(s, "era_1798", 10)
    trade_post(s, "era_1798", (MANOR[0] + MW / 2 + 8, MANOR[1] - 6), "POST_1798", (0.45, 0.35, 0.22))


if __name__ == "__main__":
    for b in (build_2026, build_1938, build_1798):
        s = b(); s.write(os.path.join(ROOT, f"scenes/eras/{s.era}.tscn")); print("wrote", s.era)
