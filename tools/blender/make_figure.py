# A posed low-poly human figure for NPCs, ~1.75 m, origin at the feet, facing -Z in Godot
# (= +Y in Blender before the Y-up export flips it). Two materials: "Skin" and "Clothes",
# so the NPC script can recolour clothes per character. Poses: stand, arms_folded, holding.
#   Blender -b -P tools/blender/make_figure.py -- assets/models/figures
import bpy, sys, math, os

out_dir = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "figures"
os.makedirs(out_dir, exist_ok=True)


def mat(name, rgb, rough=0.9):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = rough
    return m


def part(name, kind, size, loc, material, rot=(0, 0, 0)):
    if kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=1, location=loc, rotation=rot)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=1, depth=1, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object; o.name = name; o.scale = size; o.data.materials.append(material)
    return o


def figure(pose):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    skin = mat("Skin", (0.8, 0.62, 0.5)); clothes = mat("Clothes", (0.45, 0.4, 0.35)); hair = mat("Hair", (0.25, 0.18, 0.12))
    shoes = mat("Shoes", (0.2, 0.15, 0.1))
    o = []
    o.append(part("Head", "sphere", (0.11, 0.12, 0.13), (0, 0, 1.62), skin))
    o.append(part("Hair", "sphere", (0.115, 0.125, 0.09), (0, 0.01, 1.68), hair))
    o.append(part("Neck", "cyl", (0.05, 0.05, 0.1), (0, 0, 1.47), skin))
    o.append(part("Torso", "cube", (0.38, 0.22, 0.6), (0, 0, 1.12), clothes))
    o.append(part("Hips", "cube", (0.34, 0.22, 0.25), (0, 0, 0.78), clothes))
    for s in (-1, 1):
        o.append(part(f"Leg{s}", "cyl", (0.075, 0.075, 0.72), (s * 0.1, 0, 0.36), clothes))
        o.append(part(f"Shoe{s}", "cube", (0.12, 0.26, 0.08), (s * 0.1, -0.04, 0.04), shoes))
        if pose == "arms_folded":
            o.append(part(f"UpperArm{s}", "cyl", (0.055, 0.055, 0.3), (s * 0.24, 0, 1.28), clothes, (0.1, 0, 0)))
            o.append(part(f"Forearm{s}", "cyl", (0.05, 0.05, 0.3), (s * 0.1, -0.15, 1.13), clothes, (0, math.radians(90), 0)))
        elif pose == "holding":
            o.append(part(f"UpperArm{s}", "cyl", (0.055, 0.055, 0.3), (s * 0.24, -0.04, 1.28), clothes, (math.radians(-25), 0, 0)))
            o.append(part(f"Forearm{s}", "cyl", (0.05, 0.05, 0.3), (s * 0.22, -0.2, 1.08), skin, (math.radians(-80), 0, 0)))
        else:
            o.append(part(f"UpperArm{s}", "cyl", (0.055, 0.055, 0.3), (s * 0.24, 0, 1.28), clothes, (0, s * 0.12, 0)))
            o.append(part(f"Forearm{s}", "cyl", (0.05, 0.05, 0.3), (s * 0.27, 0, 0.99), skin, (0, s * 0.12, 0)))
            o.append(part(f"Hand{s}", "sphere", (0.05, 0.04, 0.06), (s * 0.28, 0, 0.83), skin))
    if pose == "holding":
        o.append(part("Tool", "cyl", (0.02, 0.02, 1.3), (0.02, -0.34, 1.0), hair, (math.radians(90), 0, 0)))
    bpy.ops.object.select_all(action='DESELECT')
    for x in o: x.select_set(True)
    bpy.context.view_layer.objects.active = o[0]
    bpy.ops.object.join()
    f = bpy.context.active_object; f.name = "Figure_" + pose
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    path = os.path.join(out_dir, f"figure_{pose}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True)
    print("exported", path, "faces", len(f.data.polygons))


for pose in ("stand", "arms_folded", "holding"):
    figure(pose)
