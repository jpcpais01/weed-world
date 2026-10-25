#!/usr/bin/env python3
"""Builds the spirit owl of Owl Flight from João's Meshy owl.

Meshy gave a 31k-triangle owl, wings spread, with an 8K texture set and a
Smart Rig that's no use to a bird (its wings are a single plate). The owl is
never skinned: owl_spirit.gdshader flaps the wings itself, so this only has
to hand it a clean, light mesh that knows its own anatomy:

  * pitched level (Meshy posed it climbing at ~35 degrees), scaled up to a
    giant owl (~10.7 m wingspan) and moved so the origin is the rider's seat
    on its back between the wing roots, +Z forward, +Y up, +X its left,
  * COLOR_0 per vertex: r = wing (0 body .. 1 wing plate), g = tail plume
    (0 at its root .. 1 at its tip), b = head, a = the glowing eyes,
  * TEXCOORD_1 per vertex: x = how far out along the wing (0 at the shoulder
    .. 1 at the tip), y = where across it (0 leading edge .. 1 trailing edge,
    where the feathers fray into smoke). Off the wings x is 0,
  * simplified with meshoptimizer (seams kept) to ~10k triangles and
    reordered for the vertex cache; normals and UVs untouched,
  * one 1024 albedo (the ghost shader only reads its feather pattern and
    the eyes' colour); the normal and metal maps are dropped.

It also writes spirit_owl.json: the hinge points the shader flaps about (the
script mirrors the flap for the wingtip trails), the tips of the wings and
tail plumes, the eyes, and points scattered over the body for the smoke that
gathers into the owl and pours off it.

usage: pip install numpy pillow meshoptimizer
       python3 tools/owl_asset.py --slim <meshy_upload.glb>   (once: writes the slim source)
       python3 tools/owl_asset.py [--debug <dir>]
  reads  art_source/owl/spirit_owl_meshy.glb
  writes assets/fx/owl/spirit_owl.glb, spirit_owl.json, ghost_feather.png
"""
import io, json, math, os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rig_keling import read_glb, write_glb, accessor_array, add_accessor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art_source/owl/spirit_owl_meshy.glb")
OUT = os.path.join(ROOT, "assets/fx/owl")

PITCH = math.radians(35.0)     # nose-down turn that levels the climbing pose
SCALE = 2.0                    # Meshy's owl is 5.35 m across; ours ~10.7 m
SEAT_Z = 0.62                  # the rider sits here along the back (source m, after levelling)
TARGET_TRIS = 10000
TEX = 1024


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def slim(upload):
    """The upload minus what we never use (skin, 8K maps): the committed source."""
    j, b = read_glb(upload)
    pr = j["meshes"][0]["primitives"][0]
    at = pr["attributes"]
    nj = {"asset": {"version": "2.0", "generator": "weed-world owl_asset.py --slim"},
          "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "SpiritOwl", "mesh": 0}],
          "meshes": [], "accessors": [], "bufferViews": [], "buffers": [{"byteLength": 0}],
          "materials": [{"name": "SpiritOwl", "doubleSided": True, "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
          "textures": [{"source": 0, "sampler": 0}],
          "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
          "images": []}
    nb = bytearray()
    a_pos = add_accessor(nj, nb, accessor_array(j, b, at["POSITION"])[0], 5126, "VEC3", True, 34962)
    a_nrm = add_accessor(nj, nb, accessor_array(j, b, at["NORMAL"])[0], 5126, "VEC3", False, 34962)
    a_uv = add_accessor(nj, nb, accessor_array(j, b, at["TEXCOORD_0"])[0], 5126, "VEC2", False, 34962)
    a_idx = add_accessor(nj, nb, accessor_array(j, b, pr["indices"])[0].reshape(-1).astype(np.uint32), 5125, "SCALAR", False, 34963)
    nj["meshes"].append({"name": "SpiritOwl", "primitives": [
        {"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv}, "indices": a_idx, "material": 0}]})
    data = image_bytes(j, b, j["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"], 2048, 92)
    nj["bufferViews"].append({"buffer": 0, "byteOffset": len(nb), "byteLength": len(data)})
    nb += data
    nj["images"].append({"bufferView": len(nj["bufferViews"]) - 1, "mimeType": "image/jpeg"})
    os.makedirs(os.path.dirname(SRC), exist_ok=True)
    write_glb(SRC, nj, nb)
    print("wrote", SRC, os.path.getsize(SRC) // 1024, "KB")


def image_bytes(j, b, tex_index, size, quality):
    img = j["images"][j["textures"][tex_index]["source"]]
    bv = j["bufferViews"][img["bufferView"]]
    o = bv.get("byteOffset", 0)
    im = Image.open(io.BytesIO(bytes(b[o:o + bv["byteLength"]]))).convert("RGB").resize((size, size), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, "JPEG", quality=quality)
    return out.getvalue()


def level(P, N):
    """Pitch the owl nose-down about its middle so it flies level."""
    c, s = math.cos(PITCH), math.sin(PITCH)
    piv = np.array([0.0, 0.85, 0.4])
    Q = P - piv
    Y = Q[:, 1] * c - Q[:, 2] * s
    Z = Q[:, 1] * s + Q[:, 2] * c
    L = np.stack([Q[:, 0], Y, Z], 1) + piv
    NY = N[:, 1] * c - N[:, 2] * s
    NZ = N[:, 1] * s + N[:, 2] * c
    return L, np.stack([N[:, 0], NY, NZ], 1)


def anatomy(P0, L, alb):
    """Per-vertex masks, measured in the source pose (P0) where the parts are
    easy to tell apart, plus wing span/chord coordinates in the level pose."""
    x, y, z = P0[:, 0], P0[:, 1], P0[:, 2]
    ax = np.abs(x)
    # Wing plates: out past the shoulders, high and forward of the tail.
    wing = smoothstep(0.36, 0.62, ax) * smoothstep(0.55, 0.75, y) * smoothstep(0.25, 0.45, z)
    # Tail plumes: the two long feathers trailing behind (0 at their root).
    tail = smoothstep(-0.25, -1.6, z) * smoothstep(0.25, 0.4, ax)
    tail = np.maximum(tail, smoothstep(-0.35, -0.9, z) * 0.6)
    head = smoothstep(0.95, 1.15, z) * smoothstep(0.5, 0.35, ax) * smoothstep(0.95, 1.1, y)
    # Eyes: the bright cyan of the albedo on the face.
    eye = ((alb[:, 1] > 170) & (alb[:, 2] > 170) & (alb[:, 0] < 150)).astype(float) * head
    eye *= smoothstep(1.3, 1.42, z)

    # Span 0 at the shoulder .. 1 at the tip; chord 0 leading .. 1 trailing,
    # per thin slice across the span (in the level pose, chord runs along z).
    lx = np.abs(L[:, 0])
    span = np.clip((lx - 0.45) / (lx.max() - 0.45), 0.0, 1.0) * (wing > 0.05)
    chord = np.zeros(len(L))
    m = wing > 0.3
    bins = np.floor(lx / 0.06).astype(int)
    for k in np.unique(bins[m]):
        sel = m & (bins == k)
        zmax, zmin = np.percentile(L[sel, 2], 98), np.percentile(L[sel, 2], 2)
        sl = (bins == k) & (wing > 0.05)
        chord[sl] = np.clip((zmax - L[sl, 2]) / max(zmax - zmin, 0.05), 0.0, 1.0)
    return wing, tail, head, eye, span, chord


def simplify(L, I, target):
    import meshoptimizer as mo
    pos = np.ascontiguousarray(L.astype(np.float32))
    idx = np.ascontiguousarray(I.reshape(-1).astype(np.uint32))
    dst = np.zeros_like(idx)
    err = np.zeros(1, dtype=np.float32)
    n = mo.simplify(dst, idx, pos, target_index_count=target * 3, target_error=0.02, result_error=err)
    out = dst[:n].copy()
    cache = np.zeros_like(out)
    mo.optimize_vertex_cache(cache, out, vertex_count=len(pos))
    print("simplified %d -> %d triangles (error %.4f)" % (len(I), n // 3, float(err[0])))
    return cache.reshape(-1, 3)


def compact(I, *arrays):
    used = np.unique(I)
    remap = np.full(int(I.max()) + 1, -1, np.int64)
    remap[used] = np.arange(len(used))
    return remap[I].astype(np.uint32), [a[used] for a in arrays]


def main():
    if "--slim" in sys.argv:
        slim(sys.argv[sys.argv.index("--slim") + 1])
        return
    debug = sys.argv[sys.argv.index("--debug") + 1] if "--debug" in sys.argv else None
    j, b = read_glb(SRC)
    pr = j["meshes"][0]["primitives"][0]
    at = pr["attributes"]
    P0 = accessor_array(j, b, at["POSITION"])[0].astype(float)
    N0 = accessor_array(j, b, at["NORMAL"])[0].astype(float)
    UV = accessor_array(j, b, at["TEXCOORD_0"])[0].astype(np.float32)
    I = accessor_array(j, b, pr["indices"])[0].reshape(-1, 3).astype(np.uint32)
    img = j["images"][0]
    bv = j["bufferViews"][img["bufferView"]]
    o = bv.get("byteOffset", 0)
    tex = Image.open(io.BytesIO(bytes(b[o:o + bv["byteLength"]]))).convert("RGB")
    T = np.asarray(tex.resize((1024, 1024))).astype(int)
    uvp = (np.clip(UV, 0, 0.9999) * 1024).astype(int)
    alb = T[uvp[:, 1], uvp[:, 0]]

    L, NL = level(P0, N0)
    wing, tail, head, eye, span, chord = anatomy(P0, L, alb)

    # The seat: on top of the back at SEAT_Z, between the wing roots.
    back = (np.abs(L[:, 0]) < 0.22) & (np.abs(L[:, 2] - SEAT_Z) < 0.08)
    seat = np.array([0.0, np.percentile(L[back, 1], 97) + 0.01, SEAT_Z])
    S = (L - seat) * SCALE
    print("seat (source, level) %s, %d vertices" % (seat.round(3).tolist(), len(S)))

    I2 = simplify(S, I, TARGET_TRIS)
    color = np.stack([wing, tail, head, eye], 1)
    uv2 = np.stack([span, chord], 1)
    I2, (S2, N2, UV2, C2, U22) = compact(I2, S, NL, UV, color, uv2)

    # Landmarks the script needs (owl space, metres).
    lx = np.abs(S[:, 0])
    tipL = S[np.argmax(S[:, 0] * (wing > 0.5))]
    tipR = S[np.argmin(S[:, 0] * (wing > 0.5))]
    tails = []
    for side in (1, -1):
        m = (tail > 0.5) & (np.sign(S[:, 0]) == side)
        tails.append(S[m][np.argmin(S[m, 2])])
    shoulder_x = 0.45 * SCALE
    wingm = wing > 0.5
    hinge_y = float(np.median(S[wingm & (lx < shoulder_x + 0.3), 1]))
    hinge_z = float(np.median(S[wingm & (lx < shoulder_x + 0.3), 2]))
    eyes = []
    for side in (1, -1):
        m = (eye > 0.5) & (np.sign(S[:, 0]) == side)
        eyes.append(S[m].mean(0) if m.sum() else S[head > 0.5].mean(0))
    rng = np.random.default_rng(3)
    # Points over the surface (area-weighted) for smoke to gather into / pour off.
    tri = S[I]
    area = np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1) * 0.5
    pick = rng.choice(len(I), 192, p=area / area.sum())
    bc = rng.dirichlet([1, 1, 1], 192)
    pts = (tri[pick] * bc[:, :, None]).sum(1)
    ptw = (np.stack([wing, tail], 1)[I[pick]] * bc[:, :, None]).sum(1)
    ptc = (uv2[I[pick]] * bc[:, :, None]).sum(1)
    meta = {
        "scale": SCALE,
        "min": S.min(0).round(3).tolist(), "max": S.max(0).round(3).tolist(),
        "shoulder": [round(shoulder_x, 3), round(hinge_y, 3), round(hinge_z, 3)],
        "wrist_x": round(1.35 * SCALE, 3),
        "span_x": round(float(lx.max()), 3),
        "wing_tips": [tipL.round(3).tolist(), tipR.round(3).tolist()],
        "tail_tips": [t.round(3).tolist() for t in tails],
        "eyes": [e.round(3).tolist() for e in eyes],
        "head": S[head > 0.5].mean(0).round(3).tolist(),
        "chest": S[(lx < 0.3) & (head < 0.1) & (tail < 0.1) & (S[:, 1] < -0.3)].mean(0).round(3).tolist(),
        "points": [[round(float(v), 3) for v in list(p) + [w[0], w[1], c[0], c[1]]] for p, w, c in zip(pts, ptw, ptc)],
    }

    nj = {"asset": {"version": "2.0", "generator": "weed-world owl_asset.py"},
          "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "SpiritOwl", "mesh": 0}],
          "meshes": [], "accessors": [], "bufferViews": [], "buffers": [{"byteLength": 0}],
          "materials": [{"name": "SpiritOwl", "doubleSided": True, "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
          "textures": [{"source": 0, "sampler": 0}],
          "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
          "images": []}
    nb = bytearray()
    a_pos = add_accessor(nj, nb, S2.astype(np.float32), 5126, "VEC3", True, 34962)
    a_nrm = add_accessor(nj, nb, (N2 / np.linalg.norm(N2, axis=1, keepdims=True)).astype(np.float32), 5126, "VEC3", False, 34962)
    a_uv = add_accessor(nj, nb, UV2.astype(np.float32), 5126, "VEC2", False, 34962)
    a_uv2 = add_accessor(nj, nb, U22.astype(np.float32), 5126, "VEC2", False, 34962)
    a_col = add_accessor(nj, nb, np.round(np.clip(C2, 0, 1) * 255).astype(np.uint8), 5121, "VEC4", "norm", 34962)
    a_idx = add_accessor(nj, nb, I2.reshape(-1), 5125, "SCALAR", False, 34963)
    nj["meshes"].append({"name": "SpiritOwl", "primitives": [
        {"attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv, "TEXCOORD_1": a_uv2, "COLOR_0": a_col},
         "indices": a_idx, "material": 0}]})
    out = io.BytesIO()
    tex.resize((TEX, TEX), Image.LANCZOS).save(out, "JPEG", quality=90)
    data = out.getvalue()
    while len(nb) % 4:
        nb.append(0)
    nj["bufferViews"].append({"buffer": 0, "byteOffset": len(nb), "byteLength": len(data)})
    nb += data
    nj["images"].append({"bufferView": len(nj["bufferViews"]) - 1, "mimeType": "image/jpeg"})
    os.makedirs(OUT, exist_ok=True)
    write_glb(os.path.join(OUT, "spirit_owl.glb"), nj, nb)
    feather(os.path.join(OUT, "ghost_feather.png"))
    with open(os.path.join(OUT, "spirit_owl.json"), "w") as fh:
        json.dump(meta, fh, separators=(",", ":"))
    print("wrote", os.path.join(OUT, "spirit_owl.glb"), "%d KB," % (os.path.getsize(os.path.join(OUT, "spirit_owl.glb")) // 1024),
          len(S2), "vertices", len(I2), "triangles; span %.2f m" % (2 * meta["span_x"]))

    if debug:
        os.makedirs(debug, exist_ok=True)
        cols = np.stack([60 + 195 * wing, 60 + 195 * tail, 60 + 195 * np.maximum(head, eye)], 1).astype(np.uint8)
        cols[eye > 0.5] = (255, 255, 255)
        views(S, cols, debug, "masks")
        ch = np.stack([255 * chord, 255 * span, 80 + 0 * span], 1).astype(np.uint8)
        views(S, ch, debug, "span_chord")


def feather(path, w=64, h=160):
    """A soft glowing feather for the ones the owl sheds: a bright quill, barbs
    sweeping out from it, a ragged, wispy vane. White; the shader tints it."""
    y, x = np.mgrid[0:h, 0:w].astype(float)
    v = 1.0 - y / (h - 1)                    # 0 at the quill's base .. 1 tip
    u = (x - (w - 1) / 2) / ((w - 1) / 2)    # -1 .. 1 across
    bend = 0.12 * np.sin(v * np.pi)          # a gentle curve
    uu = u - bend
    halfw = np.clip(np.sin(np.clip((v - 0.04) / 0.98, 0, 1) * np.pi) ** 0.6, 0, 1) * (0.86 - 0.18 * v)
    inside = np.clip((halfw - np.abs(uu)) / 0.18, 0, 1)
    rng = np.random.default_rng(9)
    ragged = 0.75 + 0.25 * np.sin(v * 37 + rng.random() * 6) * np.sin(v * 13 + 1.7)
    barbs = 0.6 + 0.4 * np.sin((v * 60 - np.abs(uu) * 22))
    vane = inside * barbs * np.clip(ragged + 0.4 - np.abs(uu), 0, 1)
    quill = np.exp(-(uu / 0.05) ** 2) * (v > 0.02) * (1.0 - 0.5 * v)
    a = np.clip(vane * 0.75 + quill, 0, 1)
    rgb = np.clip(0.75 + 0.25 * quill + 0.1 * barbs, 0, 1)
    img = np.dstack([rgb * 255, rgb * 255, rgb * 255, a * 255]).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(path, optimize=True)


def views(P, col, out, name):
    from PIL import ImageDraw
    sc = 70
    pan = []
    for h, v, d, flip in [(2, 1, 0, False), (0, 2, 1, True), (0, 1, 2, True)]:
        W = int(np.ptp(P[:, h]) * sc) + 40
        H = int(np.ptp(P[:, v]) * sc) + 40
        im = np.full((H, W, 3), 30, np.uint8)
        X = ((P[:, h] - P[:, h].min()) * sc + 20).astype(int)
        Y = (H - 20 - (P[:, v] - P[:, v].min()) * sc).astype(int)
        if flip:
            X = W - 1 - X
        for i in np.argsort(P[:, d] * (-1 if d == 1 else 1)):
            im[max(Y[i] - 1, 0):Y[i] + 2, max(X[i] - 1, 0):X[i] + 2] = col[i]
        pim = Image.fromarray(im)
        dr = ImageDraw.Draw(pim)
        ox = (0 - P[:, h].min()) * sc + 20
        ox = W - 1 - ox if flip else ox
        oy = H - 20 - (0 - P[:, v].min()) * sc
        dr.line([(ox - 8, oy), (ox + 8, oy)], fill=(255, 60, 60), width=2)
        dr.line([(ox, oy - 8), (ox, oy + 8)], fill=(255, 60, 60), width=2)
        pan.append(pim)
    W = sum(p.width for p in pan)
    H = max(p.height for p in pan)
    sheet = Image.new("RGB", (W, H), (30, 30, 30))
    x = 0
    for p in pan:
        sheet.paste(p, (x, 0))
        x += p.width
    sheet.save(os.path.join(out, name + ".png"))


if __name__ == "__main__":
    main()
