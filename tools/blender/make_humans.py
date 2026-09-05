"""Generates the game's human figures with MPFB2 (MakeHuman for Blender) and exports them as glTF.

    blender --background --python tools/blender/make_humans.py -- [--out assets/models/humans] [--only man_casual] [--probe]

Needs Blender 4.2+ with the MPFB extension enabled (blender --command extension install -s -e mpfb)
and the CC0 "makehuman_system_assets" pack unpacked into MPFB's data directory
(<Blender>/extensions/.user/blender_org/mpfb/data: skins/, clothes/, hair/, eyes/, ...).
Every variant: a base mesh with macro settings (gender, age, weight, muscle, height, proportions),
a skin, eyes and eyebrows, hair, a suit and shoes from the pack, the "game_engine" rig, helpers
removed, textures scaled to TEXTURE_PX and written into <out>/<name>.glb (Y up, metres).
MPFB code is GPL-3 (used as a tool only); the base mesh, targets and the system assets are CC0, so
the exported figures are the project's own (see THIRD_PARTY.md).
--probe prints the shape keys and the rig's bone names of one figure and exits.
"""
import argparse
import importlib
import os
import sys

import bpy

TEXTURE_PX = 1024

# name: macro settings + assets. gender 0 = female, 1 = male (MakeHuman convention, checked with --probe).
VARIANTS = {
    "man_casual": {"gender": 1.0, "age": 0.42, "weight": 0.5, "muscle": 0.5, "height": 0.55, "proportions": 0.5,
                   "skin": "young_caucasian_male", "hair": "short01", "clothes": ["male_casualsuit02", "shoes01"]},
    "man_work": {"gender": 1.0, "age": 0.55, "weight": 0.6, "muscle": 0.6, "height": 0.5, "proportions": 0.45,
                 "skin": "middleage_caucasian_male", "hair": "short03", "clothes": ["male_worksuit01", "shoes03"]},
    "man_old": {"gender": 1.0, "age": 0.9, "weight": 0.45, "muscle": 0.35, "height": 0.45, "proportions": 0.5,
                "skin": "old_caucasian_male", "hair": "short02", "clothes": ["male_elegantsuit01", "shoes02", "fedora01"]},
    "man_young": {"gender": 1.0, "age": 0.3, "weight": 0.4, "muscle": 0.55, "height": 0.6, "proportions": 0.55,
                  "skin": "young_caucasian_male2", "hair": "short04", "clothes": ["male_casualsuit05", "shoes01"]},
    "woman_casual": {"gender": 0.0, "age": 0.4, "weight": 0.5, "muscle": 0.5, "height": 0.5, "proportions": 0.5,
                     "skin": "young_caucasian_female", "hair": "long01", "clothes": ["female_casualsuit01", "shoes02"]},
    "woman_elegant": {"gender": 0.0, "age": 0.55, "weight": 0.5, "muscle": 0.45, "height": 0.5, "proportions": 0.55,
                      "skin": "middleage_caucasian_female", "hair": "bob01", "clothes": ["female_elegantsuit01", "shoes02"]},
    "woman_old": {"gender": 0.0, "age": 0.9, "weight": 0.55, "muscle": 0.35, "height": 0.42, "proportions": 0.5,
                  "skin": "old_caucasian_female", "hair": "bob02", "clothes": ["female_casualsuit02", "shoes03"]},
    "woman_sport": {"gender": 0.0, "age": 0.3, "weight": 0.42, "muscle": 0.6, "height": 0.55, "proportions": 0.55,
                    "skin": "young_caucasian_female2", "hair": "ponytail01", "clothes": ["female_sportsuit01", "shoes01"]},
}


def dynamic_import(absolute_package_str, key):
    """MPFB is a Blender extension (relative package name); find its module by suffix."""
    for amod in list(sys.modules):
        if amod.endswith(absolute_package_str):
            mod = importlib.import_module(amod)
            if hasattr(mod, key):
                return getattr(mod, key)
    raise ValueError(f"MPFB module {absolute_package_str} not loaded; is the extension installed and enabled?")


def log(msg):
    print(f"[make_humans] {msg}", flush=True)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.armatures):
        for b in list(block):
            if b.users == 0:
                block.remove(b)


def build(name, v, services):
    HumanService, TargetService, HumanObjectProperties, AssetService = services
    basemesh = HumanService.create_human()
    for key in ("gender", "age", "weight", "muscle", "height", "proportions"):
        HumanObjectProperties.set_value(key, float(v[key]), entity_reference=basemesh)
    HumanObjectProperties.set_value("caucasian", 1.0, entity_reference=basemesh)
    HumanObjectProperties.set_value("african", 0.0, entity_reference=basemesh)
    HumanObjectProperties.set_value("asian", 0.0, entity_reference=basemesh)
    TargetService.reapply_macro_details(basemesh)
    skin = AssetService.find_asset_absolute_path(v["skin"] + ".mhmat", asset_subdir="skins")
    if skin:
        HumanService.set_character_skin(skin, basemesh, skin_type="GAMEENGINE")
    else:
        log(f"  skin {v['skin']} not found")
    HumanService.add_builtin_rig(basemesh, "game_engine")
    assets = [("eyes", "low-poly.mhclo", "Eyes"), ("eyebrows", "eyebrow001.mhclo", "Eyebrows"), ("hair", v["hair"] + ".mhclo", "Hair")]
    for c in v["clothes"]:
        assets.append(("clothes", c + ".mhclo", "Clothes"))
    for subdir, fname, atype in assets:
        path = AssetService.find_asset_absolute_path(fname, asset_subdir=subdir)
        if path is None:
            log(f"  {atype} {fname} not found, skipped")
            continue
        HumanService.add_mhclo_asset(path, basemesh, asset_type=atype, material_type="GAMEENGINE")
    return basemesh


def export_glb(basemesh, out_path, services_export):
    ExportService, ObjectService = services_export
    root = ExportService.create_character_copy(basemesh, name_suffix="_export")
    export_basemesh = ObjectService.find_object_of_type_amongst_nearest_relatives(root, "Basemesh")
    ExportService.bake_modifiers_remove_helpers(export_basemesh, bake_masks=True, bake_subdiv=False, remove_helpers=True, also_proxy=True)
    for img in bpy.data.images:
        if img.size[0] > TEXTURE_PX or img.size[1] > TEXTURE_PX:
            img.scale(min(img.size[0], TEXTURE_PX), min(img.size[1], TEXTURE_PX))
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in ObjectService.get_list_of_children(root):
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", use_selection=True, export_apply=True,
                              export_image_format="JPEG", export_jpeg_quality=82, export_yup=True,
                              export_skins=True, export_animations=False, export_morph=False)


def probe(basemesh):
    keys = basemesh.data.shape_keys
    if keys:
        log("shape keys: " + ", ".join(k.name for k in keys.key_blocks[:40]))
    for o in bpy.data.objects:
        if o.type == "ARMATURE":
            log(f"rig {o.name}: {len(o.data.bones)} bones: " + ", ".join(b.name for b in o.data.bones))
    dims = basemesh.dimensions
    log(f"basemesh dimensions x {dims.x:.2f} y {dims.y:.2f} z {dims.z:.2f}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "assets", "models", "humans"))
    ap.add_argument("--only", action="append")
    ap.add_argument("--probe", action="store_true")
    a = ap.parse_args(argv)
    services = (dynamic_import("mpfb.services.humanservice", "HumanService"), dynamic_import("mpfb.services.targetservice", "TargetService"),
                dynamic_import("mpfb.entities.objectproperties", "HumanObjectProperties"), dynamic_import("mpfb.services.assetservice", "AssetService"))
    services_export = (dynamic_import("mpfb.services.exportservice", "ExportService"), dynamic_import("mpfb.services.objectservice", "ObjectService"))
    os.makedirs(a.out, exist_ok=True)
    names = a.only or list(VARIANTS)
    for name in names:
        clear_scene()
        log(f"building {name}")
        basemesh = build(name, VARIANTS[name], services)
        if a.probe:
            probe(basemesh)
            return
        out_path = os.path.join(a.out, name + ".glb")
        export_glb(basemesh, out_path, services_export)
        log(f"wrote {out_path} ({os.path.getsize(out_path) / 1e6:.1f} MB)")


main()
