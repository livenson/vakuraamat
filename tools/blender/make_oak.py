# Vakuraamat hero prop: the oak, the anchor landmark present in every era.
#   Blender -b -P tools/blender/make_oak.py -- assets/models/props/oak.glb
# Tapered trunk, four bent limbs, a canopy of overlapping lumpy spheres with vertex
# colours, flared roots. ~2.5k faces. Base at the origin, ~14 m tall at scale 1.
import bpy, bmesh, sys, math, random
from mathutils import Vector, Matrix

out_path = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "oak.glb"
random.seed(7)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

bark = bpy.data.materials.new("OakBark"); bark.use_nodes = True
bark.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.30, 0.22, 0.15, 1)
bark.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
leaf = bpy.data.materials.new("OakLeaf"); leaf.use_nodes = True
leaf.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.20, 0.36, 0.12, 1)
leaf.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9

def limb(p0, p1, r0, r1, segs=8):
    """Tapered tube between two points (slightly bent)."""
    bm = bmesh.new()
    d = p1 - p0; n = 6
    rings = []
    for i in range(n + 1):
        t = i / n
        c = p0.lerp(p1, t) + Vector((math.sin(t * 3) * 0.15, math.cos(t * 2) * 0.15, 0)) * d.length * 0.08
        r = r0 * (1 - t) + r1 * t
        axis = d.normalized()
        u = axis.cross(Vector((0, 0, 1))) if abs(axis.z) < 0.9 else axis.cross(Vector((1, 0, 0)))
        u.normalize(); v = axis.cross(u)
        ring = [bm.verts.new(c + (u * math.cos(a) + v * math.sin(a)) * r * random.uniform(0.9, 1.1)) for a in [k * math.tau / segs for k in range(segs)]]
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    bm.faces.new(rings[-1][::-1])
    return bm

parts = []
def add_part(bm, name, mat):
    m = bpy.data.meshes.new(name); bm.to_mesh(m); bm.free(); m.materials.append(mat)
    o = bpy.data.objects.new(name, m); scene.collection.objects.link(o); parts.append(o); return o

# trunk and roots
add_part(limb(Vector((0, 0, -0.2)), Vector((0.1, 0, 6.0)), 0.75, 0.45), "Trunk", bark)
for k in range(5):
    a = k * math.tau / 5 + 0.3
    add_part(limb(Vector((math.cos(a) * 0.4, math.sin(a) * 0.4, 0.5)), Vector((math.cos(a) * 2.2, math.sin(a) * 2.2, -0.1)), 0.35, 0.08), f"Root{k}", bark)
# limbs
tops = []
for k in range(4):
    a = k * math.tau / 4 + 0.6
    p0 = Vector((0.1, 0, 5.2 + k * 0.3)); p1 = Vector((math.cos(a) * 4.5, math.sin(a) * 4.5, 8.5 + random.uniform(0, 1.5)))
    add_part(limb(p0, p1, 0.4, 0.12), f"Limb{k}", bark); tops.append(p1)
    p2 = p1 + Vector((math.cos(a + 0.8) * 2.5, math.sin(a + 0.8) * 2.5, 1.8))
    add_part(limb(p1, p2, 0.12, 0.04), f"Twig{k}", bark); tops.append(p2)
# canopy
for i, c in enumerate(tops + [Vector((0, 0, 10.5)), Vector((1.5, -1.0, 12.0)), Vector((-1.2, 1.4, 11.5))]):
    r = random.uniform(2.6, 3.8)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r, location=c + Vector((0, 0, 0.8)))
    o = bpy.context.active_object; o.name = f"Canopy{i}"
    for v in o.data.vertices:
        v.co += Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-0.5, 0.5))) * 0.35
    o.data.materials.append(leaf); parts.append(o)

bpy.ops.object.select_all(action='DESELECT')
for o in parts: o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
oak = bpy.context.active_object; oak.name = "Oak"
bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True)
print("exported", out_path, "verts", len(oak.data.vertices), "faces", len(oak.data.polygons))
