# Vakuraamat buildings, generated headless. Origin at ground centre, +Y up (glTF), X = width.
#   Blender -b -P tools/blender/make_buildings.py -- assets/models/buildings
# Produces manor.glb, ruin.glb, rehielamu.glb (1798 barn-dwelling), farmhouse_1938.glb.
# Materials are plain principled colours so Godot needs no textures.
import bpy, bmesh, sys, math, random, os
from mathutils import Vector

out_dir = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "buildings"
os.makedirs(out_dir, exist_ok=True)
random.seed(1938)


ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEX = os.path.join(ROOT, "assets/textures/buildings")


def mat(name, rgb, rough=0.9, texture=None, tile=2.0, tint=(1, 1, 1)):
    """Principled material; with `texture`, colour + normal maps from assets/textures/buildings,
    box-projected at `tile` metres per repeat (see box_uv). rgb is used as a fallback/tint."""
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1); b.inputs["Roughness"].default_value = rough
    col_path = os.path.join(TEX, f"{texture}_color.jpg") if texture else None
    if col_path and os.path.exists(col_path):
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = bpy.data.images.load(col_path)
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'; mix.inputs[0].default_value = 1.0
        nt.links.new(tex.outputs["Color"], mix.inputs[6]); mix.inputs[7].default_value = (*tint, 1)
        nt.links.new(mix.outputs[2], b.inputs["Base Color"])
        nrm_path = os.path.join(TEX, f"{texture}_normal.jpg")
        if os.path.exists(nrm_path):
            ntex = nt.nodes.new("ShaderNodeTexImage"); ntex.image = bpy.data.images.load(nrm_path); ntex.image.colorspace_settings.name = 'Non-Color'
            nmap = nt.nodes.new("ShaderNodeNormalMap"); nmap.inputs["Strength"].default_value = 0.8
            nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"]); nt.links.new(nmap.outputs["Normal"], b.inputs["Normal"])
    m["tile"] = tile
    return m


def box_uv(obj):
    """Box-project UVs per face by dominant normal, scaled per material tile size (metres/repeat)."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers[0]
    for poly in me.polygons:
        matslot = me.materials[poly.material_index] if me.materials else None
        tile = float(matslot.get("tile", 2.0)) if matslot else 2.0
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = obj.matrix_world @ me.vertices[me.loops[li].vertex_index].co if False else me.vertices[me.loops[li].vertex_index].co
            u, v = ((co.y, co.z) if ax == 0 else (co.x, co.z) if ax == 1 else (co.x, co.y))
            uv.data[li].uv = (u / tile, v / tile)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def box(name, size, loc, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object; o.name = name; o.scale = size
    o.data.materials.append(material)
    return o


def hipped_roof(name, w, d, base_z, h, overhang, material, ridge_frac=0.35):
    """Hipped roof: rectangle at the eaves, ridge along the long (Y) axis."""
    bm = bmesh.new()
    hw, hd = w / 2 + overhang, d / 2 + overhang
    e = [bm.verts.new(v) for v in [(-hw, -hd, base_z), (hw, -hd, base_z), (hw, hd, base_z), (-hw, hd, base_z)]]
    ridge_half = hd * ridge_frac if d > w else hw * ridge_frac
    if d >= w:
        r = [bm.verts.new((0, -ridge_half, base_z + h)), bm.verts.new((0, ridge_half, base_z + h))]
        bm.faces.new((e[0], e[1], r[0])); bm.faces.new((e[1], e[2], r[1], r[0])); bm.faces.new((e[2], e[3], r[1])); bm.faces.new((e[3], e[0], r[0], r[1]))
    else:
        r = [bm.verts.new((-ridge_half, 0, base_z + h)), bm.verts.new((ridge_half, 0, base_z + h))]
        bm.faces.new((e[0], e[1], r[1], r[0])); bm.faces.new((e[1], e[2], r[1])); bm.faces.new((e[2], e[3], r[0], r[1])); bm.faces.new((e[3], e[0], r[0]))
    bm.faces.new(e[::-1])
    m = bpy.data.meshes.new(name); bm.to_mesh(m); bm.free(); m.materials.append(material)
    o = bpy.data.objects.new(name, m); bpy.context.scene.collection.objects.link(o)
    return o


def windows(prefix, w, d, z_rows, material, count_x, count_y, ww=1.2, wh=1.8, depth=0.08):
    """Dark inset panes flush with the walls on all four sides."""
    objs = []
    for z in z_rows:
        for i in range(count_x):
            x = -w / 2 + (i + 0.5) * w / count_x
            objs.append(box(f"{prefix}wN{len(objs)}", (ww, depth, wh), (x, -d / 2 - depth / 2 + 0.02, z), material))
            objs.append(box(f"{prefix}wS{len(objs)}", (ww, depth, wh), (x, d / 2 + depth / 2 - 0.02, z), material))
        for j in range(count_y):
            y = -d / 2 + (j + 0.5) * d / count_y
            objs.append(box(f"{prefix}wW{len(objs)}", (depth, ww, wh), (-w / 2 - depth / 2 + 0.02, y, z), material))
            objs.append(box(f"{prefix}wE{len(objs)}", (depth, ww, wh), (w / 2 + depth / 2 - 0.02, y, z), material))
    return objs


def export(name, objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    root = bpy.context.active_object; root.name = name
    box_uv(root)
    path = os.path.join(out_dir, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True)
    print("exported", path, "faces", len(root.data.polygons))


# ---------------------------------------------------------------- manor house (24 x 32, two storeys)
reset()
W, D, H = 24, 32, 7.2
wall = mat("ManorWall", (1, 1, 1), texture="plaster", tile=3.0, tint=(0.92, 0.8, 0.5)); roof = mat("ManorRoof", (1, 1, 1), texture="rooftiles", tile=2.0, tint=(0.55, 0.5, 0.45)); dark = mat("Window", (0.12, 0.13, 0.16), 0.3)
white = mat("Trim", (0.95, 0.93, 0.88)); stone = mat("Plinth", (1, 1, 1), texture="rock", tile=2.0, tint=(0.8, 0.78, 0.72))
objs = [box("Body", (W, D, H), (0, 0, H / 2), wall), box("Plinth", (W + 0.4, D + 0.4, 0.8), (0, 0, 0.4), stone),
        box("Cornice", (W + 0.6, D + 0.6, 0.35), (0, 0, H + 0.17), white),
        hipped_roof("Roof", W, D, H + 0.3, 4.2, 0.8, roof)]
objs += windows("m", W, D, [2.0, 5.2], dark, 5, 7)
# portico on the north (-Y) side: four columns and a pediment
for i, x in enumerate([-3.6, -1.2, 1.2, 3.6]):
    bpy.ops.mesh.primitive_cylinder_add(radius=0.28, depth=6.2, location=(x, -D / 2 - 2.2, 3.1), vertices=12)
    c = bpy.context.active_object; c.name = f"Column{i}"; c.data.materials.append(white); objs.append(c)
objs.append(box("PorticoRoof", (10, 3.4, 0.5), (0, -D / 2 - 1.7, 6.5), white))
objs.append(box("Steps", (10, 1.6, 0.8), (0, -D / 2 - 4.2, 0.4), stone))
objs.append(box("Door", (1.8, 0.1, 3.0), (0, -D / 2 - 0.05, 1.5), mat("Door", (0.3, 0.2, 0.12))))
export("manor", objs)

# ---------------------------------------------------------------- ruin of the same footprint
reset()
stone = mat("RuinStone", (1, 1, 1), texture="rock", tile=1.6, tint=(1.15, 1.05, 0.9)); rubble = mat("Rubble", (1, 1, 1), texture="rock", tile=1.0, tint=(1.0, 0.92, 0.8))
objs = []
def ruined_wall(name, length, along_x, offset, base_h):
    n = int(length / 2.4)
    for i in range(n):
        t = -length / 2 + (i + 0.5) * length / n
        h = max(0.4, base_h + random.uniform(-1.2, 0.6))
        if random.random() < 0.12:
            h = 0.5
        loc = (t, offset, h / 2) if along_x else (offset, t, h / 2)
        size = (length / n + 0.02, 0.7, h) if along_x else (0.7, length / n + 0.02, h)
        objs.append(box(f"{name}{i}", size, loc, stone))
ruined_wall("N", W, True, -D / 2, 3.2); ruined_wall("S", W, True, D / 2, 1.8); ruined_wall("W", D, False, -W / 2, 3.6); ruined_wall("E", D, False, W / 2, 2.2)
# doorway gap in the north wall: remove the two centre segments
for o in list(objs):
    if o.name.startswith("N") and abs(o.location.x) < 2.6: bpy.data.objects.remove(o, do_unlink=True); objs.remove(o)
for k in range(28):
    objs.append(box(f"Rubble{k}", (random.uniform(0.4, 1.4), random.uniform(0.4, 1.2), random.uniform(0.3, 0.8)),
                    (random.uniform(-W / 2 + 1, W / 2 - 1), random.uniform(-D / 2 + 1, D / 2 - 1), 0.25), rubble,
                    (0, 0, random.uniform(0, 3.14))))
export("ruin", objs)

# ---------------------------------------------------------------- 1798 rehielamu (barn-dwelling), 16 x 8, log walls, high thatch
reset()
log = mat("Log", (1, 1, 1), texture="bark", tile=1.5, tint=(0.75, 0.62, 0.45)); thatch = mat("Thatch", (1, 1, 1), texture="thatch", tile=2.5, tint=(0.85, 0.7, 0.4)) if os.path.exists(os.path.join(TEX, "thatch_color.jpg")) else mat("Thatch", (0.48, 0.36, 0.17)); door = mat("Door", (0.22, 0.16, 0.1))
objs = [box("Walls", (16, 8, 2.6), (0, 0, 1.3), log)]
for k in range(6):
    objs.append(box(f"LogLine{k}", (16.1, 8.1, 0.06), (0, 0, 0.35 + k * 0.42), mat(f"LogGap{k}", (0.2, 0.15, 0.1))))
objs.append(hipped_roof("Thatch", 16, 8, 2.6, 4.6, 1.0, thatch, ridge_frac=0.45))
objs.append(box("Door", (1.6, 0.1, 2.0), (2.5, -4.05, 1.0), door))
objs.append(box("Door2", (2.6, 0.1, 2.3), (-4.5, -4.05, 1.15), door))
export("rehielamu", objs)

# ---------------------------------------------------------------- 1938 farmhouse: same walls, new tiled roof, chimney, extension
reset()
log = mat("Log38", (1, 1, 1), texture="woodsiding", tile=2.0, tint=(0.7, 0.55, 0.35)); tile = mat("Tile", (1, 1, 1), texture="rooftiles", tile=1.5, tint=(0.95, 0.5, 0.35)); chim = mat("Chimney", (0.6, 0.35, 0.28))
white = mat("Frame", (0.9, 0.88, 0.8)); dark = mat("Pane", (0.15, 0.17, 0.2), 0.3); door = mat("Door38", (0.25, 0.3, 0.2))
objs = [box("Walls", (16, 8, 3.0), (0, 0, 1.5), log), hipped_roof("Roof", 16, 8, 3.0, 3.2, 0.7, tile, ridge_frac=0.5),
        box("Chimney", (0.8, 0.8, 2.4), (3, 0, 5.4), chim), box("Door", (1.2, 0.1, 2.1), (2.5, -4.05, 1.05), door),
        box("Extension", (6, 5, 2.6), (11, -1, 1.3), mat("ExtWall", (0.55, 0.45, 0.3))),
        hipped_roof("ExtRoof", 6, 5, 2.6, 1.6, 0.5, tile, ridge_frac=0.4)]
objs[-1].location = (11, -1, 0)
objs += windows("f", 16, 8, [1.7], dark, 4, 2, ww=1.0, wh=1.2)
for o in list(objs):
    if o.name.startswith("fw"):
        objs.append(box(o.name + "F", (o.scale.x + 0.2 if o.scale.x > o.scale.y else 0.12, o.scale.y + 0.2 if o.scale.y > o.scale.x else 0.12, o.scale.z + 0.2), tuple(o.location), white))
export("farmhouse_1938", objs)
