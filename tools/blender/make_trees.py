# Vakuraamat trees: birch, pine, spruce from Blender's Sapling Tree Gen presets (GPL add-on,
# used only as a tool; its output is ours) with CC0 foliage cards from ambientCG.
#   Blender -b -P tools/blender/make_trees.py -- assets/models/trees
# Each species exports <name>.glb at natural size with two materials (Bark, Foliage).
# Foliage cards use alpha-scissor textures so Godot renders them without sorting issues.
import bpy, sys, os, math, random, ast

out_dir = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "trees"
os.makedirs(out_dir, exist_ok=True)
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FOLIAGE = os.path.join(ROOT, "assets/textures/foliage")
bpy.ops.preferences.addon_enable(module="bl_ext.blender_org.sapling_tree_gen")
import importlib
sap = importlib.import_module("bl_ext.blender_org.sapling_tree_gen")
PRESETS = os.path.join(os.path.dirname(sap.__file__), "presets")


def load_preset(name):
    txt = open(os.path.join(PRESETS, name + ".py")).read()
    return ast.literal_eval(txt[txt.index("{"):])


SPECIES = {
    # name: (preset, overrides, foliage texture, bark colour, target height m, leaf scale)
    "birch": ("white_birch", {"levels": 3, "bevelRes": 3, "curveRes": (8, 4, 3, 1), "branches": (0, 30, 12, 0), "leaves": 14}, "birch_cluster.png", (0.86, 0.84, 0.78), 14.0, 1.6),
    "pine": ("small_pine", {"levels": 3, "bevelRes": 3, "curveRes": (8, 4, 2, 1), "branches": (0, 26, 10, 0), "leaves": 10}, "conifer_sprigs.png", (0.45, 0.32, 0.22), 18.0, 1.8),
    "spruce": ("douglas_fir", {"levels": 3, "bevelRes": 3, "curveRes": (8, 4, 2, 1), "branches": (0, 40, 12, 0), "leaves": 12}, "conifer_sprigs.png", (0.36, 0.28, 0.2), 20.0, 1.7),
}


def mat_bark(rgb):
    m = bpy.data.materials.new("Bark"); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = 0.95
    return m


def mat_foliage(texture):
    m = bpy.data.materials.new("Foliage"); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = bpy.data.images.load(os.path.join(FOLIAGE, texture))
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], b.inputs["Alpha"])
    b.inputs["Roughness"].default_value = 0.85
    m.blend_method = 'CLIP' if hasattr(m, "blend_method") else None
    return m


for name, (preset, overrides, foliage, bark_rgb, height, leaf_scale) in SPECIES.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="bl_ext.blender_org.sapling_tree_gen")   # reset disables add-ons
    p = load_preset(preset)
    p.update(overrides)
    p.update({"showLeaves": True, "leafShape": "rect", "leafScale": leaf_scale, "leafScaleX": 1.0,
              "bevel": True, "seed": 7, "scale": height, "scaleV": 0.0, "do_update": True, "handleType": "0"})
    try:
        bpy.ops.curve.tree_add(**p)
    except TypeError as e:
        # drop keys the installed version doesn't know
        bad = str(e).split('"')[1] if '"' in str(e) else None
        if bad and bad in p:
            del p[bad]; bpy.ops.curve.tree_add(**p)
        else:
            raise
    tree = bpy.data.objects.get("tree"); leaves = bpy.data.objects.get("leaves")
    bpy.context.view_layer.objects.active = tree; tree.select_set(True)
    bpy.ops.object.convert(target='MESH')
    tree = bpy.context.active_object
    tree.data.materials.clear(); tree.data.materials.append(mat_bark(bark_rgb))
    if leaves:
        leaves.data.materials.clear(); leaves.data.materials.append(mat_foliage(foliage))
    objs = [tree] + ([leaves] if leaves else [])
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = tree
    bpy.ops.object.join()
    t = bpy.context.active_object; t.name = name
    path = os.path.join(out_dir, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True, export_image_format='AUTO')
    zs = [v.co.z for v in t.data.vertices]
    print("exported", path, "faces", len(t.data.polygons), "height %.1f" % (max(zs) - min(zs)))
