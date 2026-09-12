"""Roofs from laser heights for buildings without a 3D model (docs/latvia-plan.md, step 4).

Outside Rīga Latvia has no LOD2 models, and without one `footprint_building.gd` extrudes a footprint to
a flat roof: right for a Soviet block, wrong for a farmhouse. LĢIA's laser points are classified, and
`fetch_tile_lv` keeps the building class as the highest return per metre above the ground
(`<tile>_roofs.r32`). This fits a roof to those heights and writes it as the LOD2 faces the engine
already draws.

Candidates, each laid on the footprint's minimum rotated rectangle: flat, a gable with its ridge along
the long side, a gable with its ridge across it, and a hip roof. Each candidate's eave and ridge
heights are read from the cells (a low percentile near the eaves, a high one along the ridge), its
surface is compared with every cell under the footprint, and the one with the smallest error wins; a
pitched roof has to beat the flat one by a margin, so a roof the laser barely resolves stays flat.
Only footprints that fill most of their rectangle get a pitched roof (an L-shaped house under a
rectangle's roof would overhang its own yard); the rest keep the flat roof at the measured height.
"""
import numpy as np

MIN_FILL = 0.82        # footprint area / rectangle area for a pitched roof
MIN_CELLS = 12         # laser cells under a footprint needed to judge a roof
MIN_RISE = 0.8         # metres between eave and ridge below which a roof is flat
FLAT_MARGIN = 0.85     # a pitched candidate must reach this fraction of the flat error to win


def _rect(poly):
    """The minimum rotated rectangle of a footprint: (corners 4x2 with the long side first, fill ratio)."""
    import warnings
    from shapely.geometry import Polygon
    p = Polygon(poly)
    if not p.is_valid:
        p = p.buffer(0)
    with warnings.catch_warnings():   # GEOS divides by an edge of zero length on axis-aligned outlines
        warnings.simplefilter("ignore", RuntimeWarning)
        r = p.minimum_rotated_rectangle
    c = np.array(r.exterior.coords[:4], dtype=float)
    if np.linalg.norm(c[1] - c[0]) < np.linalg.norm(c[2] - c[1]):
        c = np.roll(c, -1, axis=0)       # c0 -> c1 is a long side
    return c, (p.area / r.area if r.area > 0 else 0.0)


def cells_in(poly, raster):
    """Cell centres inside a footprint (tile metres, x east, z south) with their raster values."""
    from shapely import contains_xy
    from shapely.geometry import Polygon
    p = Polygon(poly)
    if not p.is_valid:
        p = p.buffer(0)
    x0, z0, x1, z1 = p.bounds
    size = raster.shape[0]
    xs = np.arange(max(int(x0), 0), min(int(x1) + 1, size))
    zs = np.arange(max(int(z0), 0), min(int(z1) + 1, size))
    if xs.size == 0 or zs.size == 0:
        return np.zeros((0, 2)), np.zeros(0)
    gx, gz = np.meshgrid(xs + 0.5, zs + 0.5)
    inside = contains_xy(p, gx, gz)
    pts = np.stack([gx[inside], gz[inside]], axis=1)
    vals = raster[(pts[:, 1] - 0.5).astype(int), (pts[:, 0] - 0.5).astype(int)]
    return pts, vals


def _frame(c):
    """Origin, unit long axis, unit short axis, long length, short length of a rectangle."""
    o = c[0]
    u = c[1] - c[0]
    lu = np.linalg.norm(u)
    v = c[3] - c[0]
    lv = np.linalg.norm(v)
    return o, u / lu, v / lv, lu, lv


def _surface(kind, s, t, L, W, eave, ridge):
    """Height of a candidate roof at rectangle coordinates (s along the long side, t across)."""
    rise = ridge - eave
    if kind == "flat":
        return np.full_like(s, ridge)
    if kind == "gable_long":        # ridge along the long axis, at t = W/2
        return eave + rise * (1 - np.abs(t - W / 2) / (W / 2))
    if kind == "gable_short":       # ridge across, at s = L/2
        return eave + rise * (1 - np.abs(s - L / 2) / (L / 2))
    if kind == "hip":               # four slopes of one pitch, the ridge shortened by W at each end
        h_side = 1 - np.abs(t - W / 2) / (W / 2)
        h_end = np.minimum(s, L - s) / (W / 2)
        return eave + rise * np.clip(np.minimum(h_side, h_end), 0, 1)
    raise ValueError(kind)


def fit(poly, raster):
    """The best roof for a footprint: {kind, eave, ridge, corners, error} or None when the laser says
    too little. Heights are metres above the ground."""
    pts, vals = cells_in(poly, raster)
    good = vals > 1.5
    if good.sum() < MIN_CELLS:
        return None
    pts, vals = pts[good], vals[good]
    c, fill = _rect(poly)
    o, eu, ev, L, W = _frame(c)
    rel = pts - o
    s, t = rel @ eu, rel @ ev
    ridge = float(np.percentile(vals, 95))
    flat_h = float(np.percentile(vals, 70))
    near_long = np.minimum(t, W - t) < 1.5
    near_short = np.minimum(s, L - s) < 1.5
    best = {"kind": "flat", "eave": flat_h, "ridge": flat_h, "corners": c, "error": float(np.sqrt(np.mean((vals - flat_h) ** 2)))}
    if fill < MIN_FILL or W < 4.0:
        return best
    for kind, band in (("gable_long", near_long), ("gable_short", near_short), ("hip", near_long | near_short)):
        eave = float(np.percentile(vals[band], 30)) if band.sum() >= 4 else float(np.percentile(vals, 10))
        if ridge - eave < MIN_RISE:
            continue
        err = float(np.sqrt(np.mean((vals - _surface(kind, s, t, L, W, eave, ridge)) ** 2)))
        if err < best["error"] * (FLAT_MARGIN if best["kind"] == "flat" else 1.0):
            best = {"kind": kind, "eave": eave, "ridge": ridge, "corners": c, "error": err}
    return best


def _oriented(face, want_up, centre):
    """Wind a face (list of [x, y, z]) so the engine's Newell normal points up (roofs) or away from the
    building's centre (walls)."""
    p = np.array(face, dtype=float)
    n = np.zeros(3)
    for i in range(len(p)):
        n += np.cross(p[i], p[(i + 1) % len(p)])
    if want_up:
        flip = n[1] < 0
    else:
        mid = p.mean(axis=0)
        flip = (mid[0] - centre[0]) * n[0] + (mid[2] - centre[1]) * n[2] < 0
    return [list(map(float, q)) for q in (p[::-1] if flip else p)]


def faces(roof, bx, bz):
    """The pack's LOD2 faces for a fitted roof: x east and z south relative to the building's centre
    (bx, bz), y up from the ground. Walls rise to the eave (to the ridge on a gable's end)."""
    c = roof["corners"]
    o, eu, ev, L, W = _frame(c)
    e, r = round(roof["eave"], 2), round(roof["ridge"], 2)

    def P(s, t, y):
        q = o + eu * s + ev * t
        return [round(float(q[0]) - bx, 2), y, round(float(q[1]) - bz, 2)]
    centre = (0.0, 0.0)
    out = []
    kind = roof["kind"]
    g0, g1, g2, g3 = P(0, 0, 0.0), P(L, 0, 0.0), P(L, W, 0.0), P(0, W, 0.0)
    if kind == "flat":
        top = [P(0, 0, r), P(L, 0, r), P(L, W, r), P(0, W, r)]
        out.append(_oriented(top, True, centre))
        for a, b, ta, tb in ((g0, g1, top[0], top[1]), (g1, g2, top[1], top[2]), (g2, g3, top[2], top[3]), (g3, g0, top[3], top[0])):
            out.append(_oriented([a, b, tb, ta], False, centre))
        return out
    if kind == "gable_long":
        rA, rB = P(0, W / 2, r), P(L, W / 2, r)
        out.append(_oriented([P(0, 0, e), P(L, 0, e), rB, rA], True, centre))
        out.append(_oriented([P(L, W, e), P(0, W, e), rA, rB], True, centre))
        out.append(_oriented([g0, g1, P(L, 0, e), P(0, 0, e)], False, centre))
        out.append(_oriented([g2, g3, P(0, W, e), P(L, W, e)], False, centre))
        out.append(_oriented([g1, g2, P(L, W, e), rB, P(L, 0, e)], False, centre))   # gable ends
        out.append(_oriented([g3, g0, P(0, 0, e), rA, P(0, W, e)], False, centre))
        return out
    if kind == "gable_short":
        rA, rB = P(L / 2, 0, r), P(L / 2, W, r)
        out.append(_oriented([P(0, 0, e), P(0, W, e), rB, rA], True, centre))
        out.append(_oriented([P(L, W, e), P(L, 0, e), rA, rB], True, centre))
        out.append(_oriented([g1, g2, P(L, W, e), P(L, 0, e)], False, centre))
        out.append(_oriented([g3, g0, P(0, 0, e), P(0, W, e)], False, centre))
        out.append(_oriented([g0, g1, P(L, 0, e), rA, P(0, 0, e)], False, centre))
        out.append(_oriented([g2, g3, P(0, W, e), rB, P(L, W, e)], False, centre))
        return out
    # hip: the ridge inset by half the width at each end (one pitch all round); a square house is a pyramid
    inset = min(W / 2, L / 2)
    rA, rB = P(inset, W / 2, r), P(L - inset, W / 2, r)
    e0, e1, e2, e3 = P(0, 0, e), P(L, 0, e), P(L, W, e), P(0, W, e)
    out.append(_oriented([e0, e1, rB, rA] if L - 2 * inset > 0.05 else [e0, e1, rA], True, centre))
    out.append(_oriented([e2, e3, rA, rB] if L - 2 * inset > 0.05 else [e2, e3, rA], True, centre))
    out.append(_oriented([e1, e2, rB], True, centre))
    out.append(_oriented([e3, e0, rA], True, centre))
    for a, b, ta, tb in ((g0, g1, e0, e1), (g1, g2, e1, e2), (g2, g3, e2, e3), (g3, g0, e3, e0)):
        out.append(_oriented([a, b, tb, ta], False, centre))
    return out
