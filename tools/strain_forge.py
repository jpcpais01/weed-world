#!/usr/bin/env python3
"""Forges the rarer weed strains out of João's four Meshy models.

Nothing here is a recolour: every strain gets its own plant silhouette and
its own bud shape, kit-bashed from the real Meshy geometry.

  * A whole Meshy plant, shrunk down, reads as one leafy branch. Those
    "sprigs" are bent along procedural curves (each vertex rides the curve by
    its height, in a parallel-transport frame) so they arch, droop, twist and
    curl, and are hung off new skeletons: helices, whorled spires, weeping
    fountains, candelabras, cloud-pruned bonsai pads, lotus rosettes...
  * Stems are the bare twisted trunk cut from the Verdant model, tiled and
    bent along the skeleton's curves, or plain tapered tubes textured from a
    patch of bark in the atlas.
  * Buds are the rounded Meshy bud (see weed_assets.round_bud) reshaped:
    twisted into swirls, stacked into foxtails, spherised, ribbed into
    lanterns, clustered into popcorn and clouds, braided into twins.
  * Each strain gets its own palette baked into its atlas (up to two Meshy
    atlases side by side, so hybrids keep both parents' leaves).

Outputs (per strain id): assets/weed/strains/<id>.glb (plant, metres, root at
the origin), <id>_bud.glb (bud, ~0.95 units tall like the original) and
<id>.json (bud anchors: position + growth direction, metres). Composites are
simplified to a phone budget with MeshLab's texture-aware decimation
(`pip install pymeshlab numpy pillow`); Godot builds LODs on import.

usage: python3 tools/strain_forge.py <dir with the 4 Meshy glbs> assets/weed/strains [id ...]
  (sources kept in the project files under weed-source/)
"""
import io, json, math, os, sys, tempfile
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from weed_assets import read_glb, weld, round_bud  # noqa: E402

SRC_PREFIX = {
    "ember": "Meshy_AI_Enchanted_Herb_Bloom",
    "starlit": "Meshy_AI_Starlit_Verdant_Bloom",
    "verdant": "Meshy_AI_Enchanted_Verdant_Spr",
    "bud": "Meshy_AI_Enchanted_Bloom_Tree",
}
TEX = 1024          # each source atlas in a strain texture
BUD_TEX = 512
BUD_H = 0.95        # bud models stay the size WeedKit.BUD_SCALE expects


# ---------------------------------------------------------------------------
# Mesh soup

class M:
    """Triangle soup with UVs; `slot` is which source atlas the UVs index and
    `lock` marks geometry the simplifier must leave alone (stems: a thin tube
    has no volume to spare and collapses into a flat ribbon)."""

    def __init__(self, pos, uv, idx, slot=None, lock=None):
        self.pos = np.asarray(pos, np.float64)
        self.uv = np.asarray(uv, np.float64)
        self.idx = np.asarray(idx, np.int64).reshape(-1, 3)
        self.slot = np.zeros(len(self.pos), np.int64) if slot is None else np.asarray(slot, np.int64)
        self.lock = np.zeros(len(self.pos), bool) if lock is None else np.asarray(lock, bool)

    def copy(self):
        return M(self.pos.copy(), self.uv.copy(), self.idx.copy(), self.slot.copy(), self.lock.copy())

    def map(self, fn):
        m = self.copy()
        m.pos = fn(m.pos)
        return m

    def tris(self):
        return len(self.idx)


def concat(ms):
    ms = [m for m in ms if m is not None and m.tris() > 0]
    off, idx = 0, []
    for m in ms:
        idx.append(m.idx + off)
        off += len(m.pos)
    return M(np.concatenate([m.pos for m in ms]), np.concatenate([m.uv for m in ms]),
             np.concatenate(idx), np.concatenate([m.slot for m in ms]), np.concatenate([m.lock for m in ms]))


def cut(m, keep):
    """Keeps the triangles whose centroid passes keep(centroids)."""
    c = m.pos[m.idx].mean(1)
    idx = m.idx[keep(c)]
    used = np.unique(idx)
    remap = -np.ones(len(m.pos), np.int64)
    remap[used] = np.arange(len(used))
    return M(m.pos[used], m.uv[used], remap[idx], m.slot[used], m.lock[used])


def rot(axis, ang):
    axis = np.asarray(axis, np.float64)
    axis = axis / np.linalg.norm(axis)
    x, y, z = axis
    c, s, C = math.cos(ang), math.sin(ang), 1 - math.cos(ang)
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def xform(m, R=None, t=(0, 0, 0), s=1.0):
    R = np.eye(3) if R is None else R
    S = np.diag(s) if np.ndim(s) else np.eye(3) * s
    return m.map(lambda p: p @ (R @ S).T + np.asarray(t))


def vnormals(pos, idx):
    """Area-weighted vertex normals, shared across corners at one position."""
    key = np.round(pos / 1e-6).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    fn = np.cross(pos[idx[:, 1]] - pos[idx[:, 0]], pos[idx[:, 2]] - pos[idx[:, 0]])
    acc = np.zeros((inv.max() + 1, 3))
    for k in range(3):
        np.add.at(acc, inv[idx[:, k]], fn)
    n = acc[inv]
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)


# ---------------------------------------------------------------------------
# Curves: Catmull-Rom through control points, resampled by arc length, with
# parallel-transport frames so bent geometry never flips or twists by itself.

class Curve:
    def __init__(self, pts, up_hint=(0, 0, 1), samples=96):
        P = np.asarray(pts, np.float64)
        if len(P) == 2:
            P = np.array([P[0], P[0] * 2 / 3 + P[1] / 3, P[0] / 3 + P[1] * 2 / 3, P[1]])
        ext = np.concatenate([[2 * P[0] - P[1]], P, [2 * P[-1] - P[-2]]])
        dense = []
        for i in range(len(P) - 1):
            p0, p1, p2, p3 = ext[i], ext[i + 1], ext[i + 2], ext[i + 3]
            for t in np.linspace(0, 1, 24, endpoint=False):
                t2, t3 = t * t, t * t * t
                dense.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                                    + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
        dense.append(P[-1])
        dense = np.array(dense)
        seg = np.linalg.norm(np.diff(dense, axis=0), axis=1)
        s = np.concatenate([[0], np.cumsum(seg)])
        self.length = s[-1]
        u = np.linspace(0, self.length, samples)
        self.p = np.stack([np.interp(u, s, dense[:, k]) for k in range(3)], 1)
        self.s = u
        T = np.gradient(self.p, axis=0)
        T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-12)
        N = np.zeros_like(T)
        n = np.asarray(up_hint, np.float64)
        n = n - T[0] * n.dot(T[0])
        if np.linalg.norm(n) < 1e-6:
            n = np.cross(T[0], [1, 0, 0])
        N[0] = n / np.linalg.norm(n)
        for i in range(1, len(T)):
            v = N[i - 1] - T[i] * N[i - 1].dot(T[i])
            N[i] = v / max(np.linalg.norm(v), 1e-12)
        self.T, self.N = T, N
        self.B = np.cross(T, N)

    def at(self, f):
        """Point, tangent, normal, binormal at fraction f (0..1) of the length."""
        f = np.clip(np.asarray(f, np.float64), 0, 1) * (len(self.s) - 1)
        i = np.minimum(f.astype(np.int64), len(self.s) - 2)
        w = (f - i)[..., None]
        lerp = lambda a: a[i] * (1 - w) + a[i + 1] * w
        return lerp(self.p), lerp(self.T), lerp(self.N), lerp(self.B)


def bend(m, curve, h=None, width=1.0, twist=0.0, taper=(1.0, 1.0), roll=0.0, f0=0.0, f1=1.0):
    """Lays a model whose axis is +Y (0..h) along a curve: height becomes arc
    length (the model stretches to the curve), x/z ride the frame scaled by
    `width`, tapering from taper[0] at the root to taper[1] at the tip and
    turning `twist` radians along the way."""
    h = m.pos[:, 1].max() if h is None else h
    f = np.clip(m.pos[:, 1] / h, 0, 1)
    p, T, N, B = curve.at(f0 + (f1 - f0) * f)
    ang = roll + twist * f
    sc = width * (taper[0] + (taper[1] - taper[0]) * f)
    x = m.pos[:, 0] * sc
    z = m.pos[:, 2] * sc
    c, s = np.cos(ang), np.sin(ang)
    xr, zr = x * c - z * s, x * s + z * c
    out = m.copy()
    out.pos = p + N * xr[:, None] + B * zr[:, None]
    return out


def tube(curve, r0, r1, uv_c, uv_r, sides=7, rings=None, slot=0, wobble=0.0, seed=0):
    """A tapered tube along a curve, its UVs spread over a little bark patch."""
    rings = rings or max(4, int(curve.length / 0.04))
    rng = np.random.default_rng(seed)
    f = np.linspace(0, 1, rings)
    p, T, N, B = curve.at(f)
    r = r0 + (r1 - r0) * f
    r = r * (1 + wobble * np.sin(f * 17 + rng.random() * 6))
    a = np.linspace(0, 2 * math.pi, sides, endpoint=False)
    pos = (p[:, None, :] + (N[:, None, :] * np.cos(a)[None, :, None] + B[:, None, :] * np.sin(a)[None, :, None])
           * r[:, None, None]).reshape(-1, 3)
    uv = np.stack(np.meshgrid(np.cos(a) * 0.5, f * 2 - 1), -1).reshape(-1, 2)
    uv = np.asarray(uv_c) + uv * uv_r
    idx = []
    for i in range(rings - 1):
        for j in range(sides):
            a0, a1 = i * sides + j, i * sides + (j + 1) % sides
            b0, b1 = a0 + sides, a1 + sides
            idx += [[a0, b0, a1], [a1, b0, b1]]
    # Cap the tip so a cut-off stem never shows a hole.
    tip = len(pos)
    pos = np.vstack([pos, p[-1] + T[-1] * r[-1] * 0.6])
    uv = np.vstack([uv, uv_c])
    for j in range(sides):
        idx.append([(rings - 1) * sides + j, tip, (rings - 1) * sides + (j + 1) % sides])
    return M(pos, uv, idx, np.full(len(pos), slot), np.ones(len(pos), bool))


# ---------------------------------------------------------------------------
# Sources

_cache = {}


def source(name):
    """A Meshy model welded, plants standing on their root with height 1.0,
    the bud rounded and centred with height 1.0."""
    if name in _cache:
        return _cache[name]
    files = os.listdir(SRC_DIR)
    path = os.path.join(SRC_DIR, next(f for f in files if SRC_PREFIX[name] in f and f.endswith(".glb")))
    g = read_glb(path)
    if name == "bud":
        pos, nrm, uv, idx = round_bud(g)
    else:
        pos = g["pos"].copy()
        lo, hi = pos.min(0), pos.max(0)
        pos[:, 0] -= (lo[0] + hi[0]) * 0.5
        pos[:, 2] -= (lo[2] + hi[2]) * 0.5
        pos[:, 1] -= lo[1]
        nrm, uv, idx = g["nrm"], g["uv"], g["idx"]
    pos, nrm, uv, idx = weld(pos, nrm, uv, idx)
    h = pos[:, 1].max() - pos[:, 1].min()
    pos = pos / h
    if name == "plant_verdant" or name == "verdant":
        pass
    img = Image.open(io.BytesIO(g["base"])).convert("RGB")
    nimg = Image.open(io.BytesIO(g["normal"])).convert("RGB") if g["normal"] else None
    _cache[name] = (M(pos, uv, idx), img, nimg)
    return _cache[name]


def simplify(m, target):
    """Texture-aware quadric decimation (MeshLab). Meshy atlases are cut into
    hundreds of UV charts, which stop seam-respecting simplifiers (gltfpack,
    meshoptimizer) at ~40%; MeshLab collapses across seams while keeping each
    corner's UV, so composites reach a phone budget without smeared texels."""
    if m.tris() <= target:
        return m.copy()
    locked = m.lock[m.idx].any(1)
    if locked.any():
        rigid = cut(m, lambda c, l=locked: l)
        soft = cut(m, lambda c, l=locked: ~l)
        return concat([rigid, simplify(soft, max(target - rigid.tris(), soft.tris() // 8))])
    import pymeshlab
    from weed_assets import weld_ids
    w = weld_ids(m.pos, 1e-6)
    P = np.zeros((w.max() + 1, 3))
    P[w] = m.pos
    F = w[m.idx]
    uv = m.uv.copy()
    uv[:, 0] += m.slot  # keep atlas slots apart while simplifying
    with tempfile.TemporaryDirectory() as d:
        Image.new("RGB", (8, 8)).save(os.path.join(d, "t.png"))
        with open(os.path.join(d, "m.mtl"), "w") as fh:
            fh.write("newmtl a\nmap_Kd t.png\n")
        with open(os.path.join(d, "m.obj"), "w") as fh:
            fh.write("mtllib m.mtl\nusemtl a\n")
            fh.write("".join("v %.6f %.6f %.6f\n" % tuple(p) for p in P))
            fh.write("".join("vt %.6f %.6f\n" % (u[0], 1 - u[1]) for u in uv))
            fh.write("".join("f %d/%d %d/%d %d/%d\n" % (a + 1, i + 1, b + 1, j + 1, c + 1, k + 1)
                             for (a, b, c), (i, j, k) in zip(F, m.idx)))
        ms = pymeshlab.MeshSet()
        ms.load_new_mesh(os.path.join(d, "m.obj"))
        ms.meshing_decimation_quadric_edge_collapse_with_texture(
            targetfacenum=int(target), qualitythr=0.3, extratcoordw=1.0, preserveboundary=False,
            optimalplacement=True, preservenormal=True, planarquadric=False)
        o = ms.current_mesh()
        V, Fo, W = o.vertex_matrix(), o.face_matrix(), o.wedge_tex_coord_matrix()
    pos = V[Fo].reshape(-1, 3)
    W = W.reshape(-1, 2)
    slot = np.floor(np.clip(W[:, 0], 0, 7.999)).astype(np.int64)
    # One slot per triangle (its first corner's), so no face straddles two atlases.
    slot = np.repeat(slot.reshape(-1, 3)[:, 0], 3)
    uvo = np.stack([W[:, 0] - slot, 1 - W[:, 1]], 1)
    return M(pos, uvo, np.arange(len(pos)).reshape(-1, 3), slot)


def lod(name, tris):
    """A source model pre-simplified to about `tris` triangles: a sprig a
    few centimetres long needs a fraction of the Meshy detail."""
    key = (name, tris)
    if key not in _cache:
        _cache[key] = simplify(source(name)[0], tris)
    return _cache[key].copy()


# Where each plant's bare foot ends: sprigs drop it so every centimetre of a
# branch carries leaves (the Verdant model stands on a long bare trunk).
CROWN = {"ember": 0.08, "starlit": 0.06, "verdant": 0.24}


def sprig(name, length=0.4, flat=False):
    """A Meshy plant used as one leafy branch: its bare foot cut off, height
    renormalised to 1, with as much detail as its size on screen deserves
    (`flat` sprigs lie in pads and rosettes and are seen side-on less)."""
    tris = 2600 if length >= 0.5 else 2000 if length >= 0.36 else 1400
    if flat:
        tris = int(tris * 0.7)
    key = ("sprig", name, tris)
    if key not in _cache:
        m = lod(name, tris)
        c0 = CROWN[name]
        m = cut(m, lambda c: c[:, 1] > c0)
        m.pos[:, 1] = (m.pos[:, 1] - c0) / (m.pos[:, 1].max() - c0)
        m.pos[:, 1] = np.maximum(m.pos[:, 1], 0)
        _cache[key] = m
    return _cache[key].copy()


def trunk_piece():
    """The bare twisted trunk at the foot of the Verdant model, height 1,
    centred on its own axis: tiled along curves for gnarly stems."""
    m = lod("verdant", 2200)
    top = 0.26
    piece = cut(m, lambda c: (c[:, 1] < top) & (np.linalg.norm(c[:, [0, 2]] - np.median(c[c[:, 1] < top][:, [0, 2]], 0), axis=1) < 0.075))
    lo = piece.pos[:, 1].min()
    piece.pos[:, 1] -= lo
    ctr = piece.pos[piece.pos[:, 1] < 0.03][:, [0, 2]].mean(0)
    top_ctr = piece.pos[piece.pos[:, 1] > piece.pos[:, 1].max() - 0.03][:, [0, 2]].mean(0)
    # Lean it straight: shear so the top sits over the root.
    y = piece.pos[:, 1] / piece.pos[:, 1].max()
    piece.pos[:, 0] -= ctr[0] + (top_ctr[0] - ctr[0]) * y
    piece.pos[:, 2] -= ctr[1] + (top_ctr[1] - ctr[1]) * y
    hh = piece.pos[:, 1].max()
    return piece, hh


def trunk(curve, radius, taper=(1.0, 0.55), slot=0, twist=0.0):
    """The Verdant trunk tiled end to end along a curve, `radius` metres
    thick at the root."""
    piece, hh = trunk_piece()
    native_r = np.percentile(np.linalg.norm(piece.pos[:, [0, 2]], axis=1), 80)
    seg_len = max(hh / native_r * radius * 1.6, 0.22)  # roughly the bark's own proportions
    n = max(1, int(round(curve.length / seg_len)))
    parts = []
    for k in range(n):
        f0, f1 = k / n, (k + 1) / n
        t0 = taper[0] + (taper[1] - taper[0]) * f0
        t1 = taper[0] + (taper[1] - taper[0]) * f1
        w = radius / native_r
        part = bend(piece, curve, h=hh, width=w, taper=(t0, t1), f0=f0, f1=min(f1 + 0.02, 1.0),
                    roll=k * 2.1 + twist * f0, twist=twist / n)
        part.slot[:] = slot
        part.lock[:] = True
        parts.append(part)
    return concat(parts)


def bark_uv(name):
    """Centre and radius of a patch of bark in a source atlas (the stem's own
    texture at the plant's foot)."""
    m = source(name)[0]
    c = m.pos[m.idx].mean(1)
    ax = np.median(c[c[:, 1] < 0.08][:, [0, 2]], 0)
    sel = (c[:, 1] < 0.1) & (np.linalg.norm(c[:, [0, 2]] - ax, axis=1) < 0.04)
    uvs = m.uv[m.idx[sel]].reshape(-1, 2)
    med = np.median(uvs, 0)
    # The UV of the stem corner nearest the median, with a small radius.
    best = uvs[np.argmin(np.linalg.norm(uvs - med, axis=1))]
    return best, 0.006


# ---------------------------------------------------------------------------
# Palettes

def gradient_map(img, stops, amt=1.0, keep=None):
    """Repaints an image by luminance through a few colour stops (dark to
    light), keeping all the painted detail but giving it a designed palette.
    `keep` = (hue_lo, hue_hi) degrees of the original left alone (the orange
    pistil hairs on a bud, say)."""
    a = np.asarray(img, np.float32) / 255.0
    lum = a @ np.array([0.299, 0.587, 0.114], np.float32)
    lo, hi = np.percentile(lum, 2), np.percentile(lum, 98)
    t = np.clip((lum - lo) / max(hi - lo, 1e-4), 0, 1)
    st = np.asarray(stops, np.float32)
    x = np.linspace(0, 1, len(st))
    g = np.stack([np.interp(t, x, st[:, k]) for k in range(3)], -1)
    w = np.full(lum.shape, amt, np.float32)
    if keep:
        hsv = np.asarray(img.convert("HSV"), np.float32)
        h = hsv[..., 0] / 255.0 * 360.0
        sat = hsv[..., 1] / 255.0
        lo_h, hi_h = keep
        inside = (((h - lo_h) % 360) <= ((hi_h - lo_h) % 360)) & (sat > 0.35)
        w = np.where(inside, amt * 0.15, w)
    out = a * (1 - w[..., None]) + g * w[..., None]
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def recolor(img, hue=0.0, sat=1.0, val=1.0, tint=None, tint_amt=0.0, gamma=1.0, keep=None, grad=None, grad_amt=0.6):
    """Rotates hues (degrees), scales saturation and value, then pulls towards
    a tint by luminance. `keep` = (hue_lo, hue_hi) degrees left untouched
    (e.g. a strain keeping its pink veins while its greens change)."""
    a = np.asarray(img, np.float32) / 255.0
    mx, mn = a.max(2), a.min(2)
    d = mx - mn
    h = np.zeros_like(mx)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    m = d > 1e-6
    rr = m & (mx == r)
    gg = m & (mx == g) & ~rr
    bb = m & ~rr & ~gg
    h[rr] = ((g - b)[rr] / d[rr]) % 6
    h[gg] = (b - r)[gg] / d[gg] + 2
    h[bb] = (r - g)[bb] / d[bb] + 4
    h = h * 60.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    v = mx
    w = np.ones_like(h)
    if keep:
        lo, hi = keep
        inside = ((h - lo) % 360) <= ((hi - lo) % 360)
        w = np.where(inside, 0.0, 1.0)
    h = (h + hue * w) % 360
    s = np.clip(s * (1 + (sat - 1) * w), 0, 1)
    v = np.clip((v ** gamma) * (1 + (val - 1) * w), 0, 1)
    # hsv -> rgb
    hh = h / 60.0
    i = np.floor(hh).astype(np.int32) % 6
    f = hh - np.floor(hh)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    out = np.zeros_like(a)
    for k, (x, y, z) in enumerate([(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)]):
        sel = i == k
        out[..., 0][sel], out[..., 1][sel], out[..., 2][sel] = x[sel], y[sel], z[sel]
    if tint is not None and tint_amt > 0:
        lum = (out @ np.array([0.299, 0.587, 0.114], np.float32))[..., None]
        out = out * (1 - tint_amt) + lum * np.asarray(tint, np.float32) * 1.4 * tint_amt
    out = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))
    if grad:
        out = gradient_map(out, grad, grad_amt, keep)
    return out


# ---------------------------------------------------------------------------
# Writing

def jpeg_bytes(img, q=88):
    b = io.BytesIO()
    img.save(b, "JPEG", quality=q, optimize=True)
    return b.getvalue()


def png_bytes(img):
    b = io.BytesIO()
    img.save(b, "PNG", optimize=True)
    return b.getvalue()


def write(path, m, images, target_tris, nslots=1):
    """Simplifies to target_tris, welds and writes a glb."""
    from weed_assets import write_glb
    raw = m.tris()
    m = simplify(m, target_tris)
    uv = m.uv.copy()
    uv[:, 0] = (np.clip(uv[:, 0], 0, 1) + m.slot) / nslots
    nrm = vnormals(m.pos, m.idx)
    pos, nrm, uv, idx = weld(m.pos, nrm, uv, m.idx)
    write_glb(path, pos, nrm, uv, idx, images)
    return raw, len(idx), pos.min(0), pos.max(0)


def atlas(sources, palette):
    imgs = []
    for name in sources:
        im = source(name)[1].resize((TEX, TEX), Image.LANCZOS)
        imgs.append(recolor(im, **palette.get(name, palette.get("*", {}))))
    out = Image.new("RGB", (TEX * len(imgs), TEX))
    for k, im in enumerate(imgs):
        out.paste(im, (k * TEX, 0))
    return out


# ---------------------------------------------------------------------------
# Helpers for skeletons

def leaf_branch(name, root, direction, length, width=1.1, droop=0.0, curl=0.0, twist=0.0,
                spin=0.0, slot=0, taper=(1.0, 1.0), squash=1.0, flat=False):
    """A sprig laid along a curve from `root` heading `direction`, sagging by
    `droop` (metres at the tip) and curling up by `curl`. `spin` turns the
    sprig about its own axis first, `squash` flattens it front to back."""
    d = np.asarray(direction, np.float64)
    d = d / np.linalg.norm(d)
    p0 = np.asarray(root, np.float64)
    side = np.cross(d, [0, 1, 0])
    if np.linalg.norm(side) < 1e-6:
        side = np.array([1.0, 0, 0])
    side /= np.linalg.norm(side)
    pts = [p0 + d * length * f + np.array([0, 1, 0]) * (-droop * f * f + curl * f ** 3) for f in (0, 0.33, 0.66, 1.0)]
    c = Curve(pts, up_hint=side)
    m = sprig(name, length, flat)
    cs, sn = math.cos(spin), math.sin(spin)
    m.pos[:, [0, 2]] = m.pos[:, [0, 2]] @ np.array([[cs, -sn], [sn, cs]]).T
    m.pos[:, 2] *= squash
    out = bend(m, c, h=1.0, width=length * width, twist=twist, taper=taper)
    out.slot[:] = slot
    return out, pts[-1]


def hanging(name, top, out, length, width=0.9, twist=0.0, slot=0):
    """A sprig hanging straight down from `top`, swinging a little outwards."""
    out = np.asarray(out, np.float64)
    top = np.asarray(top, np.float64)
    c = Curve([top, top + out * 0.05 + [0, -length * 0.4, 0], top + out * 0.07 + [0, -length, 0]],
              up_hint=np.cross(out, [0, 1, 0]))
    m = sprig(name, length)
    m.pos[:, 2] *= 0.65
    # Hang it upside down so the leaves spill from the branch.
    m.pos[:, 1] = 1.0 - m.pos[:, 1]
    m.pos[:, [0, 2]] *= -1
    m = bend(m, c, h=1.0, width=length * width, twist=twist, taper=(1.0, 0.8))
    m.slot[:] = slot
    return m


def anchor(p, d=(0, 1, 0)):
    d = np.asarray(d, np.float64)
    return {"pos": [round(float(x), 4) for x in p], "dir": [round(float(x), 4) for x in d / np.linalg.norm(d)]}


def ring(n, phase=0.0):
    for k in range(n):
        a = k * 2 * math.pi / n + phase
        yield k, a, np.array([math.cos(a), 0.0, math.sin(a)])


GOLDEN = 2.39996


# ---------------------------------------------------------------------------
# The strains. Each returns (plant M, nslots, bud anchors). Metres, root at
# the origin. Buds must sit 0.25..1.0 m up so a Keling can pick them.

def corkscrew():
    """A stem that corkscrews up like a spring, sprigs spiralling off it in
    the golden angle, each one wrung into a twist."""
    turns, H = 1.75, 0.95
    pts = []
    for f in np.linspace(0, 1, 16):
        a = f * turns * 2 * math.pi
        r = 0.13 * (1 - f) ** 0.7 + 0.015
        pts.append([math.cos(a) * r, f * H, math.sin(a) * r])
    stem = Curve(pts)
    parts = [tube(stem, 0.026, 0.009, *bark_uv("ember"), sides=8)]
    anchors = []
    n = 8
    for k in range(n):
        f = 0.2 + 0.72 * k / (n - 1)
        p = stem.at(f)[0]
        a = k * GOLDEN
        out = np.array([math.cos(a), 0.0, math.sin(a)])
        d = out * 0.8 + [0, 0.5 + f * 0.6, 0]
        L = 0.52 - 0.2 * f
        br, tip = leaf_branch("ember", p, d, L, width=1.6, twist=2.2, curl=0.06, spin=a)
        parts.append(br)
        if k in (2, 5):
            anchors.append(anchor(p + (tip - p) * 0.45 + [0, 0.04, 0], d))
    p, T = stem.at(1.0)[:2]
    top, _ = leaf_branch("ember", p - T * 0.05, [0.05, 1, 0], 0.46, width=1.5, twist=3.0)
    parts.append(top)
    anchors.insert(0, anchor(p + T * 0.08, [0, 1, 0]))
    return concat(parts), 1, anchors


def mossy_mound():
    """A low, wide dome of leaves pushing out from a squat crown, like a
    mossy boulder that sprouted."""
    parts = []
    bark = bark_uv("verdant")
    for k, a, out in ring(3, 0.4):
        c = Curve([[0, 0, 0], out * 0.07 + [0, 0.12, 0], out * 0.13 + [0, 0.24, 0]])
        parts.append(tube(c, 0.035, 0.02, *bark, sides=7))
    rng = np.random.default_rng(7)
    n = 12
    for k in range(n):
        y = 1 - (k + 0.5) / n * 0.95
        r = math.sqrt(max(0, 1 - y * y))
        a = k * GOLDEN
        dirv = np.array([math.cos(a) * r, y * 0.8 + 0.2, math.sin(a) * r])
        root = np.array([0, 0.16, 0]) + dirv * 0.08
        L = 0.48 + rng.random() * 0.1
        br, _ = leaf_branch("verdant", root, dirv, L, width=1.7, droop=0.1 * r, spin=rng.random() * 6, squash=0.85)
        parts.append(br)
    anchors = [anchor([0.02, 0.62, 0.05], [0, 1, 0]), anchor([0.3, 0.44, 0.14], [0.6, 0.8, 0.2]),
               anchor([-0.26, 0.42, -0.2], [-0.5, 0.8, -0.4])]
    return concat(parts), 1, anchors


def starfish():
    """Arms that sprawl flat along the ground and curl up at the tips, like a
    starfish (or an agave), with a little crown in the middle."""
    parts, anchors = [], []
    for k, a, d in ring(5, 0.3):
        L = 0.8 + 0.07 * math.sin(k * 3.1)
        pts = [d * 0.02 + [0, 0.04, 0], d * L * 0.4 + [0, 0.08, 0], d * L * 0.78 + [0, 0.2, 0], d * L + [0, 0.52, 0]]
        c = Curve(pts, up_hint=np.cross(d, [0, 1, 0]))
        m = sprig("starlit", L)
        m.pos[:, 2] *= 0.6
        parts.append(bend(m, c, h=1.0, width=1.15, twist=0.25 * (-1) ** k, taper=(0.75, 1.15)))
    crown, _ = leaf_branch("starlit", [0, 0, 0], [0, 1, 0], 0.52, width=1.3, twist=1.0)
    parts.append(crown)
    anchors = [anchor([0, 0.52, 0], [0, 1, 0])]
    for k in (1, 3):
        a = k * 2 * math.pi / 5 + 0.3
        d = np.array([math.cos(a), 0.0, math.sin(a)])
        anchors.append(anchor(d * 0.78 + [0, 0.56, 0], d * 0.3 + [0, 1, 0]))
    return concat(parts), 1, anchors


def sky_spire():
    """A towering, slender sativa: whorls of long narrow sprigs, longest at
    the bottom, a Christmas-tree silhouette twice a Keling's height."""
    H = 2.2
    stem = Curve([[0, 0, 0], [0.03, H * 0.35, 0.01], [-0.02, H * 0.7, -0.015], [0.01, H, 0]])
    parts = [tube(stem, 0.032, 0.008, *bark_uv("ember"), sides=8)]
    anchors = []
    levels = 6
    for lv in range(levels):
        f = 0.12 + 0.8 * lv / (levels - 1)
        p = stem.at(f)[0]
        L = 0.75 * (1 - f) + 0.22
        n = 3
        for j in range(n):
            a = j * 2 * math.pi / n + lv * 1.05
            d = np.array([math.cos(a), 0.8 + f * 1.4, math.sin(a)])
            br, tip = leaf_branch("ember", p, d, L, width=1.4, droop=0.07 * (1 - f), spin=a, taper=(0.85, 1.0))
            parts.append(br)
            if (lv, j) in ((0, 0), (1, 2)):
                anchors.append(anchor(p + (tip - p) * 0.55 + [0, 0.03, 0], d))
    p, T = stem.at(1.0)[:2]
    top, _ = leaf_branch("ember", p - T * 0.04, [0, 1, 0], 0.4, width=1.0)
    parts.append(top)
    # The crown cola sits where a Keling can still reach it on tiptoe.
    p, T, N = stem.at(0.42)[:3]
    anchors.insert(0, anchor(p + N * 0.05, [0.2, 1, 0]))
    return concat(parts), 1, anchors


def bubblegum():
    """A topiary lollipop: a bare trunk holding up a perfect ball of leaves
    with a smaller ball balanced on top."""
    H = 0.58
    stem = Curve([[0, 0, 0], [0.02, H * 0.5, 0], [0, H + 0.1, 0.01]])
    parts = [trunk(stem, 0.032, taper=(1.0, 0.75))]

    def ball(c, R, n, seed):
        rng = np.random.default_rng(seed)
        for k in range(n):
            y = 1 - 2 * (k + 0.5) / n
            r = math.sqrt(max(0, 1 - y * y))
            a = k * GOLDEN
            d = np.array([math.cos(a) * r, y, math.sin(a) * r])
            br, _ = leaf_branch("verdant", np.asarray(c) - d * R * 0.15, d + [0, 0.2, 0], R * 1.1, width=1.5,
                                spin=rng.random() * 6, squash=0.8)
            parts.append(br)

    ball([0, H + 0.16, 0], 0.3, 11, 3)
    ball([0, H + 0.56, 0], 0.17, 6, 5)
    anchors = [anchor([0.05, H + 0.42, 0.18], [0.2, 1, 0.5]), anchor([0.31, H + 0.1, 0.12], [1, 0.2, 0.3]),
               anchor([-0.25, H + 0.04, -0.2], [-0.7, 0.1, -0.6])]
    return concat(parts), 1, anchors


def moonfeather():
    """A weeping willow: a leaning trunk fountains into long arching branches
    whose leaves hang in curtains, feathery buds dangling at the ends."""
    H = 1.2
    trunk_c = Curve([[0, 0, 0], [0.07, H * 0.45, 0.02], [0.0, H * 0.85, -0.02], [0.02, H, 0]])
    parts = [trunk(trunk_c, 0.045, taper=(1.0, 0.5), twist=0.8)]
    anchors = []
    top = trunk_c.at(1.0)[0]
    bark = bark_uv("starlit")
    for k, a, out in ring(7, 0.2):
        R = 0.52 + 0.08 * math.sin(k * 2.3)
        arc = Curve([top - [0, 0.04, 0], top + out * R * 0.35 + [0, 0.2, 0], top + out * R * 0.8 + [0, 0.1, 0],
                     top + out * R + [0, -0.22, 0]], up_hint=np.cross(out, [0, 1, 0]))
        parts.append(tube(arc, 0.013, 0.006, *bark, sides=6))
        for j, f in enumerate((0.55, 0.95)):
            p = arc.at(f)[0]
            L = 0.6 - 0.12 * j + 0.05 * math.sin(k + j)
            parts.append(hanging("starlit", p, out, L, width=1.5, twist=0.5 * ((k + j) % 2 * 2 - 1)))
            if j == 1 and k in (1, 3, 5):
                anchors.append(anchor(p + out * 0.07 + [0, -L - 0.04, 0], [0, -1, 0]))
    for k, a, out in ring(3, 0.5):
        br, _ = leaf_branch("starlit", top - [0, 0.05, 0], out * 0.4 + [0, 1, 0], 0.36, width=1.5)
        parts.append(br)
    return concat(parts), 1, anchors


def lantern():
    """A candelabra: a stout trunk splits into five arms that sweep out and
    turn upright, each holding up a glowing lantern bud."""
    stem = Curve([[0, 0, 0], [0.01, 0.18, 0], [0, 0.34, 0]])
    parts = [trunk(stem, 0.055, taper=(1.0, 0.85), slot=1)]
    anchors = []
    for k, a, out in ring(5):
        R = 0.36 if k % 2 == 0 else 0.25
        top = 0.9 if k % 2 == 0 else 0.78
        arm = Curve([[0, 0.32, 0], out * R * 0.55 + [0, 0.36, 0], out * R + [0, 0.48, 0], out * R + [0, top - 0.22, 0]])
        parts.append(trunk(arm, 0.024, taper=(1.0, 0.6), twist=1.0, slot=1))
        br, _ = leaf_branch("ember", out * R + [0, top - 0.3, 0], out * 0.15 + [0, 1, 0], 0.42, width=1.6, spin=a)
        parts.append(br)
        sk, _ = leaf_branch("ember", out * 0.08 + [0, 0.34, 0], out + [0, 0.25, 0], 0.36, width=1.7, droop=0.07, spin=a)
        parts.append(sk)
        if k in (0, 2, 3):
            anchors.append(anchor(out * R + [0, top + 0.03, 0], [0, 1, 0]))
    return concat(parts), 2, anchors


def cloud_bonsai():
    """A cloud-pruned bonsai: a gnarled S-curved trunk with branches ending
    in flat, round pads of leaves."""
    trunk_c = Curve([[0, 0, 0], [0.12, 0.22, 0.02], [-0.06, 0.5, -0.03], [0.08, 0.76, 0.0], [0.0, 0.98, 0.02]])
    parts = [trunk(trunk_c, 0.075, taper=(1.0, 0.45), slot=1, twist=1.2)]
    anchors = []
    pads = [(0.46, 0.2, 0.46, 0.38), (0.7, 2.9, 0.4, 0.34), (1.0, 0.0, 0.0, 0.34)]
    for i, (f, a, reach, R) in enumerate(pads):
        p = trunk_c.at(f)[0]
        out = np.array([math.cos(a), 0, math.sin(a)])
        centre = p + out * reach + [0, 0.1 if reach else 0.06, 0]
        if reach:
            br = Curve([p, p + out * reach * 0.5 + [0, 0.02, 0], centre - [0, 0.04, 0]])
            parts.append(trunk(br, 0.028, taper=(1.0, 0.55), slot=1))
        for k, b, d in ring(4, i * 0.7):
            m, _ = leaf_branch("ember", centre - d * 0.06, d + [0, 0.32, 0], R, width=2.5, curl=0.05, spin=b, flat=True)
            m.pos[:, 1] = centre[1] + (m.pos[:, 1] - centre[1]) * 0.6
            parts.append(m)
        # A domed cap so each pad reads as one soft cloud.
        cap, _ = leaf_branch("ember", centre - [0, 0.03, 0], [0, 1, 0], R * 0.75, width=2.4, spin=i, flat=True)
        cap.pos[:, 1] = centre[1] + (cap.pos[:, 1] - centre[1]) * 0.45
        parts.append(cap)
        anchors.append(anchor(centre + [0, 0.12, 0] + out * 0.04, [0, 1, 0]))
    return concat(parts), 2, [anchors[2], anchors[0], anchors[1]]


def sunset_braid():
    """A hybrid: an Ember stem and a Starlit stem twisting around each other
    in a double helix, each with its own parent's leaves, meeting in a crown
    of both."""
    H = 0.92
    parts, anchors = [], []
    for s in range(2):
        pts = []
        for f in np.linspace(0, 1, 18):
            a = f * 2.2 * 2 * math.pi + s * math.pi
            r = 0.055 * math.sin(min(f * 1.1, 1) * math.pi) + 0.014
            pts.append([math.cos(a) * r, f * H, math.sin(a) * r])
        c = Curve(pts)
        name = "ember" if s == 0 else "starlit"
        parts.append(tube(c, 0.024, 0.01, *bark_uv(name), sides=7, slot=s))
        for k in range(5):
            f = 0.26 + 0.14 * k + 0.07 * s
            p = c.at(f)[0]
            outv = np.array([p[0], 0, p[2]])
            outv = outv / np.linalg.norm(outv) if np.linalg.norm(outv) > 1e-4 else np.array([1.0, 0, 0])
            d = outv + [0, 0.8 + f * 0.7, 0]
            br, tip = leaf_branch(name, p, d, 0.42 - 0.14 * f, width=1.5, curl=0.04, spin=k + s, slot=s)
            parts.append(br)
            if (s, k) in ((0, 1), (1, 1)):
                anchors.append(anchor(p + (tip - p) * 0.45 + [0, 0.03, 0], d))
        top, _ = leaf_branch(name, c.at(1.0)[0] - [0, 0.04, 0], [0.3 * (1 - 2 * s), 1, 0.1], 0.38, width=1.2, slot=s, twist=1.4)
        parts.append(top)
    anchors.insert(0, anchor([0, H + 0.08, 0], [0, 1, 0]))
    return concat(parts), 2, anchors


def moonlit_lotus():
    """The legendary one: a lotus rosette of broad leaves around a tall stem
    that opens into a cup-shaped crown, the giant cola nested inside."""
    parts, anchors = [], []
    for r, (n, L, lift, droop, curl) in enumerate(((7, 0.62, 0.08, 0.12, 0.16), (5, 0.48, 0.5, 0.0, 0.2))):
        for k, a, d in ring(n, r * 0.4):
            # Broad Verdant leaves make the lily-pad rosette.
            br, _ = leaf_branch("verdant", d * 0.03, d + [0, lift, 0], L, width=1.8, droop=droop, curl=curl,
                                spin=a, squash=0.55, flat=r == 0, slot=1)
            parts.append(br)
    H = 0.86
    stem = Curve([[0, 0, 0], [0.03, H * 0.4, 0.0], [-0.02, H * 0.8, 0.02], [0, H, 0]])
    parts.append(trunk(stem, 0.03, taper=(1.0, 0.7), slot=1))
    for k, a, d in ring(5):
        br, _ = leaf_branch("starlit", [0, H - 0.05, 0], d + [0, 1.4, 0], 0.4, width=2.0, curl=0.06, spin=a, squash=0.65)
        parts.append(br)
    anchors.append(anchor([0, H + 0.12, 0], [0, 1, 0]))
    for k in (0, 4):
        a = k * 2 * math.pi / 8
        d = np.array([math.cos(a), 0.6, math.sin(a)])
        anchors.append(anchor(d * 0.34 + [0, 0.26, 0], d))
    return concat(parts), 2, anchors


# Per strain: recipe, atlas sources (slots, left to right), the palette baked
# into each source atlas, and the triangle budget (Godot adds LODs on import).
STRAINS = {
    "corkscrew": (corkscrew, ["ember"], {
        "ember": {"hue": 50, "sat": 1.1, "val": 1.05, "keep": (290, 30),
                  "grad": [(0.08, 0.2, 0.05), (0.35, 0.62, 0.12), (0.78, 0.95, 0.35), (1.0, 1.0, 0.75)], "grad_amt": 0.45}}, 8000),
    "mossy_mound": (mossy_mound, ["verdant"], {
        "verdant": {"hue": -10, "sat": 0.85, "val": 0.9,
                    "grad": [(0.05, 0.12, 0.06), (0.18, 0.38, 0.14), (0.45, 0.62, 0.25), (0.8, 0.85, 0.5)], "grad_amt": 0.55}}, 8500),
    "starfish": (starfish, ["starlit"], {
        "starlit": {"hue": -95, "sat": 1.1, "val": 1.05, "keep": (280, 340),
                    "grad": [(0.02, 0.12, 0.2), (0.08, 0.42, 0.5), (0.35, 0.82, 0.8), (0.9, 1.0, 0.95)], "grad_amt": 0.45}}, 7000),
    "sky_spire": (sky_spire, ["ember"], {
        "ember": {"hue": 70, "sat": 0.85, "val": 1.1,
                  "grad": [(0.15, 0.2, 0.05), (0.55, 0.6, 0.18), (0.9, 0.88, 0.45), (1.0, 1.0, 0.82)], "grad_amt": 0.5}}, 9500),
    "bubblegum": (bubblegum, ["verdant"], {
        "verdant": {"hue": 35, "sat": 1.2, "val": 1.08,
                    "grad": [(0.03, 0.2, 0.22), (0.1, 0.55, 0.55), (0.45, 0.9, 0.8), (1.0, 0.85, 0.95)], "grad_amt": 0.55}}, 9000),
    "moonfeather": (moonfeather, ["starlit"], {
        "starlit": {"sat": 0.5, "val": 1.15,
                    "grad": [(0.1, 0.14, 0.24), (0.38, 0.48, 0.62), (0.72, 0.82, 0.92), (0.95, 0.98, 1.0)], "grad_amt": 0.75}}, 9500),
    "lantern": (lantern, ["ember", "verdant"], {
        "ember": {"sat": 0.9, "val": 0.85,
                  "grad": [(0.02, 0.08, 0.08), (0.05, 0.3, 0.27), (0.28, 0.58, 0.42), (1.0, 0.82, 0.42)], "grad_amt": 0.6},
        "verdant": {"hue": -25, "sat": 0.8, "val": 0.9}}, 9000),
    "cloud_bonsai": (cloud_bonsai, ["ember", "verdant"], {
        "ember": {"hue": 160, "sat": 0.8, "val": 1.15,
                  "grad": [(0.3, 0.1, 0.18), (0.75, 0.38, 0.55), (0.98, 0.72, 0.84), (1.0, 0.95, 0.97)], "grad_amt": 0.6},
        "verdant": {"hue": -45, "sat": 0.55, "val": 0.85}}, 9500),
    "sunset_braid": (sunset_braid, ["ember", "starlit"], {
        "ember": {"hue": -150, "sat": 1.1, "val": 1.05,
                  "grad": [(0.25, 0.05, 0.03), (0.75, 0.25, 0.08), (1.0, 0.6, 0.25), (1.0, 0.9, 0.6)], "grad_amt": 0.5},
        "starlit": {"sat": 1.15, "grad": [(0.1, 0.03, 0.2), (0.38, 0.12, 0.55), (0.75, 0.45, 0.9), (1.0, 0.85, 1.0)], "grad_amt": 0.4}}, 9000),
    "moonlit_lotus": (moonlit_lotus, ["starlit", "verdant"], {
        "starlit": {"sat": 0.5, "val": 1.2,
                    "grad": [(0.32, 0.3, 0.52), (0.66, 0.66, 0.88), (0.9, 0.92, 1.0), (1.0, 1.0, 1.0)], "grad_amt": 0.75},
        "verdant": {"sat": 0.4, "grad": [(0.36, 0.37, 0.52), (0.64, 0.66, 0.84), (0.9, 0.92, 1.0)], "grad_amt": 0.8}}, 11000),
}


# ---------------------------------------------------------------------------
# Buds. Every one is normalised back to BUD_H tall, centred on its middle.
# The Meshy bud is a carved relief, so shapes come from scaling, twisting and
# clustering it: never smoothing, which would sand the calyxes away.

def bud_base(tris=2400):
    """The rounded Meshy bud (it is flat front to back: plump it up)."""
    m = lod("bud", tris)
    m.pos[:, 2] *= 1.45
    return m


def norm_bud(m):
    lo, hi = m.pos.min(0), m.pos.max(0)
    m.pos -= (lo + hi) * 0.5
    m.pos *= BUD_H / (hi[1] - lo[1])
    return m


def radial_fit(m, profile):
    """Scales each vertex's distance from the axis so the bud's outline
    follows profile(y in 0..1) while its bumps stay put."""
    y = (m.pos[:, 1] - m.pos[:, 1].min()) / np.ptp(m.pos[:, 1])
    bins = np.clip((y * 24).astype(int), 0, 23)
    r = np.linalg.norm(m.pos[:, [0, 2]], axis=1)
    env = np.array([np.percentile(r[bins == b], 85) if (bins == b).sum() > 3 else 1.0 for b in range(24)])
    env = np.convolve(np.pad(env, 2, mode="edge"), np.ones(5) / 5, mode="valid")
    s = profile(y) / np.maximum(env[bins], 1e-4)
    m.pos[:, [0, 2]] *= s[:, None]
    return m


def bud_twist():
    """Soft-serve swirl: stretched, wrung and tapered to a curl at the tip."""
    m = bud_base()
    m.pos[:, 1] *= 1.25
    y = (m.pos[:, 1] - m.pos[:, 1].min()) / np.ptp(m.pos[:, 1])
    m.pos[:, 0] *= 1.3
    a = y * 4.5
    x, z = m.pos[:, 0].copy(), m.pos[:, 2].copy()
    m.pos[:, 0], m.pos[:, 2] = x * np.cos(a) - z * np.sin(a), x * np.sin(a) + z * np.cos(a)
    m = radial_fit(m, lambda y: 0.36 * np.sin(np.clip(y * 1.05 + 0.08, 0, 1) * math.pi) ** 0.7 * (1 - 0.45 * y) + 0.02)
    m.pos[:, 0] += np.sin(y * 3.2) * 0.05
    return m


def bud_popcorn():
    """A lumpy cluster of little round nugs."""
    rng = np.random.default_rng(11)
    small = bud_base(900)
    small.pos[:, 1] *= 0.8
    parts = [xform(small, None, (0, 0.04, 0), 0.62)]
    for k in range(1, 7):
        a = k * GOLDEN
        y = 0.5 - (k / 7) * 1.0
        r = math.sqrt(max(0, 1 - y * y))
        c = np.array([math.cos(a) * r, y, math.sin(a) * r]) * 0.25
        parts.append(xform(small, rot([rng.random() - 0.5, 1, rng.random() - 0.5], rng.random() * 6), c, 0.44 + rng.random() * 0.08))
    return concat(parts)


def bud_star():
    """Five pointed spears radiating from a heart, like a little starfish."""
    parts = []
    spear = bud_base(800)
    spear.pos *= [0.6, 1.0, 0.7]
    spear.pos[:, 1] -= spear.pos[:, 1].min() + 0.05
    for k in range(5):
        parts.append(xform(spear, rot([0, 0, 1], k * 2 * math.pi / 5), (0, 0, 0), 0.6))
    parts.append(xform(bud_base(700), None, (0, 0, 0), 0.42))
    m = concat(parts)
    m.pos[:, 2] *= 1.2
    return m


def bud_foxtail():
    """A long spear of stacked calyxes, each smaller towards the tip."""
    parts = []
    b = bud_base(900)
    y = 0.0
    for k in range(5):
        s = 0.6 - k * 0.07
        parts.append(xform(b, rot([0, 1, 0], k * 1.3), (math.sin(k * 1.7) * 0.025, y, 0), s))
        y += s * 0.6
    m = concat(parts)
    m.pos[:, [0, 2]] *= 0.85
    return m


def bud_orb():
    """A gumball: round all over, calyxes intact."""
    m = bud_base()
    return radial_fit(m, lambda y: 0.48 * np.sqrt(np.clip(1 - (2 * y - 1) ** 2, 0, 1)) ** 0.85 + 0.015)


def bud_feather():
    """A long plume, plump where it hangs from the branch and drawn out to a
    fine curling tip (+Y is the tip; Moonfeather's buds point down)."""
    m = bud_base()
    m.pos *= [0.8, 1.9, 0.5]
    y = (m.pos[:, 1] - m.pos[:, 1].min()) / np.ptp(m.pos[:, 1])
    m = radial_fit(m, lambda y: 0.3 * np.sin(math.pi * (0.16 + 0.84 * y)) ** 0.6 * (1.0 - 0.5 * y) + 0.015)
    m.pos[:, 2] *= 0.7
    m.pos[:, 2] += np.sin(y * math.pi) * 0.16 - y * y * 0.12
    m.pos[:, 0] += np.sin(y * 2 * math.pi) * 0.05
    return m


def bud_lantern():
    """A paper lantern: round, squat and ribbed, pinched at both rims."""
    m = bud_base()
    m.pos[:, 1] *= 0.85
    m = radial_fit(m, lambda y: 0.5 * np.sqrt(np.clip(1 - (2 * y - 1) ** 2, 0, 1)) ** 0.6 * (1 - 0.3 * np.abs(2 * y - 1) ** 6) + 0.06)
    a = np.arctan2(m.pos[:, 2], m.pos[:, 0])
    m.pos[:, [0, 2]] *= (1.0 + 0.08 * np.cos(a * 8))[:, None]
    return m


def bud_cloud():
    """A flat, puffy cloud of soft nugs."""
    rng = np.random.default_rng(5)
    small = bud_base(900)
    small.pos[:, 1] *= 0.75
    parts = []
    for x, y, s in ((0, 0.06, 0.62), (-0.33, -0.04, 0.48), (0.33, -0.02, 0.5), (-0.15, 0.2, 0.42), (0.17, 0.21, 0.44), (0, -0.1, 0.52)):
        parts.append(xform(small, rot([0, 1, 0], rng.random() * 6), (x, y, (rng.random() - 0.5) * 0.2), s))
    m = concat(parts)
    m.pos[:, 2] *= 1.5
    return m


def bud_twin():
    """Two slim buds braided around each other."""
    parts = []
    for s in range(2):
        b = bud_base(1200)
        b.pos *= [0.55, 1.15, 0.55]
        y = (b.pos[:, 1] - b.pos[:, 1].min()) / np.ptp(b.pos[:, 1])
        a = y * 3.6 + s * math.pi
        b.pos[:, 0] += np.cos(a) * 0.12
        b.pos[:, 2] += np.sin(a) * 0.12
        parts.append(b)
    return concat(parts)


def bud_crown():
    """A royal cola: a tall centre ringed by petal-like nugs, like a flower."""
    centre = bud_base(1300)
    centre.pos *= [0.8, 1.15, 0.8]
    parts = [centre]
    petal = bud_base(500)
    petal.pos *= [0.55, 0.8, 0.45]
    petal.pos[:, 1] -= petal.pos[:, 1].min()
    for k in range(6):
        a = k * 2 * math.pi / 6
        R = rot([math.cos(a + math.pi / 2), 0, math.sin(a + math.pi / 2)], 0.95) @ rot([0, 1, 0], -a)
        parts.append(xform(petal, R, (0, -0.4, 0), 0.75))
    return concat(parts)


# Per strain: shape, gradient-map palette for the bud atlas (dark to light;
# `keep` spares the orange pistil hairs), and the triangle budget.
PISTILS = (12, 48)
BUDS = {
    "corkscrew": (bud_twist, {"stops": [(0.1, 0.22, 0.04), (0.42, 0.7, 0.12), (0.85, 1.0, 0.4), (1.0, 1.0, 0.85)], "keep": PISTILS}, 2200),
    "mossy_mound": (bud_popcorn, {"stops": [(0.06, 0.14, 0.05), (0.25, 0.45, 0.15), (0.62, 0.75, 0.32), (0.92, 0.95, 0.7)], "keep": PISTILS}, 2600),
    "starfish": (bud_star, {"stops": [(0.25, 0.05, 0.06), (0.75, 0.3, 0.25), (1.0, 0.66, 0.5), (1.0, 0.95, 0.85)]}, 2400),
    "sky_spire": (bud_foxtail, {"stops": [(0.2, 0.18, 0.04), (0.6, 0.58, 0.16), (0.95, 0.9, 0.45), (1.0, 1.0, 0.85)], "keep": PISTILS}, 2600),
    "bubblegum": (bud_orb, {"stops": [(0.3, 0.04, 0.2), (0.8, 0.3, 0.6), (1.0, 0.65, 0.85), (1.0, 0.95, 1.0)]}, 2000),
    "moonfeather": (bud_feather, {"stops": [(0.12, 0.16, 0.3), (0.45, 0.55, 0.75), (0.8, 0.88, 1.0), (1.0, 1.0, 1.0)]}, 2000),
    "lantern": (bud_lantern, {"stops": [(0.35, 0.1, 0.02), (0.85, 0.42, 0.06), (1.0, 0.75, 0.3), (1.0, 0.97, 0.75)]}, 2000),
    "cloud_bonsai": (bud_cloud, {"stops": [(0.45, 0.32, 0.42), (0.85, 0.7, 0.8), (1.0, 0.9, 0.95), (1.0, 1.0, 1.0)]}, 2600),
    "sunset_braid": (bud_twin, {"stops": [(0.25, 0.04, 0.15), (0.8, 0.25, 0.3), (1.0, 0.6, 0.4), (1.0, 0.9, 0.7)], "keep": PISTILS}, 2200),
    "moonlit_lotus": (bud_crown, {"stops": [(0.15, 0.12, 0.35), (0.55, 0.52, 0.85), (0.88, 0.88, 1.0), (1.0, 1.0, 1.0)]}, 2800),
}


def forge(sid, out_dir):
    fn, srcs, palette, target = STRAINS[sid]
    m, nslots, anchors = fn()
    assert nslots == len(srcs), sid
    img = atlas(srcs, palette)
    raw, tris, lo, hi = write(os.path.join(out_dir, sid + ".glb"), m, [(jpeg_bytes(img), "image/jpeg")], target, nslots)
    with open(os.path.join(out_dir, sid + ".json"), "w") as f:
        json.dump({"height": round(float(hi[1]), 4), "spread": round(float(max(-lo[0], hi[0], -lo[2], hi[2])), 4),
                   "buds": anchors[:3]}, f, indent=1)
    shape, bpal, btarget = BUDS[sid]
    b = norm_bud(shape())
    bimg = gradient_map(source("bud")[1].resize((BUD_TEX, BUD_TEX), Image.LANCZOS), bpal["stops"], 0.85, bpal.get("keep"))
    nimg = source("bud")[2].resize((BUD_TEX // 2, BUD_TEX // 2), Image.LANCZOS)
    braw, btris, blo, bhi = write(os.path.join(out_dir, sid + "_bud.glb"), b,
                                  [(jpeg_bytes(bimg), "image/jpeg"), (png_bytes(nimg), "image/png")], btarget)
    print("%-14s plant %6d -> %5d tris  %.2f m tall, %.2f m spread | bud %6d -> %5d tris" %
          (sid, raw, tris, hi[1], max(-lo[0], hi[0], -lo[2], hi[2]), braw, btris))


def main():
    global SRC_DIR
    SRC_DIR, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    ids = sys.argv[3:] or list(STRAINS)
    for sid in ids:
        forge(sid, out_dir)
    write_shapes(out_dir)


def write_shapes(out_dir):
    """Bakes every strain's bud anchors into world/weed/strain_shapes.gd (the
    json sidecars aren't exported with the game)."""
    lines = ["class_name StrainShapes", "extends RefCounted",
             "## GENERATED by tools/strain_forge.py: do not edit by hand.",
             "## Per forged strain: model height and spread (metres) and where its",
             "## buds grow (position in model space + the way the bud points).", "",
             "const SHAPES := {"]
    for sid in STRAINS:
        path = os.path.join(out_dir, sid + ".json")
        if not os.path.exists(path):
            continue
        d = json.load(open(path))
        v = lambda a: "Vector3(%s)" % ", ".join("%.4f" % x for x in a)
        buds = ", ".join("[%s, %s]" % (v(b["pos"]), v(b["dir"])) for b in d["buds"])
        lines.append('\t&"%s": {"height": %.4f, "spread": %.4f, "buds": [%s]},' % (sid, d["height"], d["spread"], buds))
    lines.append("}")
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(os.path.join(root, "world", "weed", "strain_shapes.gd"), "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
