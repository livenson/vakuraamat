# Vakuraamat — Phase 0 hero prop: a manor boundary stone (piirikivi).
# Run headless:
#   /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/make_boundary_stone.py -- assets/models/props/boundary_stone.glb
# Generates a rough, tapered granite post with a carved cross and an
# engraved year band, then exports it as a single glTF binary with
# vertex colours (no external textures needed).
import bpy, bmesh, sys, math, random
from mathutils import Vector

out_path = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "boundary_stone.glb"
random.seed(1798)

# --- clean scene -----------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# --- base stone: tapered octagonal prism, ~1.1 m tall -----------------------
bm = bmesh.new()
bottom = [Vector((0.28 * math.cos(a), 0.22 * math.sin(a), 0.0)) for a in
          [i * math.tau / 8 + math.tau / 16 for i in range(8)]]
top = [Vector((0.20 * math.cos(a), 0.16 * math.sin(a), 1.10)) for a in
       [i * math.tau / 8 + math.tau / 16 for i in range(8)]]
vb = [bm.verts.new(v) for v in bottom]
vt = [bm.verts.new(v) for v in top]
bm.faces.new(vb[::-1])
bm.faces.new(vt)
for i in range(8):
    bm.faces.new((vb[i], vb[(i + 1) % 8], vt[(i + 1) % 8], vt[i]))
bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=0.035, segments=2, affect='EDGES')
bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
# rough the surface a little so it reads as fieldstone
for v in bm.verts:
    if v.co.z > 0.02:
        v.co += Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-0.6, 0.6))) * 0.012
bm.normal_update()
mesh = bpy.data.meshes.new("BoundaryStone")
bm.to_mesh(mesh)
bm.free()
stone = bpy.data.objects.new("BoundaryStone", mesh)
scene.collection.objects.link(stone)

# --- vertex colours: granite grey with a lichen tint near the base ----------
col = mesh.color_attributes.new(name="Col", type='BYTE_COLOR', domain='CORNER')
for poly in mesh.polygons:
    for li in poly.loop_indices:
        z = mesh.vertices[mesh.loops[li].vertex_index].co.z
        g = 0.42 + random.uniform(-0.05, 0.05)
        lichen = max(0.0, 0.25 - z) * 1.2
        col.data[li].color = (g - lichen * 0.1, g + lichen * 0.08, g - lichen * 0.15, 1.0)

# --- carved cross on the north face (−Y) ------------------------------------
def bar(name, size, loc):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    return o
cross_v = bar("CrossV", (0.05, 0.04, 0.34), (0.0, -0.215, 0.78))
cross_h = bar("CrossH", (0.22, 0.04, 0.05), (0.0, -0.215, 0.84))
for o in (cross_v, cross_h):
    mod = stone.modifiers.new("Carve_" + o.name, 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.object = o
    mod.solver = 'EXACT'
bpy.context.view_layer.objects.active = stone
for m in list(stone.modifiers):
    bpy.ops.object.modifier_apply(modifier=m.name)
for o in (cross_v, cross_h):
    bpy.data.objects.remove(o, do_unlink=True)

# --- material: plain principled, reads the vertex colour --------------------
mat = bpy.data.materials.new("Granite")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.9
# Base colour is a plain granite grey so the prop reads correctly even if a viewer ignores
# vertex colours; the exported COLOR_0 attribute multiplies it (glTF spec) in Godot.
bsdf.inputs["Base Color"].default_value = (0.62, 0.61, 0.58, 1.0)
# The COLOR_0 attribute is still exported (export_vertex_color='ACTIVE') for engines that
# multiply it in; Godot's glTF importer leaves it unused unless the material opts in.
mesh.materials.clear()  # boolean cutters leave an empty slot at index 0; granite must be slot 0
mesh.materials.append(mat)

# --- smooth-by-angle so the bevels read as stone, then export ---------------
bpy.ops.object.select_all(action='DESELECT')
stone.select_set(True)
bpy.context.view_layer.objects.active = stone
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', use_selection=True,
                          export_apply=True, export_yup=True,
                          export_vertex_color='ACTIVE')
print("exported", out_path, "verts", len(mesh.vertices), "faces", len(mesh.polygons))
