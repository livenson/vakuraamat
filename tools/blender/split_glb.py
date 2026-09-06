"""Split a Sketchfab pack into one glb per model group, headless Blender.

    blender --background --python tools/blender/split_glb.py -- <pack.glb> <out_dir> "<Name>=<regex>" ...

Each "<Name>=<regex>" names an output file <out_dir>/<name>.glb holding every object whose name
matches the regex (case-insensitive), plus their children. Objects matched by no group are dropped.
Sketchfab wraps everything in Sketchfab_model/root/... : the exported scene keeps world
transforms, so the parts of one car stay where they were relative to each other; each output is
re-centred on the ground (min y = 0, xz centre = 0).

    blender --background --python tools/blender/split_glb.py -- /tmp/cars.glb assets/vendor/sketchfab \\
        "car_sedan=^Sedan Body" "car_wagon=^Wagon Body"      # wheels under each body are adopted
    blender --background --python tools/blender/split_glb.py -- /tmp/plants.glb out --no-adopt "potato=^Potato_Plants_0$"
"""
import os, re, sys

import bpy


def log(msg):
    print(f"[split_glb] {msg}", flush=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    src, out_dir, groups = argv[0], argv[1], argv[2:]
    adopt = "--no-adopt" not in groups   # by default loose objects (wheels) join the body they sit under
    groups = [g for g in groups if g != "--no-adopt"]
    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    log(f"{src}: {len(meshes)} mesh objects")
    # bake world transforms so the parenting chain can be dropped
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.select_all(action="DESELECT")
    from mathutils import Vector

    def bounds(objs):
        xs, ys, zs = [], [], []
        for o in objs:
            for v in o.bound_box:
                w = o.matrix_world @ Vector(v)
                xs.append(w.x); ys.append(w.y); zs.append(w.z)
        return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)

    matched = set()
    named = {}
    for spec in groups:
        name, pattern = spec.split("=", 1)
        rx = re.compile(pattern, re.I)
        named[name] = [o for o in meshes if rx.search(o.name)]
        matched.update(o.name for o in named[name])
    loose = [o for o in meshes if o.name not in matched] if adopt else []   # wheels and the like: adopted by the body they sit under
    for name, chosen in named.items():
        if not chosen:
            log(f"{name}: nothing matched")
            continue
        x0, x1, y0, y1, z0, z1 = bounds(chosen)
        for o in loose:
            lx0, lx1, ly0, ly1, lz0, lz1 = bounds([o])
            c = ((lx0 + lx1) / 2, (ly0 + ly1) / 2)
            if x0 <= c[0] <= x1 and y0 <= c[1] <= y1 and lz1 <= z1 + 0.1:
                chosen.append(o)
        # undo the pack's arrangement: a car pack places its cars in a circle, each facing outward.
        # The body's long horizontal axis (2D principal axis of its world vertices) becomes +Y, the
        # end farther from the pack's origin is taken as the front.
        import math
        from mathutils import Matrix
        body = chosen[0]
        pts = [body.matrix_world @ v.co for v in body.data.vertices]
        mx = sum(p.x for p in pts) / len(pts); my = sum(p.y for p in pts) / len(pts)
        sxx = sum((p.x - mx) ** 2 for p in pts); syy = sum((p.y - my) ** 2 for p in pts); sxy = sum((p.x - mx) * (p.y - my) for p in pts)
        theta = 0.5 * math.atan2(2 * sxy, sxx - syy)          # direction of the long axis
        ax = Vector((math.cos(theta), math.sin(theta), 0.0))
        if ax.dot(Vector((mx, my, 0.0))) < 0:                  # the front points away from the pack centre
            ax = -ax
        yaw = math.atan2(ax.x, ax.y)                          # rotation taking ax onto +Y
        undo = Matrix.Rotation(yaw, 4, "Z")
        for o in chosen:
            o.matrix_world = undo @ o.matrix_world
        bpy.context.view_layer.update()
        # ground and centre the group
        x0, x1, y0, y1, z0, z1 = bounds(chosen)
        cx, cy, zmin = (x0 + x1) / 2, (y0 + y1) / 2, z0
        for o in chosen:
            o.location.x -= cx
            o.location.y -= cy
            o.location.z -= zmin
        bpy.ops.object.select_all(action="DESELECT")
        for o in chosen:
            o.select_set(True)
        out = os.path.join(out_dir, name + ".glb")
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True)
        for o in chosen:   # put the group back so the next group is measured from its own place
            o.location.x += cx
            o.location.y += cy
            o.location.z += zmin
            o.matrix_world = undo.inverted() @ o.matrix_world
        bpy.context.view_layer.update()
        log(f"{name}: {len(chosen)} objects -> {out}")


main()
